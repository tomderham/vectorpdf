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
import Foundation
import ImageIO
import MuPDFBridge

/// Headers, footers (with page and Bates numbers) and a watermark, as chosen in the Headers,
/// Footers and Watermark sheet. Kept in the document with the marks, so they can be changed.
public struct PageMarkSettings: Codable, Equatable, Sendable {
    public var header = HeaderFooter()
    public var watermark = Watermark()
    public var pages = PageChoice()
    /// The number `<<page>>` gives the first page marked.
    public var firstPageNumber = 1
    public var bates = Bates()

    public init() {}

    public struct HeaderFooter: Codable, Equatable, Sendable {
        /// Top left, centre, right, then bottom left, centre, right.
        public var texts = ["", "", "", "", "", ""]
        public var font = MarkFont.helvetica
        public var size: Double = 10
        public var color = MarkColor(red: 0, green: 0, blue: 0)
        /// Points, from the page's edges as shown.
        public var marginTop: Double = 36
        public var marginBottom: Double = 30
        public var marginLeft: Double = 72
        public var marginRight: Double = 72

        public init() {}

        public var isEmpty: Bool { texts.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    public struct Watermark: Codable, Equatable, Sendable {
        public var text = ""
        public var font = MarkFont.helveticaBold
        /// Points; 0 for as large as fits the page.
        public var size: Double = 0
        public var color = MarkColor(red: 0.6, green: 0.6, blue: 0.6)
        public var opacity: Double = 0.3
        /// Degrees, anticlockwise.
        public var rotation: Double = 45
        public var behindContent = false

        public init() {}

        public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public struct PageChoice: Codable, Equatable, Sendable {
        public enum Which: String, Codable, Sendable, CaseIterable { case all, odd, even }
        public var which = Which.all
        /// 1-based, inclusive; nil for the first or last page.
        public var from: Int?
        public var to: Int?

        public init() {}

        /// The page indices chosen, of `pageCount`.
        public func indices(pageCount: Int) -> [Int] {
            let first = max(1, from ?? 1), last = min(pageCount, to ?? pageCount)
            guard first <= last else { return [] }
            return (first...last).filter { number in
                switch which {
                case .all: return true
                case .odd: return number % 2 == 1
                case .even: return number % 2 == 0
                }
            }.map { $0 - 1 }
        }
    }

    public struct Bates: Codable, Equatable, Sendable {
        public var prefix = ""
        public var suffix = ""
        public var digits = 6
        public var start = 1

        public init() {}

        /// The Bates number of the `index`th page marked (0 for the first).
        public func number(_ index: Int) -> String {
            let value = String(start + index)
            let padded = String(repeating: "0", count: max(0, digits - value.count)) + value
            return prefix + padded + suffix
        }
    }

    public enum MarkFont: Int, Codable, Sendable, CaseIterable {
        case helvetica = 0, times = 1, courier = 2, helveticaBold = 3

        public var displayName: String {
            switch self {
            case .helvetica: return "Helvetica"
            case .times: return "Times"
            case .courier: return "Courier"
            case .helveticaBold: return "Helvetica Bold"
            }
        }
    }

    public struct MarkColor: Codable, Equatable, Sendable {
        public var red: Double, green: Double, blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red; self.green = green; self.blue = blue
        }

        public init(_ color: NSColor) {
            let rgb = color.usingColorSpace(.sRGB) ?? .black
            self.init(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
        }

        public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    }

    public var isEmpty: Bool { header.isEmpty && watermark.isEmpty }

    /// The words `<<...>>` in a header, footer or watermark stand for.
    public enum Token: String, CaseIterable, Sendable {
        case page = "<<page>>", pageCount = "<<pages>>", bates = "<<bates>>", date = "<<date>>", fileName = "<<file>>"

        public var title: String {
            switch self {
            case .page: return "Page Number"
            case .pageCount: return "Page Count"
            case .bates: return "Bates Number"
            case .date: return "Date"
            case .fileName: return "File Name"
            }
        }
    }

    /// `text` for the `index`th page marked (0 for the first), the document having `pageCount` pages.
    public func expand(_ text: String, index: Int, pageCount: Int, date: Date, fileName: String) -> String {
        guard text.contains("<<") else { return text }
        return text
            .replacingOccurrences(of: Token.page.rawValue, with: String(firstPageNumber + index))
            .replacingOccurrences(of: Token.pageCount.rawValue, with: String(pageCount))
            .replacingOccurrences(of: Token.bates.rawValue, with: bates.number(index))
            .replacingOccurrences(of: Token.date.rawValue, with: date.formatted(date: .numeric, time: .omitted))
            .replacingOccurrences(of: Token.fileName.rawValue, with: fileName)
    }
}

extension PDFDocumentCore {
    /// What kinds of mark the pages have.
    public func pageMarkKinds() -> (headerFooter: Bool, watermark: Bool) {
        guard isPDF else { return (false, false) }
        let found = withLockedDocument { ctx, doc in mupdf_pdf_page_marks(ctx, doc) }
        return (found & MUPDF_PAGE_MARK_HEADER_FOOTER != 0, found & MUPDF_PAGE_MARK_WATERMARK != 0)
    }

    /// The settings the marks were made with, if VectorPDF made them.
    public func pageMarkSettings() -> PageMarkSettings? {
        guard isPDF else { return nil }
        let json: String? = withLockedDocument { ctx, doc in
            guard let raw = mupdf_pdf_page_marks_settings(ctx, doc) else { return nil }
            defer { fz_free(ctx, raw) }
            return String(cString: raw)
        }
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PageMarkSettings.self, from: data)
    }

    /// Takes off the headers, footers and watermark VectorPDF added, and puts on these instead
    /// (none if `settings` is empty). Returns the pages changed.
    @discardableResult
    /// `pageCount` and `fileName`, if given, are what the page count and file name tokens show
    /// (for a preview on a copy of one page).
    public func applyPageMarks(_ settings: PageMarkSettings, date: Date = Date(), pageCount shownCount: Int? = nil, fileName shownName: String? = nil) throws -> Set<Int> {
        guard isPDF else { throw PDFError.operationFailed("Only PDFs can have headers and footers") }
        let fileName = shownName ?? (filePath as NSString).lastPathComponent
        let count = pageCount
        let shownPageCount = shownCount ?? count
        let before = pageMarkPages()
        let pages = settings.isEmpty ? [] : settings.pages.indices(pageCount: count)
        let json = settings.isEmpty ? nil : String(data: try JSONEncoder().encode(settings), encoding: .utf8)
        try withLockedDocument { ctx, doc in
            var error: UnsafePointer<CChar>?
            guard mupdf_pdf_remove_page_marks(ctx, doc, MUPDF_PAGE_MARK_HEADER_FOOTER | MUPDF_PAGE_MARK_WATERMARK, &error) >= 0 else {
                throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "The old marks can't be removed")
            }
            for (index, page) in pages.enumerated() {
                if !settings.watermark.isEmpty {
                    let wm = settings.watermark
                    let text = settings.expand(wm.text, index: index, pageCount: shownPageCount, date: date, fileName: fileName)
                    let ok = text.withCString { cText -> Bool in
                        var mark = mupdf_watermark()
                        mark.text = cText
                        mark.font = Int32(wm.font.rawValue)
                        mark.size = Float(wm.size)
                        mark.color = (Float(wm.color.red), Float(wm.color.green), Float(wm.color.blue))
                        mark.opacity = Float(wm.opacity)
                        mark.rotation = Float(wm.rotation)
                        mark.behind = wm.behindContent ? 1 : 0
                        return mupdf_page_add_watermark(ctx, doc, Int32(page), &mark, &error) == 0
                    }
                    if !ok { throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "The watermark can't be added") }
                }
                if !settings.header.isEmpty {
                    let hf = settings.header
                    let texts = hf.texts.map { settings.expand($0, index: index, pageCount: shownPageCount, date: date, fileName: fileName) }
                    let ok = withCStrings(texts) { pointers -> Bool in
                        var mark = mupdf_header_footer()
                        mark.text = (pointers[0], pointers[1], pointers[2], pointers[3], pointers[4], pointers[5])
                        mark.font = Int32(hf.font.rawValue)
                        mark.size = Float(hf.size)
                        mark.color = (Float(hf.color.red), Float(hf.color.green), Float(hf.color.blue))
                        mark.margin_top = Float(hf.marginTop)
                        mark.margin_bottom = Float(hf.marginBottom)
                        mark.margin_left = Float(hf.marginLeft)
                        mark.margin_right = Float(hf.marginRight)
                        return mupdf_page_add_header_footer(ctx, doc, Int32(page), &mark, &error) == 0
                    }
                    if !ok { throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "The header and footer can't be added") }
                }
            }
            guard (json ?? "").withCString({ mupdf_pdf_set_page_marks_settings(ctx, doc, $0, &error) }) == 0 else {
                throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "The settings can't be kept")
            }
        }
        return before.union(pages)
    }

    /// The pages that have marks VectorPDF added.
    func pageMarkPages() -> Set<Int> {
        // Cheap enough to ask of every page only when there are marks at all.
        let kinds = pageMarkKinds()
        guard kinds.headerFooter || kinds.watermark else { return [] }
        return Set(0..<pageCount)
    }
}

/// Runs `body` with C strings for `strings` (six of them), NULL for an empty one.
private func withCStrings<R>(_ strings: [String], _ body: ([UnsafePointer<CChar>?]) -> R) -> R {
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { $0.isEmpty ? nil : strdup($0) }
    while pointers.count < 6 { pointers.append(nil) }
    defer { pointers.forEach { free($0) } }
    return body(pointers.map { $0.map { UnsafePointer($0) } })
}

/// Pictures of a page with marks on it, for the sheet's preview, made on a copy of the page so
/// the document isn't changed.
public final class PageMarksPreview: @unchecked Sendable {
    public let pageIndex: Int
    private let copy: URL
    private let pageCount: Int
    private let fileName: String

    /// Copies page `pageIndex` of `document`, as it is (unsaved changes included).
    public init(document: PDFDocumentCore, pageIndex: Int) throws {
        self.pageIndex = pageIndex
        pageCount = document.pageCount
        fileName = (document.filePath as NSString).lastPathComponent
        copy = FileManager.default.temporaryDirectory.appendingPathComponent("VectorPDF-marks-preview-\(UUID().uuidString).pdf")
        try document.extractPages([pageIndex], to: copy)
    }

    deinit { try? FileManager.default.removeItem(at: copy) }

    /// `settings` for a copy of page `pageIndex` alone, numbered as that page is among the
    /// `pageCount` pages; empty if it isn't marked.
    static func settings(_ settings: PageMarkSettings, forPage pageIndex: Int, of pageCount: Int) -> PageMarkSettings {
        guard let position = settings.pages.indices(pageCount: pageCount).firstIndex(of: pageIndex) else { return PageMarkSettings() }
        var shown = settings
        shown.pages = PageMarkSettings.PageChoice()
        shown.firstPageNumber = settings.firstPageNumber + position
        shown.bates.start = settings.bates.start + position
        return shown
    }

    /// The page with `settings`' marks as it would have them in the document (its own page and
    /// Bates numbers), `width` points wide; without marks if `settings` leave the page out.
    public func image(_ settings: PageMarkSettings, width: CGFloat, date: Date = Date()) throws -> CGImage? {
        let doc = try PDFDocumentCore(filePath: copy.path)
        let shown = Self.settings(settings, forPage: pageIndex, of: pageCount)
        try doc.applyPageMarks(shown, date: date, pageCount: pageCount, fileName: fileName)
        guard let bounds = doc.pageBounds.first, bounds.width > 0,
              let data = doc.renderPageRect(pageIndex: 0, rect: bounds, scale: width / bounds.width) else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
