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
        // Always actually (re-)open below, even if filePath matches currentPath — the caller only
        // invokes this when it genuinely wants a (re)load, including the same path after a save.
        resource.listCache.removeAll(ctx: resource.ctx)
        resource.pageBoundsCache.removeAll()
        if let d = resource.doc {
            mupdf_document_drop(resource.ctx, d)
            resource.doc = nil
        }

        var docPtr: FZDocument?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_document_open(resource.ctx, filePath, &docPtr, &errorMsg)
        guard ret == 0, let d = docPtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to open document for rendering"
            throw PDFError.openFailed(msg)
        }

        // This actor holds its own separate fz_document instance in its own cloned context, so
        // it needs its own authentication too — PDFDocumentCore's own check (used to decide
        // whether to even prompt for a password in the first place) doesn't cover this instance.
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

        self.resource.doc = d
        self.currentPath = filePath
    }
    
    /// Longest edge, in pixels, a single rendered page bitmap is allowed to reach — at zoomScale
    /// 4.0 (rendered at 8x, see PDFViewerViewModel.renderPage) a standard page would otherwise
    /// produce a ~124 MB uncompressed RGBA bitmap; clamping the actual render scale keeps memory
    /// bounded even at maximum zoom, at the cost of not exceeding "native resolution" sharpness
    /// beyond this size (the view still scales the result up to fill the zoomed frame).
    private static let maxRenderDimension: Float = 4096

    /// Result of rendering a page: the bitmap itself, plus the page's real native (unscaled) bounds
    /// in PDF-space points — used by PDFViewerViewModel to correct PDFDocumentCore's layout the
    /// first time a page turns out not to match the placeholder it was assumed to share (see
    /// PDFDocumentCore.recordActualPageBounds).
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
