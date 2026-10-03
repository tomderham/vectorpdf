//
// VectorPDF
// Copyright (c) 2026 Thomas Derham
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This application links to and incorporates the MuPDF framework, which is
// Copyright (c) 2006-2026 Artifex Software, Inc.
//
// VECTORPDF IS PROVIDED "AS IS" WITHOUT ANY WARRANTY, AND ALL
// WARRANTIES, WHETHER EXPRESSED OR IMPLIED, INCLUDING WARRANTY OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, ARE DISCLAIMED.
//

import Foundation
import CoreGraphics
import MuPDFBridge

final class RenderResource: @unchecked Sendable {
    let ctx: FZContext
    var doc: FZDocument?
    let listCache: PDFDisplayListCache
    /// Each page's native (untransformed) bounds in PDF-space points, recorded the first time it's
    /// actually loaded — used both to clamp the rendered pixel size at high zoom (see renderPage's
    /// maxRenderDimension) without reloading the page just to re-check its bounds on a display-list
    /// cache hit, and to report a page's real bounds back to PDFDocumentCore the first time it's
    /// rendered (see renderPage's RenderedPage result and PDFDocumentCore.recordActualPageBounds).
    var pageBoundsCache: [Int: CGRect] = [:]

    init(cacheCapacity: Int) {
        self.ctx = PDFContextManager.shared.makeClonedContext()
        self.listCache = PDFDisplayListCache(capacity: cacheCapacity)
    }
    
    deinit {
        listCache.removeAll(ctx: ctx)
        if let d = doc {
            mupdf_document_drop(ctx, d)
        }
        PDFContextManager.shared.dropContext(ctx)
    }
}

public actor PDFRenderActor {
    private let resource: RenderResource
    private var currentPath: String?
    
    public init(cacheCapacity: Int = 4) {
        self.resource = RenderResource(cacheCapacity: cacheCapacity)
    }
    
    public func openDocument(filePath: String, password: String? = nil) throws {
        // Keep existing document open until replacement is opened and authenticated.
        var docPtr: FZDocument?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_document_open(resource.ctx, filePath, &docPtr, &errorMsg)
        guard ret == 0, let d = docPtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to open document for rendering"
            throw PDFError.openFailed(msg)
        }

        // Authenticate the actor's independent document instance.
        var needsPassword: Int32 = 0
        mupdf_document_needs_password(resource.ctx, d, &needsPassword, &errorMsg)
        if needsPassword != 0 {
            guard let password else {
                mupdf_document_drop(resource.ctx, d)
                throw PDFError.passwordRequired
            }
            var authenticated: Int32 = 0
            mupdf_document_authenticate_password(resource.ctx, d, password, &authenticated, &errorMsg)
            guard authenticated != 0 else {
                mupdf_document_drop(resource.ctx, d)
                throw PDFError.incorrectPassword
            }
        }

        resource.listCache.removeAll(ctx: resource.ctx)
        resource.pageBoundsCache.removeAll()
        if let old = resource.doc {
            mupdf_document_drop(resource.ctx, old)
        }
        self.resource.doc = d
        self.currentPath = filePath
    }
    
    /// Maximum pixel dimension for a rendered page bitmap to bound memory usage at high zoom.
    private static let maxRenderDimension: Float = 4096

    /// Result of rendering a page: the bitmap and the page's native bounds.
    // CGImage isn't marked Sendable by its own SDK overlay, though it's an immutable value once
    // created — safe to cross the actor boundary here as @unchecked Sendable on that basis.
    public struct RenderedPage: @unchecked Sendable {
        public let image: CGImage
        public let nativeBounds: CGRect
    }

    /// Renders a page at the specified scale (e.g. 2.0 for Retina) into a CGImage
    public func renderPage(pageIndex: Int, scale: CGFloat) throws -> RenderedPage {
        guard let doc = self.resource.doc else {
            throw PDFError.openFailed("No document opened in render actor")
        }

        let ctx = resource.ctx
        let requestedScale = Float(scale)
        var pixmapPtr: FZPixmap?
        var errorMsg: UnsafePointer<CChar>?

        // Check display list cache first
        if let cachedList = resource.listCache.get(pageIndex: pageIndex), let cachedBounds = resource.pageBoundsCache[pageIndex] {
            let scaleF = Self.clampedScale(requestedScale, pageBounds: cachedBounds)
            let ret = mupdf_render_display_list(ctx, cachedList, scaleF, scaleF, &pixmapPtr, &errorMsg)
            guard ret == 0, let pix = pixmapPtr else {
                let msg = errorMsg != nil ? String(cString: errorMsg!) : "Render display list failed"
                throw PDFError.renderFailed(msg)
            }
            defer { mupdf_pixmap_drop(ctx, pix) }
            return RenderedPage(image: try makeCGImage(from: pix), nativeBounds: cachedBounds)
        }

        // Load page
        var pagePtr: FZPage?
        let loadRet = mupdf_page_load(ctx, doc, Int32(pageIndex), &pagePtr, &errorMsg)
        guard loadRet == 0, let page = pagePtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to load page"
            throw PDFError.pageLoadFailed(pageIndex, msg)
        }
        defer { mupdf_page_drop(ctx, page) }

        var rect = fz_rect()
        mupdf_page_bounds(ctx, page, &rect, nil)
        let pageBounds = CGRect(x: CGFloat(rect.x0), y: CGFloat(rect.y0), width: CGFloat(rect.x1 - rect.x0), height: CGFloat(rect.y1 - rect.y0))
        resource.pageBoundsCache[pageIndex] = pageBounds
        let scaleF = Self.clampedScale(requestedScale, pageBounds: pageBounds)

        // Create display list and insert into cache
        var listPtr: FZDisplayList?
        if mupdf_display_list_create(ctx, page, &listPtr, nil) == 0, let list = listPtr {
            resource.listCache.insert(pageIndex: pageIndex, list: list, ctx: ctx)
            let ret = mupdf_render_display_list(ctx, list, scaleF, scaleF, &pixmapPtr, &errorMsg)
            guard ret == 0, let pix = pixmapPtr else {
                let msg = errorMsg != nil ? String(cString: errorMsg!) : "Render display list failed"
                throw PDFError.renderFailed(msg)
            }
            defer {
                mupdf_pixmap_drop(ctx, pix)
                _ = mupdf_context_shrink_store(ctx, 50)
            }
            return RenderedPage(image: try makeCGImage(from: pix), nativeBounds: pageBounds)
        } else {
            // Fallback to direct page render
            let ret = mupdf_render_page(ctx, page, scaleF, scaleF, &pixmapPtr, &errorMsg)
            guard ret == 0, let pix = pixmapPtr else {
                let msg = errorMsg != nil ? String(cString: errorMsg!) : "Direct page render failed"
                throw PDFError.renderFailed(msg)
            }
            defer {
                mupdf_pixmap_drop(ctx, pix)
                _ = mupdf_context_shrink_store(ctx, 50)
            }
            return RenderedPage(image: try makeCGImage(from: pix), nativeBounds: pageBounds)
        }
    }

    /// Renders a specific rectangular sub-region of a page (in native PDF point coordinates) at the specified scale.
    public func renderPageRect(pageIndex: Int, rect: CGRect, scale: CGFloat) throws -> CGImage {
        guard let doc = self.resource.doc else {
            throw PDFError.openFailed("No document opened in render actor")
        }

        let ctx = resource.ctx
        let scaleF = Float(scale)
        var pixmapPtr: FZPixmap?
        var errorMsg: UnsafePointer<CChar>?

        var pagePtr: FZPage?
        let loadRet = mupdf_page_load(ctx, doc, Int32(pageIndex), &pagePtr, &errorMsg)
        guard loadRet == 0, let page = pagePtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to load page"
            throw PDFError.pageLoadFailed(pageIndex, msg)
        }
        defer { mupdf_page_drop(ctx, page) }

        let ret = mupdf_render_page_rect(
            ctx, page, scaleF, scaleF,
            Float(rect.minX), Float(rect.minY), Float(rect.maxX), Float(rect.maxY),
            &pixmapPtr, &errorMsg
        )
        guard ret == 0, let pix = pixmapPtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Render page rect failed"
            throw PDFError.renderFailed(msg)
        }
        defer {
            mupdf_pixmap_drop(ctx, pix)
            _ = mupdf_context_shrink_store(ctx, 50)
        }
        return try makeCGImage(from: pix)
    }

    /// Scales down `requestedScale` (never up) so the resulting bitmap's longest edge doesn't
    /// exceed maxRenderDimension.
    private static func clampedScale(_ requestedScale: Float, pageBounds: CGRect) -> Float {
        guard pageBounds.width > 0, pageBounds.height > 0 else { return requestedScale }
        let longestEdge = Float(max(pageBounds.width, pageBounds.height)) * requestedScale
        guard longestEdge > maxRenderDimension else { return requestedScale }
        return requestedScale * (maxRenderDimension / longestEdge)
    }
    
    private func makeCGImage(from pix: FZPixmap) throws -> CGImage {
        let w = Int(mupdf_pixmap_width(pix))
        let h = Int(mupdf_pixmap_height(pix))
        let stride = Int(mupdf_pixmap_stride(pix))
        let n = Int(mupdf_pixmap_n(pix))
        guard let samples = mupdf_pixmap_samples(pix), w > 0, h > 0 else {
            throw PDFError.renderFailed("Empty pixmap samples")
        }
        
        let dataLength = stride * h
        let data = Data(bytes: samples, count: dataLength)
        guard let dataProvider = CGDataProvider(data: data as CFData) else {
            throw PDFError.renderFailed("Failed to create CGDataProvider")
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo
        if n == 4 {
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        } else {
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        }
        
        guard let image = CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: n * 8,
            bytesPerRow: stride,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw PDFError.renderFailed("Failed to create CGImage")
        }
        
        return image
    }
}
