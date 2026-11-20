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

import AppKit
import MuPDFBridge

/// What a page draws at a point, for the Inspector: the glyph, image and path there, each the
/// one on top. Rects are in page (top-down) coordinates.
public struct PageContentInspection: Equatable, Sendable {
    public struct Text: Equatable, Sendable {
        /// Without a subset's `ABCDEF+` prefix.
        public let fontName: String
        public let isSubset: Bool
        /// The font isn't in the file, and another is drawn in its place.
        public let isSubstitute: Bool
        public let fontSize: CGFloat
        public let character: String?
        public let isOutlined: Bool
        public let color: RGB
        public let colorSpace: String
        public let opacity: CGFloat
        public let rect: CGRect
    }

    public struct Image: Equatable, Sendable {
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let bitsPerComponent: Int
        public let isMask: Bool
        public let colorSpace: String
        /// Pixels per inch along its width and height, as placed on the page.
        public let dpi: CGSize
        public let rect: CGRect
    }

    public struct Path: Equatable, Sendable {
        /// In points; nil for a path that's only filled.
        public let strokeWidth: CGFloat?
        public let strokeColor: RGB?
        public let fillColor: RGB?
        public let colorSpace: String
        public let opacity: CGFloat
        public let rect: CGRect
    }

    public struct RGB: Equatable, Sendable {
        public let red, green, blue: CGFloat

        /// As `#RRGGBB`.
        public var hex: String {
            func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
            return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        }

        public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    }

    public let pageIndex: Int
    /// Where on the page was inspected.
    public let point: CGPoint
    public let text: Text?
    public let image: Image?
    public let path: Path?

    public var isEmpty: Bool { text == nil && image == nil && path == nil }

    /// A font name as the Inspector shows it: `ABCDEF+Helvetica` is a subset of Helvetica.
    static func fontName(_ raw: String) -> (name: String, isSubset: Bool) {
        let parts = raw.split(separator: "+", maxSplits: 1)
        if parts.count == 2, parts[0].count == 6, parts[0].allSatisfy({ $0.isUppercase && $0.isASCII }) {
            return (String(parts[1]), true)
        }
        return (raw, false)
    }
}

extension PDFDocumentCore {
    /// What the page's contents draw at `point` (page coordinates), within `tolerance` points.
    public func inspectContent(pageIndex: Int, at point: CGPoint, tolerance: CGFloat = 2) -> PageContentInspection? {
        guard pageIndex >= 0, pageIndex < pageCount else { return nil }
        var raw = mupdf_content_at_point()
        let ok = withLockedDocument { ctx, doc in
            mupdf_page_inspect_point(ctx, doc, Int32(pageIndex), Float(point.x), Float(point.y), Float(tolerance), &raw, nil) == 0
        }
        guard ok else { return nil }
        func string<T>(_ field: inout T) -> String {
            withUnsafeBytes(of: &field) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        }
        func rgb(_ c: (Float, Float, Float)) -> PageContentInspection.RGB {
            .init(red: CGFloat(c.0), green: CGFloat(c.1), blue: CGFloat(c.2))
        }
        func rect(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) -> CGRect {
            CGRect(x: CGFloat(x0), y: CGFloat(y0), width: CGFloat(x1 - x0), height: CGFloat(y1 - y0))
        }
        var text: PageContentInspection.Text?
        if raw.has_text != 0 {
            let font = PageContentInspection.fontName(string(&raw.font_name))
            let scalar = raw.text_unicode > 32 ? Unicode.Scalar(UInt32(raw.text_unicode)) : nil
            text = .init(
                fontName: font.name.isEmpty ? "Unnamed font" : font.name,
                isSubset: font.isSubset,
                isSubstitute: raw.font_is_substitute != 0,
                fontSize: CGFloat(raw.font_size),
                character: scalar.map { String(Character($0)) },
                isOutlined: raw.text_stroked != 0,
                color: rgb(raw.text_rgb),
                colorSpace: string(&raw.text_colorspace),
                opacity: CGFloat(raw.text_alpha),
                rect: rect(raw.text_x0, raw.text_y0, raw.text_x1, raw.text_y1)
            )
        }
        var image: PageContentInspection.Image?
        if raw.has_image != 0 {
            image = .init(
                pixelWidth: Int(raw.image_width),
                pixelHeight: Int(raw.image_height),
                bitsPerComponent: Int(raw.image_bpc),
                isMask: raw.image_is_mask != 0,
                colorSpace: string(&raw.image_colorspace),
                dpi: CGSize(width: CGFloat(raw.image_dpi_x), height: CGFloat(raw.image_dpi_y)),
                rect: rect(raw.image_x0, raw.image_y0, raw.image_x1, raw.image_y1)
            )
        }
        var path: PageContentInspection.Path?
        if raw.has_path != 0 {
            path = .init(
                strokeWidth: raw.path_stroked != 0 ? CGFloat(raw.stroke_width) : nil,
                strokeColor: raw.path_stroked != 0 ? rgb(raw.stroke_rgb) : nil,
                fillColor: raw.path_filled != 0 ? rgb(raw.fill_rgb) : nil,
                colorSpace: string(&raw.path_colorspace),
                opacity: CGFloat(raw.path_alpha),
                rect: rect(raw.path_x0, raw.path_y0, raw.path_x1, raw.path_y1)
            )
        }
        return PageContentInspection(pageIndex: pageIndex, point: point, text: text, image: image, path: path)
    }

    /// An annotation's opacity, 0 to 1; nil if it can't be read.
    public func annotationOpacity(pageIndex: Int, objectNumber: Int) -> CGFloat? {
        guard isPDF else { return nil }
        var opacity: Float = 1
        let ok = withLockedDocument { ctx, doc in
            mupdf_pdf_annot_opacity(ctx, doc, Int32(pageIndex), Int32(objectNumber), &opacity) == 0
        }
        return ok ? CGFloat(opacity) : nil
    }
}

/// An annotation the Inspector shows.
public struct InspectedAnnotation: Equatable, Sendable {
    public let id: UUID
    public let pageIndex: Int
}

/// A change to an annotation's place or size asked for in the Inspector, carried out by the
/// canvas as a drag would be.
public struct AnnotationGeometryEdit: Equatable, Sendable {
    public let token: Int
    public let annotationID: UUID
    public let pageIndex: Int
    /// How far to move it, in page coordinates.
    public let offset: CGSize
    /// How much wider and taller to make it.
    public let growth: CGSize
}

extension PDFAnnotation {
    /// Whether the Inspector can resize it: one with corner handles on the page.
    public var canResizeInInspector: Bool {
        rect != nil && type != .note && type != .line && !isMeasurement && (!isFromFile || isResizableFromFile)
            && (isFromFile || type == .callout || type == .freeText || type == .stamp || isShape)
    }

    /// Whether the Inspector can move it: one that can be dragged on the page.
    public var canMoveInInspector: Bool {
        isFromFile || isMeasurement || type == .callout || type == .freeText || type == .stamp || type == .note || isShape
    }

    /// The box it fills on the page, for the Inspector's position and size.
    public var inspectorBounds: CGRect? {
        if let rect { return rect }
        let points = !measurementPoints.isEmpty ? measurementPoints : inkPoints
        guard !points.isEmpty else { return quads.isEmpty ? nil : CGRect(enclosing: quads.flatMap { [$0.ul, $0.ur, $0.ll, $0.lr] }) }
        return CGRect(enclosing: points)
    }
}

extension PDFViewerViewModel {
    /// Shows or hides the Inspector. With Search in front of it on the right, brings it forward.
    public func toggleInspector() {
        if isInspectorVisible && !isInspectorOnScreen {
            rightColumnPane = .inspector
        } else {
            isInspectorVisible.toggle()
        }
    }

    /// Looks at what the page draws at `point`, for the Inspector, off the main thread.
    public func inspectContent(pageIndex: Int, at point: CGPoint) {
        guard isInspectorVisible, let doc = document else { return }
        let tolerance = max(1, 3 / max(effectiveZoom, 0.1))
        inspectionTask?.cancel()
        inspectionTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                doc.inspectContent(pageIndex: pageIndex, at: point, tolerance: tolerance)
            }.value
            guard let self, !Task.isCancelled, self.document === doc else { return }
            self.inspectedContent = found
        }
    }

    /// The annotation the Inspector shows, as it is now.
    public var inspectorAnnotation: PDFAnnotation? {
        guard let selected = inspectedAnnotation else { return nil }
        return pageAnnotations[selected.pageIndex]?.first { $0.id == selected.id }
    }

    /// Moves or resizes the Inspector's annotation so its box is `bounds` (page coordinates).
    public func setInspectorAnnotationBounds(_ bounds: CGRect) {
        guard let annotation = inspectorAnnotation, let current = annotation.inspectorBounds else { return }
        let offset = CGSize(width: bounds.minX - current.minX, height: bounds.minY - current.minY)
        let growth = annotation.canResizeInInspector
            ? CGSize(width: bounds.width - current.width, height: bounds.height - current.height)
            : .zero
        guard abs(offset.width) > 0.001 || abs(offset.height) > 0.001 || abs(growth.width) > 0.001 || abs(growth.height) > 0.001 else { return }
        annotationGeometryEdit = AnnotationGeometryEdit(
            token: (annotationGeometryEdit?.token ?? 0) &+ 1,
            annotationID: annotation.id,
            pageIndex: annotation.pageIndex,
            offset: annotation.canMoveInInspector ? offset : .zero,
            growth: growth
        )
    }
}
