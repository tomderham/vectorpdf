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
import AppKit
import MuPDFBridge

public enum PDFError: Error, LocalizedError, Equatable {
    case openFailed(String)
    case pageLoadFailed(Int, String)
    case renderFailed(String)
    case stextFailed(String)
    case saveFailed(String)
    case operationFailed(String)
    case outOfBounds(Int)
    /// The document is encrypted and no password was supplied yet — distinct from
    /// `incorrectPassword` so the caller knows to prompt for the first time rather than show a
    /// "wrong password" message.
    case passwordRequired
    /// A password was supplied but didn't authenticate.
    case incorrectPassword

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "Failed to open document: \(msg)"
        case .pageLoadFailed(let p, let msg): return "Failed to load page \(p): \(msg)"
        case .renderFailed(let msg): return "Failed to render: \(msg)"
        case .stextFailed(let msg): return "Failed to extract structured text: \(msg)"
        case .saveFailed(let msg): return "Failed to save document: \(msg)"
        case .operationFailed(let msg): return "Operation failed: \(msg)"
        case .outOfBounds(let p): return "Page index \(p) is out of bounds"
        case .passwordRequired: return "This document requires a password."
        case .incorrectPassword: return "Incorrect password."
        }
    }
}

/// Represents a loaded document, providing thread-safe metadata, layout geometry, and outline access.
/// Note: Concurrency safety with background actors (PDFRenderActor, PDFSearchActor) is maintained
/// by isolating each actor to its own cloned context and document instance. PDFDocumentCore guards
/// its internal MuPDF pointers with `lock` for any concurrent access.
public final class PDFDocumentCore: @unchecked Sendable {
    public private(set) var filePath: String
    private let ctx: FZContext
    private let doc: FZDocument
    public private(set) var pageCount: Int
    // Mutable to allow updating placeholder bounds once exact geometry is known. MainActor only.
    public private(set) var pageBounds: [CGRect]
    public private(set) var pageYOffsets: [CGFloat]
    public private(set) var totalHeight: CGFloat
    public internal(set) var outline: [PDFOutlineNode]

    /// Whether pageBounds[i] reflects exact inspected dimensions rather than a placeholder.
    private var hasExactBounds: [Bool]
    private static let pageSpacing: CGFloat = 16.0

    private let lock = NSLock()
    private let openedPassword: String?
    
    public init(filePath: String, password: String? = nil) throws {
        self.filePath = filePath
        self.openedPassword = password
        let ctx = PDFContextManager.shared.makeClonedContext()
        self.ctx = ctx

        var docPtr: FZDocument?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_document_open(ctx, filePath, &docPtr, &errorMsg)
        guard ret == 0, let doc = docPtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Unknown error"
            PDFContextManager.shared.dropContext(ctx)
            throw PDFError.openFailed(msg)
        }

        // Must happen before any other document access (page count, rendering, etc.) — those can
        // fail or return incorrect results on an unauthenticated encrypted document.
        var needsPassword: Int32 = 0
        mupdf_document_needs_password(ctx, doc, &needsPassword, &errorMsg)
        if needsPassword != 0 {
            guard let password else {
                mupdf_document_drop(ctx, doc)
                PDFContextManager.shared.dropContext(ctx)
                throw PDFError.passwordRequired
            }
            var authenticated: Int32 = 0
            mupdf_document_authenticate_password(ctx, doc, password, &authenticated, &errorMsg)
            guard authenticated != 0 else {
                mupdf_document_drop(ctx, doc)
                PDFContextManager.shared.dropContext(ctx)
                throw PDFError.incorrectPassword
            }
        }

        self.doc = doc
        self.pageCount = 0
        self.pageBounds = []
        self.pageYOffsets = []
        self.totalHeight = 0
        self.hasExactBounds = []
        self.outline = []

        rebuildPageLayoutAndOutline()
    }

    /// Recomputes page count, layout coordinates, page bounds, and outline after document modifications.
    private func rebuildPageLayoutAndOutline() {
        var count: Int32 = 0
        mupdf_document_count_pages(ctx, doc, &count, nil)
        let totalPages = Int(count)
        self.pageCount = totalPages

        var bounds: [CGRect] = []
        var yOffsets: [CGFloat] = []
        var hasExact: [Bool] = []
        var currentY: CGFloat = 0.0
        let pageSpacing = Self.pageSpacing

        var baselineRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        if totalPages > 0 {
            autoreleasepool {
                var page0Ptr: FZPage?
                if mupdf_page_load(ctx, doc, 0, &page0Ptr, nil) == 0, let page0 = page0Ptr {
                    var rect = fz_rect()
                    mupdf_page_bounds(ctx, page0, &rect, nil)
                    let w = CGFloat(rect.x1 - rect.x0)
                    let h = CGFloat(rect.y1 - rect.y0)
                    baselineRect = CGRect(x: CGFloat(rect.x0), y: CGFloat(rect.y0), width: max(w, 100), height: max(h, 100))
                    mupdf_page_drop(ctx, page0)
                }
            }
        }

        if totalPages <= 60 {
            bounds.reserveCapacity(totalPages)
            yOffsets.reserveCapacity(totalPages)
            hasExact.reserveCapacity(totalPages)
            for i in 0..<totalPages {
                autoreleasepool {
                    var pagePtr: FZPage?
                    if mupdf_page_load(ctx, doc, Int32(i), &pagePtr, nil) == 0, let page = pagePtr {
                        var rect = fz_rect()
                        mupdf_page_bounds(ctx, page, &rect, nil)
                        let w = CGFloat(rect.x1 - rect.x0)
                        let h = CGFloat(rect.y1 - rect.y0)
                        let pageRect = CGRect(x: CGFloat(rect.x0), y: CGFloat(rect.y0), width: max(w, 100), height: max(h, 100))
                        bounds.append(pageRect)
                        yOffsets.append(currentY)
                        hasExact.append(true)
                        currentY += pageRect.height + pageSpacing
                        mupdf_page_drop(ctx, page)
                    } else {
                        bounds.append(baselineRect)
                        yOffsets.append(currentY)
                        hasExact.append(true)
                        currentY += baselineRect.height + pageSpacing
                    }
                }
            }
        } else {
            bounds.reserveCapacity(totalPages)
            yOffsets.reserveCapacity(totalPages)
            hasExact.reserveCapacity(totalPages)
            let pageHeightWithSpacing = baselineRect.height + pageSpacing
            for i in 0..<totalPages {
                bounds.append(baselineRect)
                yOffsets.append(currentY)
                hasExact.append(i == 0)
                currentY += pageHeightWithSpacing
            }
        }
        mupdf_context_empty_store(ctx)
        self.pageBounds = bounds
        self.pageYOffsets = yOffsets
        self.totalHeight = currentY
        self.hasExactBounds = hasExact

        var outlinePtr: FZOutline?
        if mupdf_document_load_outline(ctx, doc, &outlinePtr, nil) == 0, let out = outlinePtr {
            self.outline = PDFDocumentCore.parseOutline(out)
            mupdf_outline_drop(ctx, out)
        } else {
            self.outline = []
        }
    }
    
    deinit {
        mupdf_document_drop(ctx, doc)
        PDFContextManager.shared.dropContext(ctx)
    }
    
    /// Recursively converts MuPDF outline tree to Swift PDFOutlineNode array
    private static func parseOutline(_ outline: FZOutline) -> [PDFOutlineNode] {
        var nodes: [PDFOutlineNode] = []
        var curr: FZOutline? = outline
        
        while let item = curr {
            let titleStr: String
            if let cTitle = mupdf_outline_title(item) {
                titleStr = String(cString: cTitle)
            } else {
                titleStr = "Untitled"
            }
            
            let uriStr: String?
            if let cUri = mupdf_outline_uri(item) {
                uriStr = String(cString: cUri)
            } else {
                uriStr = nil
            }
            
            let p = Int(mupdf_outline_page(item))
            let pageIndex = p >= 0 ? p : nil
            
            let children: [PDFOutlineNode]
            if let down = mupdf_outline_down(item) {
                children = parseOutline(down)
            } else {
                children = []
            }
            
            nodes.append(PDFOutlineNode(title: titleStr, uri: uriStr, targetPage: pageIndex, children: children))
            curr = mupdf_outline_next(item)
        }
        
        return nodes
    }
    
    /// Finds which page index is located at a vertical scroll offset
    public func pageIndex(atYOffset y: CGFloat) -> Int {
        guard !pageYOffsets.isEmpty else { return 0 }
        var low = 0
        var high = pageYOffsets.count - 1
        var result = 0
        
        while low <= high {
            let mid = (low + high) / 2
            if pageYOffsets[mid] <= y {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return min(max(result, 0), pageCount - 1)
    }

    /// Updates a page's exact bounds and adjusts subsequent vertical page offsets.
    @discardableResult
    public func recordActualPageBounds(_ actualBounds: CGRect, forPage pageIndex: Int) -> Bool {
        guard pageBounds.indices.contains(pageIndex), hasExactBounds.indices.contains(pageIndex) else { return false }
        guard !hasExactBounds[pageIndex] else { return false }
        hasExactBounds[pageIndex] = true
        guard actualBounds.width > 0, actualBounds.height > 0 else { return false }
        // Same floor init applies to every page's bounds, so a pathologically tiny real page can't
        // produce a near-zero-size frame that breaks scale math elsewhere (thumbnail cropping,
        // widget positioning, etc.).
        let clampedBounds = CGRect(x: actualBounds.minX, y: actualBounds.minY, width: max(actualBounds.width, 100), height: max(actualBounds.height, 100))
        guard clampedBounds != pageBounds[pageIndex] else { return false }

        pageBounds[pageIndex] = clampedBounds
        var currentY = pageYOffsets[pageIndex]
        for i in pageIndex..<pageBounds.count {
            pageYOffsets[i] = currentY
            currentY += pageBounds[i].height + Self.pageSpacing
        }
        totalHeight = currentY
        return true
    }

    /// Thread-safe scoped page inspection using this core's context
    public func withPage<T>(pageIndex: Int, _ body: (FZPage) throws -> T) throws -> T {
        guard pageIndex >= 0 && pageIndex < pageCount else {
            throw PDFError.outOfBounds(pageIndex)
        }
        lock.lock()
        defer { lock.unlock() }
        
        var pagePtr: FZPage?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_page_load(ctx, doc, Int32(pageIndex), &pagePtr, &errorMsg)
        guard ret == 0, let page = pagePtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to load page"
            throw PDFError.pageLoadFailed(pageIndex, msg)
        }
        defer {
            mupdf_page_drop(ctx, page)
        }
        return try body(page)
    }

    /// Renders a specific rectangular sub-region of a page (in PDF points) into PNG data at the specified scale.
    public func renderPageRect(pageIndex: Int, rect: CGRect, scale: CGFloat = 2.0) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        var pagePtr: FZPage?
        guard mupdf_page_load(ctx, doc, Int32(pageIndex), &pagePtr, nil) == 0, let page = pagePtr else {
            return nil
        }
        defer { mupdf_page_drop(ctx, page) }

        let scaleF = Float(scale)
        var pixmapPtr: FZPixmap?
        let ret = mupdf_render_page_rect(
            ctx, page, scaleF, scaleF,
            Float(rect.minX), Float(rect.minY), Float(rect.maxX), Float(rect.maxY),
            &pixmapPtr, nil
        )
        guard ret == 0, let pix = pixmapPtr else { return nil }
        defer { mupdf_pixmap_drop(ctx, pix) }

        let width = Int(mupdf_pixmap_width(pix))
        let height = Int(mupdf_pixmap_height(pix))
        guard width > 0, height > 0 else { return nil }

        let stride = Int(mupdf_pixmap_stride(pix))
        let n = Int(mupdf_pixmap_n(pix))
        guard let samples = mupdf_pixmap_samples(pix) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = (n == 4) ? CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue) : CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)

        guard let provider = CGDataProvider(data: Data(bytes: samples, count: stride * height) as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: n * 8,
                  bytesPerRow: stride,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo,
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else { return nil }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
    
    /// Adds a text markup annotation (highlight, underline, or strikethrough) to a page across one or more text line quads
    public func addTextMarkup(pageIndex: Int, type: PDFAnnotationType, quads: [PDFQuad], red: Float, green: Float, blue: Float) throws {
        guard !quads.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let markupType: Int32
        switch type {
        case .highlight: markupType = 0
        case .underline: markupType = 1
        case .strikeout: markupType = 2
        case .ink, .freeText, .callout, .stamp, .measureLength, .measurePerimeter, .measureArea, .measureAngle: return
        }

        let fzQuads = quads.map { $0.toFZQuad() }
        var errorMsg: UnsafePointer<CChar>?
        let ret = fzQuads.withUnsafeBufferPointer { buf in
            mupdf_pdf_add_text_markup(ctx, doc, Int32(pageIndex), markupType, buf.baseAddress, Int32(buf.count), red, green, blue, &errorMsg)
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to add text markup"
            throw PDFError.saveFailed(msg)
        }
    }

    /// Adds a highlight annotation to a page across one or more text line quads
    public func addHighlight(pageIndex: Int, quads: [PDFQuad], red: Float, green: Float, blue: Float) throws {
        try addTextMarkup(pageIndex: pageIndex, type: .highlight, quads: quads, red: red, green: green, blue: blue)
    }
    
    /// Single-quad highlight overload
    public func addHighlight(pageIndex: Int, quad: PDFQuad, red: Float, green: Float, blue: Float) throws {
        try addHighlight(pageIndex: pageIndex, quads: [quad], red: red, green: green, blue: blue)
    }

    /// Adds a freehand ink stroke annotation to a page
    public func addInkStroke(pageIndex: Int, points: [CGPoint], strokeWidth: CGFloat, red: Float, green: Float, blue: Float) throws {
        guard !points.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let fzPoints = points.map { fz_point(x: Float($0.x), y: Float($0.y)) }
        var errorMsg: UnsafePointer<CChar>?
        let ret = fzPoints.withUnsafeBufferPointer { buf in
            mupdf_pdf_add_ink_stroke(ctx, doc, Int32(pageIndex), buf.baseAddress, Int32(buf.count), Float(strokeWidth), red, green, blue, &errorMsg)
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to add ink stroke"
            throw PDFError.saveFailed(msg)
        }
    }

    /// Adds a FreeText (text box) annotation to a page
    public func addFreeText(pageIndex: Int, rect: CGRect, text: String, fontSize: CGFloat, red: Float, green: Float, blue: Float) throws {
        guard !text.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var errorMsg: UnsafePointer<CChar>?
        let ret = text.withCString { cText in
            mupdf_pdf_add_free_text_annot(
                ctx,
                doc,
                Int32(pageIndex),
                Float(rect.origin.x),
                Float(rect.origin.y),
                Float(rect.origin.x + rect.width),
                Float(rect.origin.y + rect.height),
                cText,
                Float(fontSize),
                red,
                green,
                blue,
                &errorMsg
            )
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to add free text annotation"
            throw PDFError.saveFailed(msg)
        }
    }

    /// Adds a technical leader-line callout annotation (/IT /FreeTextCallout) with an arrow pointer, knee elbow, and text note box.
    public func addCallout(
        pageIndex: Int,
        targetPoint: CGPoint,
        kneePoint: CGPoint,
        textBoxRect: CGRect,
        text: String,
        fontSize: CGFloat = 11.0,
        red: Float,
        green: Float,
        blue: Float
    ) throws {
        guard !text.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var errorMsg: UnsafePointer<CChar>?
        let ret = text.withCString { cText in
            mupdf_pdf_add_callout_annot(
                ctx,
                doc,
                Int32(pageIndex),
                Float(targetPoint.x),
                Float(targetPoint.y),
                Float(kneePoint.x),
                Float(kneePoint.y),
                Float(textBoxRect.minX),
                Float(textBoxRect.minY),
                Float(textBoxRect.maxX),
                Float(textBoxRect.maxY),
                cText,
                Float(fontSize),
                red,
                green,
                blue,
                &errorMsg
            )
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to add callout annotation"
            throw PDFError.saveFailed(msg)
        }
    }

    /// Permanently redacts (scrubs and deletes) all text glyphs, vector line art, and bitmap pixels
    /// Permanently redacts all content covered by the given rectangles on `pageIndex`.
    /// - Parameters:
    ///   - mode: 1 = Blackout Region (burns black boxes, scrubs line art and images),
    ///           2 = Whiteout Region (burns white boxes, scrubs line art and images),
    ///           0 = Text Only (excises text, leaves surrounding line art and images intact).
    public func applyRedactions(pageIndex: Int, rects: [CGRect], mode: Int32 = 1) throws {
        guard !rects.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let fzRects = rects.map { r in
            fz_rect(
                x0: Float(r.minX),
                y0: Float(r.minY),
                x1: Float(r.maxX),
                y1: Float(r.maxY)
            )
        }

        var errorMsg: UnsafePointer<CChar>?
        let ret = fzRects.withUnsafeBufferPointer { buf in
            mupdf_page_apply_redaction_rects(
                ctx,
                doc,
                Int32(pageIndex),
                buf.baseAddress,
                Int32(buf.count),
                mode,
                &errorMsg
            )
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to apply redactions"
            throw PDFError.saveFailed(msg)
        }
    }

    public func applyRedactions(pageIndex: Int, rects: [CGRect], blackBoxes: Bool) throws {
        try applyRedactions(pageIndex: pageIndex, rects: rects, mode: blackBoxes ? 1 : 2)
    }

    // MARK: - Engineering Measurement & Takeoff Annotations

    public func addLineDimension(
        pageIndex: Int,
        startPoint: CGPoint,
        endPoint: CGPoint,
        leaderOffset: CGFloat = 0.0,
        text: String,
        red: Float,
        green: Float,
        blue: Float
    ) throws {
        guard !text.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var errorMsg: UnsafePointer<CChar>?
        let ret = text.withCString { cText in
            mupdf_pdf_add_line_dimension_annot(
                ctx,
                doc,
                Int32(pageIndex),
                Float(startPoint.x),
                Float(startPoint.y),
                Float(endPoint.x),
                Float(endPoint.y),
                Float(leaderOffset),
                cText,
                red,
                green,
                blue,
                &errorMsg
            )
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to add line dimension annotation"
            throw PDFError.saveFailed(msg)
        }
    }

    public func addPolylineDimension(
        pageIndex: Int,
        vertices: [CGPoint],
        text: String,
        red: Float,
        green: Float,
        blue: Float
    ) throws {
        guard !text.isEmpty, vertices.count >= 2 else { return }
        lock.lock()
        defer { lock.unlock() }

        let fzPts = vertices.map { fz_point(x: Float($0.x), y: Float($0.y)) }
        var errorMsg: UnsafePointer<CChar>?
        let ret = fzPts.withUnsafeBufferPointer { buf in
            text.withCString { cText in
                mupdf_pdf_add_polyline_dimension_annot(
                    ctx,
                    doc,
                    Int32(pageIndex),
                    buf.baseAddress,
                    Int32(buf.count),
                    cText,
                    red,
                    green,
                    blue,
                    &errorMsg
                )
            }
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to add polyline dimension annotation"
            throw PDFError.saveFailed(msg)
        }
    }

    public func addPolygonDimension(
        pageIndex: Int,
        vertices: [CGPoint],
        text: String,
        red: Float,
        green: Float,
        blue: Float,
        fillAlpha: Float = 0.22
    ) throws {
        guard !text.isEmpty, vertices.count >= 3 else { return }
        lock.lock()
        defer { lock.unlock() }

        let fzPts = vertices.map { fz_point(x: Float($0.x), y: Float($0.y)) }
        var errorMsg: UnsafePointer<CChar>?
        let ret = fzPts.withUnsafeBufferPointer { buf in
            text.withCString { cText in
                mupdf_pdf_add_polygon_dimension_annot(
                    ctx,
                    doc,
                    Int32(pageIndex),
                    buf.baseAddress,
                    Int32(buf.count),
                    cText,
                    red,
                    green,
                    blue,
                    fillAlpha,
                    &errorMsg
                )
            }
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to add polygon dimension annotation"
            throw PDFError.saveFailed(msg)
        }
    }

    /// Writes an angle measurement (rays `points[0]` and `points[2]` meeting at apex `points[1]`)
    /// as a PolyLine annotation labelled with `text`.
    public func addAngleMeasurement(
        pageIndex: Int,
        points: [CGPoint],
        text: String,
        red: Float,
        green: Float,
        blue: Float
    ) throws {
        guard !text.isEmpty, points.count == 3 else { return }
        lock.lock()
        defer { lock.unlock() }

        let fzPts = points.map { fz_point(x: Float($0.x), y: Float($0.y)) }
        var errorMsg: UnsafePointer<CChar>?
        let ret = fzPts.withUnsafeBufferPointer { buf in
            text.withCString { cText in
                mupdf_pdf_add_angle_annot(
                    ctx,
                    doc,
                    Int32(pageIndex),
                    buf.baseAddress,
                    Int32(buf.count),
                    cText,
                    red,
                    green,
                    blue,
                    &errorMsg
                )
            }
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to add angle annotation"
            throw PDFError.saveFailed(msg)
        }
    }

    /// The drawing scale stored on pageIndex, if any.
    public func loadPageScale(pageIndex: Int) -> PDFScaleConfiguration? {
        guard pageIndex >= 0, pageIndex < pageCount else { return nil }
        lock.lock()
        defer { lock.unlock() }

        var ratio = [CChar](repeating: 0, count: 128)
        var unit = [CChar](repeating: 0, count: 32)
        var ptsPerUnit: Float = 0
        var found: Int32 = 0
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_pdf_get_page_scale(ctx, doc, Int32(pageIndex), &ratio, ratio.count, &unit, unit.count, &ptsPerUnit, &found, &errorMsg)
        guard ret == 0, found != 0, ptsPerUnit > 0 else { return nil }
        return PDFScaleConfiguration.restored(
            ratioString: String(cString: ratio),
            unitSymbol: String(cString: unit),
            pointsPerUnit: Double(ptsPerUnit)
        )
    }

    public func setPageScale(
        pageIndex: Int,
        ratioString: String,
        unitString: String,
        pointsPerUnit: Double
    ) throws {
        guard !ratioString.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var errorMsg: UnsafePointer<CChar>?
        let ret = ratioString.withCString { cRatio in
            unitString.withCString { cUnit in
                mupdf_pdf_set_page_scale(
                    ctx,
                    doc,
                    Int32(pageIndex),
                    cRatio,
                    cUnit,
                    Float(pointsPerUnit),
                    &errorMsg
                )
            }
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to set page scale"
            throw PDFError.saveFailed(msg)
        }
    }

    /// Extracts plain text from the specified page.
    public func extractText(pageIndex: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }

        var pagePtr: FZPage?
        guard mupdf_page_load(ctx, doc, Int32(pageIndex), &pagePtr, nil) == 0, let page = pagePtr else {
            return nil
        }
        defer { mupdf_page_drop(ctx, page) }

        var stextPtr: FZStextPage?
        guard mupdf_stext_page_load(ctx, page, &stextPtr, nil) == 0, let stext = stextPtr else {
            return nil
        }
        defer { mupdf_stext_page_drop(ctx, stext) }

        guard let cText = mupdf_stext_page_text(ctx, stext) else { return nil }
        let text = String(cString: cText)
        mupdf_free(ctx, cText)
        return text
    }

    /// Checks whether `pageIndex` is a scanned page (i.e. containing 0 extractable structured text characters).
    public func isScannedPage(pageIndex: Int) -> Bool {
        guard let text = extractText(pageIndex: pageIndex) else { return true }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Deletes any user annotation (highlight, underline, strikethrough, ink, free text, or callout)
    /// located near a point on a page. Returns true if an annotation was found and removed.
    @discardableResult
    public func deleteAnnotation(pageIndex: Int, at pagePoint: CGPoint) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_pdf_delete_annot_near_point(ctx, doc, Int32(pageIndex), Float(pagePoint.x), Float(pagePoint.y), &errorMsg)
        if ret < 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to delete annotation"
            throw PDFError.saveFailed(msg)
        }
        return ret == 1
    }

    /// Measurement annotations stored on pageIndex, recomputed from stored geometry.
    public func measurementAnnotations(pageIndex: Int) -> [PDFAnnotation] {
        lock.lock()
        defer { lock.unlock() }
        var total: Int32 = 0
        guard mupdf_pdf_get_measurement_annots(ctx, doc, Int32(pageIndex), nil, 0, &total, nil) == 0, total > 0 else {
            return []
        }
        var buffer = [mupdf_measurement_annot](repeating: mupdf_measurement_annot(), count: Int(total))
        var filled: Int32 = 0
        let ret = buffer.withUnsafeMutableBufferPointer {
            mupdf_pdf_get_measurement_annots(ctx, doc, Int32(pageIndex), $0.baseAddress, total, &filled, nil)
        }
        guard ret == 0 else { return [] }
        return buffer.prefix(Int(min(filled, total))).compactMap { m -> PDFAnnotation? in
            var raw = m
            let n = Int(raw.n_points)
            let points: [CGPoint] = withUnsafeBytes(of: &raw.xy) { bytes in
                let xy = bytes.bindMemory(to: Float.self)
                return (0..<n).map { CGPoint(x: CGFloat(xy[2 * $0]), y: CGFloat(xy[2 * $0 + 1])) }
            }
            let text: String = withUnsafeBytes(of: &raw.text) { bytes in
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let type: PDFAnnotationType
            let value: Double
            switch raw.kind {
            case 1:
                guard points.count >= 2 else { return nil }
                type = .measureLength
                value = Double(hypot(points[1].x - points[0].x, points[1].y - points[0].y))
            case 2:
                guard points.count >= 2 else { return nil }
                type = .measurePerimeter
                value = zip(points, points.dropFirst()).reduce(0.0) { $0 + Double(hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)) }
            case 3:
                guard points.count >= 3 else { return nil }
                type = .measureArea
                value = PDFMeasurementGeometry.shoelaceArea(points: points)
            case 4:
                guard points.count >= 3 else { return nil }
                type = .measureAngle
                value = PDFMeasurementGeometry.angleDegrees(r1: points[0], apex: points[1], r2: points[2])
            default:
                return nil
            }
            var annot = PDFAnnotation(
                pageIndex: pageIndex,
                type: type,
                color: AnnotationColor.nearest(red: raw.r, green: raw.g, blue: raw.b),
                text: text,
                measurementPoints: points,
                measurementValue: value,
                measurementText: text
            )
            annot.documentObjectNumber = Int(raw.objnum)
            return annot
        }
    }

    /// Object number of the most recently added annotation on a page (see
    /// mupdf_pdf_last_annot_objnum), or nil if the page has none.
    public func lastAnnotationObjectNumber(pageIndex: Int) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        var objnum: Int32 = 0
        guard mupdf_pdf_last_annot_objnum(ctx, doc, Int32(pageIndex), &objnum, nil) == 0, objnum > 0 else { return nil }
        return Int(objnum)
    }

    /// Deletes the annotation stored as PDF object `objectNumber` on a page. Returns false if no
    /// annotation on that page has that object number.
    @discardableResult
    public func deleteAnnotation(pageIndex: Int, objectNumber: Int) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_pdf_delete_annot_by_objnum(ctx, doc, Int32(pageIndex), Int32(objectNumber), &errorMsg)
        if ret < 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to delete annotation"
            throw PDFError.saveFailed(msg)
        }
        return ret == 1
    }

    /// Deletes a highlight annotation located near a point on a page
    @discardableResult
    public func deleteHighlight(pageIndex: Int, at pagePoint: CGPoint) throws -> Bool {
        return try deleteAnnotation(pageIndex: pageIndex, at: pagePoint)
    }
    
    /// Stamps `imageData` (PNG or JPEG bytes) into `rect` (native bottom-up PDF coordinates) on a
    /// page as a visual signature stamp — not a filled-in AcroForm field value, not a cryptographic
    /// signature.
    public func stampImage(pageIndex: Int, rect: CGRect, imageData: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        var errorMsg: UnsafePointer<CChar>?
        let ret = imageData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int32 in
            let bytes = raw.bindMemory(to: UInt8.self).baseAddress
            return mupdf_pdf_stamp_image_annot(
                ctx, doc, Int32(pageIndex),
                Float(rect.minX), Float(rect.minY), Float(rect.maxX), Float(rect.maxY),
                bytes, raw.count, &errorMsg
            )
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to stamp signature image"
            throw PDFError.saveFailed(msg)
        }
    }

    /// Whether a signature stamp annotation exists at widgetRect on pageIndex.
    public func hasSignatureStamp(pageIndex: Int, widgetRect: CGRect) -> Bool {
        guard pageIndex >= 0, pageIndex < pageBounds.count else { return false }
        let pageTopY = pageBounds[pageIndex].maxY
        let nativeRect = CGRect(x: widgetRect.minX, y: pageTopY - widgetRect.maxY, width: widgetRect.width, height: widgetRect.height)

        lock.lock()
        defer { lock.unlock() }

        var found: Int32 = 0
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_pdf_page_has_stamp_near_rect(
            ctx, doc, Int32(pageIndex),
            Float(nativeRect.minX), Float(nativeRect.minY), Float(nativeRect.maxX), Float(nativeRect.maxY),
            &found, &errorMsg
        )
        return ret == 0 && found != 0
    }

    /// Updates the internal file path if the document was moved or renamed externally.
    public func updateFilePath(_ newPath: String) {
        lock.lock()
        defer { lock.unlock() }
        self.filePath = newPath
    }

    /// Safely writes document data to a target URL, using a temporary file in `temporaryDirectory`
    /// and coordinating with `NSFileCoordinator` to prevent sync daemon race conditions in iCloud Drive
    /// or other cloud providers.
    private func performCoordinatedSave(to destinationURL: URL, isSameFile: Bool, writeAction: (String) throws -> Void) throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_save_\(UUID().uuidString)_\(destinationURL.lastPathComponent)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Execute save to local temporary directory outside iCloud/CloudStorage
        try writeAction(tempURL.path)

        let targetExists = FileManager.default.fileExists(atPath: destinationURL.path)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var replaceError: Error?

        let writingOptions: NSFileCoordinator.WritingOptions = targetExists ? .forReplacing : []
        coordinator.coordinate(writingItemAt: destinationURL, options: writingOptions, error: &coordError) { writingURL in
            do {
                if targetExists || isSameFile {
                    _ = try FileManager.default.replaceItemAt(writingURL, withItemAt: tempURL)
                } else {
                    try FileManager.default.moveItem(at: tempURL, to: writingURL)
                }
            } catch {
                replaceError = error
            }
        }

        if let replaceError {
            throw replaceError
        }
        if let coordError {
            throw coordError
        }
    }

    /// Saves the modified PDF, using atomic file swapping and NSFileCoordinator to ensure safe cloud sync.
    public func save(to path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let destinationURL = URL(fileURLWithPath: path)
        let isSameFile = (path == self.filePath)
        
        try performCoordinatedSave(to: destinationURL, isSameFile: isSameFile) { targetTempPath in
            var errorMsg: UnsafePointer<CChar>?
            let ret = mupdf_pdf_save(ctx, doc, targetTempPath, &errorMsg)
            if ret != 0 {
                let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to save PDF"
                throw PDFError.saveFailed(msg)
            }
        }
    }

    /// Saves the modified PDF encrypted with a password using AES-256 encryption.
    public func saveEncrypted(to path: String, password: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let destinationURL = URL(fileURLWithPath: path)
        let isSameFile = (path == self.filePath)
        
        try performCoordinatedSave(to: destinationURL, isSameFile: isSameFile) { targetTempPath in
            var errorMsg: UnsafePointer<CChar>?
            let ret = mupdf_pdf_save_encrypted(ctx, doc, targetTempPath, password, &errorMsg)
            if ret != 0 {
                let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to save encrypted PDF"
                throw PDFError.saveFailed(msg)
            }
        }
    }

    /// Saves the modified PDF with annotations and/or form fields permanently flattened (baked) into static page graphics.
    ///
    /// Preserves the interactive state of this in-memory document instance by executing the flattening
    /// operation on an isolated temporary document clone.
    public func saveFlattened(to path: String, bakeAnnotations: Bool = true, bakeWidgets: Bool = true) throws {
        lock.lock()
        defer { lock.unlock() }

        let destinationURL = URL(fileURLWithPath: path)
        let isSameFile = (path == self.filePath)

        // 1. Flush current in-memory modifications to a temporary working file
        let tempSourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_pre_flatten_\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: tempSourceURL) }

        var errorMsg: UnsafePointer<CChar>?
        let saveRet = mupdf_pdf_save(ctx, doc, tempSourceURL.path, &errorMsg)
        if saveRet != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to prepare temporary document for flattening"
            throw PDFError.saveFailed(msg)
        }

        // 2. Open the temporary file in an isolated document instance
        let tempDoc = try PDFDocumentCore(filePath: tempSourceURL.path, password: self.openedPassword)

        // 3. Bake and save to target path using coordinated save
        try performCoordinatedSave(to: destinationURL, isSameFile: isSameFile) { targetTempPath in
            var bakeErrorMsg: UnsafePointer<CChar>?
            let bakeRet = mupdf_pdf_save_flattened(
                tempDoc.ctx, tempDoc.doc, targetTempPath,
                bakeAnnotations ? 1 : 0,
                bakeWidgets ? 1 : 0,
                &bakeErrorMsg
            )
            if bakeRet != 0 {
                let msg = bakeErrorMsg != nil ? String(cString: bakeErrorMsg!) : "Failed to save flattened PDF"
                throw PDFError.saveFailed(msg)
            }
        }
    }

    // MARK: - Page Manipulation
    public func rotatePage(_ pageIndex: Int, by degrees: Int = 90) throws {
        lock.lock()
        defer { lock.unlock() }
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_pdf_rotate_page(ctx, doc, Int32(pageIndex), Int32(degrees), &errorMsg)
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to rotate page"
            throw PDFError.operationFailed(msg)
        }
        rebuildPageLayoutAndOutline()
    }

    public func deletePage(_ pageIndex: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_pdf_delete_page(ctx, doc, Int32(pageIndex), &errorMsg)
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to delete page"
            throw PDFError.operationFailed(msg)
        }
        rebuildPageLayoutAndOutline()
    }

    public func reorderPage(from fromIndex: Int, to toIndex: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_pdf_reorder_page(ctx, doc, Int32(fromIndex), Int32(toIndex), &errorMsg)
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to reorder page"
            throw PDFError.operationFailed(msg)
        }
        rebuildPageLayoutAndOutline()
    }

    public func reorderPages(from fromIndices: [Int], toSlot destSlot: Int) throws {
        guard !fromIndices.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var errorMsg: UnsafePointer<CChar>?
        let int32Indices = fromIndices.map { Int32($0) }
        let ret = int32Indices.withUnsafeBufferPointer { buf in
            mupdf_pdf_reorder_pages(ctx, doc, buf.baseAddress, Int32(buf.count), Int32(destSlot), &errorMsg)
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to reorder pages"
            throw PDFError.operationFailed(msg)
        }
        rebuildPageLayoutAndOutline()
    }

    public func deletePages(_ pageIndices: [Int]) throws {
        guard !pageIndices.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var errorMsg: UnsafePointer<CChar>?
        let int32Indices = pageIndices.map { Int32($0) }
        let ret = int32Indices.withUnsafeBufferPointer { buf in
            mupdf_pdf_delete_pages(ctx, doc, buf.baseAddress, Int32(buf.count), &errorMsg)
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to delete pages"
            throw PDFError.operationFailed(msg)
        }
        rebuildPageLayoutAndOutline()
    }

    public func rotatePages(_ pageIndices: [Int], by degrees: Int = 90) throws {
        guard !pageIndices.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        for pageIndex in pageIndices {
            var errorMsg: UnsafePointer<CChar>?
            let ret = mupdf_pdf_rotate_page(ctx, doc, Int32(pageIndex), Int32(degrees), &errorMsg)
            if ret != 0 {
                let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to rotate page \(pageIndex)"
                throw PDFError.operationFailed(msg)
            }
        }
        rebuildPageLayoutAndOutline()
    }

    public func extractPages(_ pageIndices: [Int], to destinationURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        var errorMsg: UnsafePointer<CChar>?
        let int32Indices = pageIndices.map { Int32($0) }
        let ret = int32Indices.withUnsafeBufferPointer { buf in
            mupdf_pdf_extract_pages(ctx, doc, buf.baseAddress, Int32(buf.count), destinationURL.path, &errorMsg)
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to extract pages"
            throw PDFError.operationFailed(msg)
        }
    }

    /// Exports the specified page as an SVG XML string via MuPDF's native SVG device.
    /// - Parameters:
    ///   - pageIndex: 0-based index of the page to export.
    ///   - textAsPath: If true, text and math glyphs are converted to vector path outlines (guaranteeing exact visual appearance without font dependencies); if false, raw <text> elements are emitted.
    public func exportPageToSVG(pageIndex: Int, textAsPath: Bool = true) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard pageIndex >= 0, pageIndex < pageCount else {
            throw PDFError.outOfBounds(pageIndex)
        }
        var svgCStr: UnsafeMutablePointer<CChar>?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_page_to_svg(ctx, doc, Int32(pageIndex), textAsPath ? 1 : 0, &svgCStr, &errorMsg)
        guard ret == 0, let cStr = svgCStr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to export SVG"
            throw PDFError.operationFailed(msg)
        }
        defer { free(svgCStr) }
        return String(cString: cStr)
    }

    /// Exports the specified page directly to an SVG file at `destinationURL` via MuPDF's native SVG device.
    /// - Parameters:
    ///   - pageIndex: 0-based index of the page to export.
    ///   - destinationURL: File destination URL.
    ///   - textAsPath: If true, text and math glyphs are converted to vector path outlines (guaranteeing exact visual appearance without font dependencies); if false, raw <text> elements are emitted.
    public func exportPageToSVGFile(pageIndex: Int, destinationURL: URL, textAsPath: Bool = true) throws {
        lock.lock()
        defer { lock.unlock() }
        guard pageIndex >= 0, pageIndex < pageCount else {
            throw PDFError.outOfBounds(pageIndex)
        }
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_page_export_svg(ctx, doc, Int32(pageIndex), destinationURL.path, textAsPath ? 1 : 0, &errorMsg)
        guard ret == 0 else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to export SVG file"
            throw PDFError.operationFailed(msg)
        }
    }

    public func duplicatePages(_ pageIndices: [Int]) throws -> (insertedSlot: Int, count: Int) {
        guard !pageIndices.isEmpty else { return (0, 0) }
        lock.lock()
        defer { lock.unlock() }
        var insertedSlot: Int32 = 0
        var errorMsg: UnsafePointer<CChar>?
        let int32Indices = pageIndices.map { Int32($0) }
        let ret = int32Indices.withUnsafeBufferPointer { buf in
            mupdf_pdf_duplicate_pages(ctx, doc, buf.baseAddress, Int32(buf.count), &insertedSlot, &errorMsg)
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to duplicate pages"
            throw PDFError.operationFailed(msg)
        }
        rebuildPageLayoutAndOutline()
        return (Int(insertedSlot), pageIndices.count)
    }

    public func importPages(from fileURL: URL, atSlot slot: Int) throws -> (insertedSlot: Int, count: Int) {
        lock.lock()
        defer { lock.unlock() }
        var importedCount: Int32 = 0
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_pdf_import_pages(ctx, doc, fileURL.path, Int32(slot), &importedCount, &errorMsg)
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to import pages from \(fileURL.lastPathComponent)"
            throw PDFError.operationFailed(msg)
        }
        rebuildPageLayoutAndOutline()
        return (slot, Int(importedCount))
    }

    public func insertBlankPage(atSlot slot: Int, width: CGFloat? = nil, height: CGFloat? = nil) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        var errorMsg: UnsafePointer<CChar>?
        let w = Float(width ?? 0)
        let h = Float(height ?? 0)
        let ret = mupdf_pdf_insert_blank_page(ctx, doc, Int32(slot), w, h, &errorMsg)
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to insert blank page"
            throw PDFError.operationFailed(msg)
        }
        rebuildPageLayoutAndOutline()
        return slot
    }

    public func split(
        pageRanges: [[Int]],
        outputDirectory: URL,
        fileNames: [String],
        onProgress: (@Sendable (Double, String) -> Void)? = nil
    ) throws -> [URL] {
        var generatedURLs: [URL] = []
        let total = pageRanges.count
        for (i, pages) in pageRanges.enumerated() {
            guard !pages.isEmpty else { continue }
            let fileName = fileNames[i]
            let fileURL = outputDirectory.appendingPathComponent(fileName)
            onProgress?(Double(i) / Double(max(1, total)), "Writing \(fileName)...")
            try extractPages(pages, to: fileURL)
            generatedURLs.append(fileURL)
        }
        onProgress?(1.0, "Complete")
        return generatedURLs
    }
}

extension PDFDocumentCore {
    /// Loads interactive links for a page
    public func loadLinks(for pageIndex: Int) -> [SnapshotTarget] {
        let resolver = CrossReferenceResolver()
        return (try? withPage(pageIndex: pageIndex) { page in
            resolver.resolveLinks(on: page, pageIndex: pageIndex, doc: self.doc, ctx: self.ctx)
        }) ?? []
    }
    
    /// Loads structured text hierarchy for a page
    public func loadStructuredPage(for pageIndex: Int) -> StructuredPage? {
        return try? withPage(pageIndex: pageIndex) { page in
            try StructuredPage.load(from: page, pageIndex: pageIndex, ctx: self.ctx)
        }
    }
    
    /// Loads interactive form widgets (text fields, checkboxes, dropdowns) for a page
    public func loadFormWidgets(for pageIndex: Int) -> [PDFFormWidget] {
        lock.lock()
        defer { lock.unlock() }
        
        var count: Int32 = 0
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_page_count_widgets(ctx, doc, Int32(pageIndex), &count, &errorMsg)
        guard ret == 0, count > 0 else { return [] }
        
        var widgets: [PDFFormWidget] = []
        widgets.reserveCapacity(Int(count))
        
        for idx in 0..<count {
            var rawType: Int32 = 0
            var fzRect = fz_rect()
            var cName: UnsafeMutablePointer<CChar>? = nil
            var cValue: UnsafeMutablePointer<CChar>? = nil
            var flags: Int32 = 0
            var fontSize: Float = 0
            var maxLen: Int32 = 0
            var textAlign: Int32 = 0
            
            let infoRet = mupdf_page_get_widget_info(
                ctx, doc, Int32(pageIndex), idx,
                &rawType, &fzRect, &cName, &cValue, &flags, &fontSize,
                &maxLen, &textAlign, &errorMsg
            )
            
            guard infoRet == 0 else { continue }
            
            let name = cName != nil ? String(cString: cName!) : ""
            let value = cValue != nil ? String(cString: cValue!) : ""
            if let cName = cName { free(cName) }
            if let cValue = cValue { free(cValue) }
            
            let widgetType = PDFWidgetType(rawValue: Int(rawType)) ?? .unknown
            let rect = CGRect(
                x: CGFloat(fzRect.x0),
                y: CGFloat(fzRect.y0),
                width: CGFloat(fzRect.x1 - fzRect.x0),
                height: CGFloat(fzRect.y1 - fzRect.y0)
            )
            
            let isReadOnly = (flags & 1) != 0
            let isMultiline = (flags & (1 << 12)) != 0
            let isPassword = (flags & (1 << 13)) != 0
            let isPushButton = (flags & (1 << 16)) != 0
            let isEditableChoice = (flags & (1 << 18)) != 0
            let isComb = ((flags & (1 << 24)) != 0) && (maxLen > 0)
            var resetFlag: Int32 = 0
            if widgetType == .button && isPushButton {
                _ = mupdf_page_widget_is_reset_button(ctx, doc, Int32(pageIndex), idx, &resetFlag, nil)
            }
            let alignment: NSTextAlignment = textAlign == 1 ? .center : (textAlign == 2 ? .right : .left)
            
            var options: [String] = []
            if widgetType == .combobox || widgetType == .listbox {
                var cOptions: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? = nil
                var optCount: Int32 = 0
                if mupdf_page_get_choice_options(ctx, doc, Int32(pageIndex), idx, &cOptions, &optCount, nil) == 0, optCount > 0, let opts = cOptions {
                    for i in 0..<Int(optCount) {
                        if let optStr = opts[i] {
                            options.append(String(cString: optStr))
                        }
                    }
                    mupdf_free_choice_options(ctx, opts, optCount)
                }
            }
            
            let widget = PDFFormWidget(
                pageIndex: pageIndex,
                widgetIndex: Int(idx),
                type: widgetType,
                rect: rect,
                name: name,
                value: value,
                isReadOnly: isReadOnly,
                isMultiline: isMultiline,
                isPassword: isPassword,
                fontSize: CGFloat(fontSize),
                maxLen: Int(maxLen),
                isComb: isComb,
                isPushButton: isPushButton,
                isEditableChoice: isEditableChoice,
                isResetButton: resetFlag != 0,
                textAlignment: alignment,
                options: options
            )
            widgets.append(widget)
        }
        
        return widgets
    }
    
    /// Resets all interactive AcroForm fields in the document to their default values
    public func resetForm() throws {
        lock.lock()
        defer { lock.unlock() }
        var errorMsg: UnsafePointer<CChar>? = nil
        let ret = mupdf_document_reset_form(ctx, doc, &errorMsg)
        if ret != 0 {
            let desc = errorMsg != nil ? String(cString: errorMsg!) : "Failed to reset form"
            throw PDFError.renderFailed(desc)
        }
    }
    
    /// Updates the value of an AcroForm widget on a page
    public func setFormWidgetValue(pageIndex: Int, widgetIndex: Int, value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_page_set_widget_value(ctx, doc, Int32(pageIndex), Int32(widgetIndex), value, &errorMsg)
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to set form widget value"
            throw PDFError.saveFailed(msg)
        }
    }

    // MARK: - Document Metadata, Security & Font Inspection

    public func getMetadata() -> DocumentMetadata {
        lock.lock()
        defer { lock.unlock() }

        var rawMeta = mupdf_document_metadata()
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_document_get_metadata(ctx, doc, &rawMeta, &errorMsg)

        let format = ret == 0 ? withUnsafeBytes(of: rawMeta.format) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        } : ""
        let encryption = ret == 0 ? withUnsafeBytes(of: rawMeta.encryption) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        } : ""
        let title = ret == 0 ? withUnsafeBytes(of: rawMeta.title) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        } : ""
        let author = ret == 0 ? withUnsafeBytes(of: rawMeta.author) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        } : ""
        let subject = ret == 0 ? withUnsafeBytes(of: rawMeta.subject) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        } : ""
        let keywords = ret == 0 ? withUnsafeBytes(of: rawMeta.keywords) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        } : ""
        let creator = ret == 0 ? withUnsafeBytes(of: rawMeta.creator) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        } : ""
        let producer = ret == 0 ? withUnsafeBytes(of: rawMeta.producer) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        } : ""
        let creationDate = ret == 0 ? withUnsafeBytes(of: rawMeta.creation_date) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        } : ""
        let modDate = ret == 0 ? withUnsafeBytes(of: rawMeta.mod_date) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        } : ""

        let versionStr: String
        if rawMeta.pdf_version > 0 {
            versionStr = "PDF \(rawMeta.pdf_version / 10).\(rawMeta.pdf_version % 10)"
        } else {
            versionStr = format.isEmpty ? "PDF" : format
        }

        var fileSizeStr = "Unknown"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
           let size = attrs[.size] as? Int64 {
            fileSizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }

        return DocumentMetadata(
            format: format.isEmpty ? "PDF" : format,
            pdfVersion: versionStr,
            title: title,
            author: author,
            subject: subject,
            keywords: keywords,
            creator: creator,
            producer: producer,
            creationDate: creationDate,
            modificationDate: modDate,
            fileSizeDescription: fileSizeStr,
            pageCount: pageCount,
            isEncrypted: rawMeta.is_encrypted != 0,
            encryptionMethod: encryption.isEmpty ? (rawMeta.is_encrypted != 0 ? "Standard" : "None") : encryption
        )
    }

    public func getPermissions() -> DocumentSecurityPermissions {
        lock.lock()
        defer { lock.unlock() }

        var rawPerms = mupdf_document_permissions()
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_document_get_permissions(ctx, doc, &rawPerms, &errorMsg)
        guard ret == 0 else {
            return DocumentSecurityPermissions(
                canPrint: true,
                canModify: true,
                canCopy: true,
                canAnnotate: true,
                canFillForms: true,
                canAccessibility: true,
                canAssemble: true,
                canPrintHighQuality: true
            )
        }

        return DocumentSecurityPermissions(
            canPrint: rawPerms.can_print != 0,
            canModify: rawPerms.can_modify != 0,
            canCopy: rawPerms.can_copy != 0,
            canAnnotate: rawPerms.can_annotate != 0,
            canFillForms: rawPerms.can_fill_forms != 0,
            canAccessibility: rawPerms.can_accessibility != 0,
            canAssemble: rawPerms.can_assemble != 0,
            canPrintHighQuality: rawPerms.can_print_high_quality != 0
        )
    }

    public func getPageBoxes(for pageIndex: Int) -> PageBoxGeometry {
        lock.lock()
        defer { lock.unlock() }

        let clamped = max(0, min(pageIndex, max(0, pageCount - 1)))
        var rawBoxes = mupdf_page_boxes()
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_page_get_boxes(ctx, doc, Int32(clamped), &rawBoxes, &errorMsg)

        func toCGRect(_ r: fz_rect) -> CGRect {
            CGRect(x: Double(r.x0), y: Double(r.y0), width: Double(r.x1 - r.x0), height: Double(r.y1 - r.y0))
        }

        guard ret == 0 else {
            let fallback = pageBounds.indices.contains(clamped) ? pageBounds[clamped] : CGRect(x: 0, y: 0, width: 612, height: 792)
            return PageBoxGeometry(
                pageIndex: clamped,
                mediaBox: fallback,
                cropBox: fallback,
                bleedBox: fallback,
                trimBox: fallback,
                artBox: fallback,
                hasCropBox: true,
                hasBleedBox: false,
                hasTrimBox: false,
                hasArtBox: false
            )
        }

        return PageBoxGeometry(
            pageIndex: clamped,
            mediaBox: toCGRect(rawBoxes.media_box),
            cropBox: toCGRect(rawBoxes.crop_box),
            bleedBox: toCGRect(rawBoxes.bleed_box),
            trimBox: toCGRect(rawBoxes.trim_box),
            artBox: toCGRect(rawBoxes.art_box),
            hasCropBox: rawBoxes.has_crop_box != 0,
            hasBleedBox: rawBoxes.has_bleed_box != 0,
            hasTrimBox: rawBoxes.has_trim_box != 0,
            hasArtBox: rawBoxes.has_art_box != 0
        )
    }

    public func getEmbeddedFonts() -> [PDFEmbeddedFont] {
        lock.lock()
        defer { lock.unlock() }

        var fontList = mupdf_font_list()
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_document_get_fonts(ctx, doc, &fontList, &errorMsg)
        guard ret == 0, fontList.count > 0, let fontPtr = fontList.fonts else {
            return []
        }
        defer { mupdf_free_font_list(ctx, &fontList) }

        var result: [PDFEmbeddedFont] = []
        result.reserveCapacity(Int(fontList.count))

        for i in 0..<Int(fontList.count) {
            let entry = fontPtr[i]
            let name = withUnsafeBytes(of: entry.name) { ptr in
                String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            let subtype = withUnsafeBytes(of: entry.subtype) { ptr in
                String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            let encoding = withUnsafeBytes(of: entry.encoding) { ptr in
                String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            result.append(PDFEmbeddedFont(
                rawName: name,
                subtype: subtype,
                encoding: encoding,
                isEmbedded: entry.is_embedded != 0,
                isSubset: entry.is_subset != 0
            ))
        }

        return result
    }

    public func generateInspectionReport(pageIndex: Int) -> PDFDocumentInspectionReport {
        let meta = getMetadata()
        let perms = getPermissions()
        let boxes = (0..<pageCount).map { getPageBoxes(for: $0) }
        let fonts = getEmbeddedFonts()
        return PDFDocumentInspectionReport(
            metadata: meta,
            permissions: perms,
            pageBoxes: boxes,
            fonts: fonts
        )
    }
}
