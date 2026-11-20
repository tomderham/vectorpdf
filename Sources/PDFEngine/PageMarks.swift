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

        /// A picture (PNG) to use instead of the text, such as a logo; and how much of the page's
        /// width it takes (0.5 if not set).
        public var image: Data?
        public var imageScale: Double?

        public var isEmpty: Bool { image == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
        let bounds = pageBounds
        try withLockedDocument { ctx, doc in
            var error: UnsafePointer<CChar>?
            guard mupdf_pdf_remove_page_marks(ctx, doc, MUPDF_PAGE_MARK_HEADER_FOOTER | MUPDF_PAGE_MARK_WATERMARK, &error) >= 0 else {
                throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "The old marks can't be removed")
            }
            // A picture watermark is in the file once, drawn on each page.
            var imageObject: Int32 = 0
            if let image = settings.watermark.image, !pages.isEmpty {
                guard image.withUnsafeBytes({ mupdf_pdf_add_mark_image(ctx, doc, $0.bindMemory(to: UInt8.self).baseAddress, $0.count, &imageObject, &error) }) == 0 else {
                    throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "The watermark's picture can't be added")
                }
            }
            // Text the standard fonts can't show, laid out first so its fonts can be embedded
            // once; again without any font that couldn't be.
            var avoiding = Set<String>()
            var shaped = Self.shapedMarks(settings, pages: pages, bounds: bounds, pageCount: shownPageCount, date: date, fileName: fileName,
                                          fonts: PageMarkShaping.Fonts(), avoiding: avoiding)
            for _ in 0..<4 {
                let failed = shaped.fonts.embed(ctx: ctx, doc: doc)
                guard !failed.isEmpty, !failed.isSubset(of: avoiding) else { break }
                avoiding.formUnion(failed)
                // Laid out again, the text may use glyphs of a font embedded already that it
                // didn't before (falling back to it): `embed` adds them.
                shaped = Self.shapedMarks(settings, pages: pages, bounds: bounds, pageCount: shownPageCount, date: date, fileName: fileName,
                                          fonts: PageMarkShaping.Fonts(after: shaped.fonts), avoiding: avoiding)
            }
            if !shaped.fonts.allEmbedded { _ = shaped.fonts.embed(ctx: ctx, doc: doc) }
            for (index, page) in pages.enumerated() {
                for mark in shaped.marks[page] ?? [] {
                    try PageMarkShaping.addMark(ctx: ctx, doc: doc, page: page, fonts: shaped.fonts, lines: mark.lines, size: mark.size,
                                                kind: mark.kind, artifact: mark.artifact, color: mark.color, opacity: mark.opacity,
                                                matrix: mark.matrix, text: mark.text)
                }
                if imageObject > 0 {
                    let wm = settings.watermark
                    var mark = mupdf_watermark()
                    mark.opacity = Float(wm.opacity)
                    mark.rotation = Float(wm.rotation)
                    mark.behind = wm.behindContent ? 1 : 0
                    guard mupdf_page_add_image_watermark(ctx, doc, Int32(page), imageObject, Float(wm.imageScale ?? 0.5), &mark, &error) == 0 else {
                        throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "The watermark can't be added")
                    }
                } else if !settings.watermark.isEmpty, !shaped.shapedWatermark.contains(page) {
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
                    // Slots laid out as shaped glyphs are left out here.
                    let texts = hf.texts.map { settings.expand($0, index: index, pageCount: shownPageCount, date: date, fileName: fileName) }
                        .map { PageMarkShaping.fitsStandardFonts($0) ? $0 : "" }
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

    /// A mark in characters the standard fonts lack, laid out: lines with their origins in the
    /// mark's space, placed on the page (as shown, bottom-up) by `matrix`.
    struct ShapedMark {
        var lines: [(PageMarkShaping.Line, CGPoint)]
        var size: CGFloat
        var kind: String
        var artifact: String
        var color: PageMarkSettings.MarkColor
        var opacity: Double?
        var matrix: CGAffineTransform
        var text: String
    }

    /// The marks on `pages` whose text the standard fonts can't show, laid out as the C side
    /// lays out the others, with the fonts they need.
    static func shapedMarks(_ settings: PageMarkSettings, pages: [Int], bounds: [CGRect], pageCount: Int, date: Date, fileName: String,
                            fonts: PageMarkShaping.Fonts, avoiding: Set<String>)
        -> (marks: [Int: [ShapedMark]], fonts: PageMarkShaping.Fonts, shapedWatermark: Set<Int>) {
        var marks: [Int: [ShapedMark]] = [:]
        var shapedWatermark = Set<Int>()
        for (index, page) in pages.enumerated() where page < bounds.count {
            let width = bounds[page].width, height = bounds[page].height
            let hf = settings.header
            if !hf.isEmpty {
                let size = CGFloat(hf.size > 0 ? hf.size : 10)
                for slot in 0..<6 {
                    let text = settings.expand(hf.texts[slot], index: index, pageCount: pageCount, date: date, fileName: fileName)
                    guard !text.isEmpty, !PageMarkShaping.fitsStandardFonts(text) else { continue }
                    let line = PageMarkShaping.shape(text, font: hf.font, size: size, avoiding: avoiding)
                    fonts.add(line)
                    let row = slot / 3, col = slot % 3
                    let x = col == 0 ? CGFloat(hf.marginLeft) : col == 1 ? (width - line.width) / 2 : width - CGFloat(hf.marginRight) - line.width
                    let y = row == 0 ? height - CGFloat(hf.marginTop) - size * 0.75 : CGFloat(hf.marginBottom)
                    marks[page, default: []].append(ShapedMark(lines: [(line, .zero)], size: size, kind: "HeaderFooter", artifact: row == 0 ? "Header" : "Footer",
                                                               color: hf.color, opacity: nil, matrix: CGAffineTransform(translationX: x, y: y), text: text))
                }
            }
            let wm = settings.watermark
            if wm.image == nil, !wm.isEmpty {
                let text = settings.expand(wm.text, index: index, pageCount: pageCount, date: date, fileName: fileName)
                guard !PageMarkShaping.fitsStandardFonts(text) else { continue }
                let texts = Array(text.components(separatedBy: "\n").prefix(16))
                var size = CGFloat(wm.size)
                if size <= 0 {
                    // As large as fits, as for the standard fonts: inside 80% of the page.
                    let widest = texts.map { PageMarkShaping.shape($0, font: wm.font, size: 100, avoiding: avoiding).width / 100 }.max() ?? 1
                    let angle = wm.rotation * .pi / 180, c = abs(cos(angle)), s = abs(sin(angle))
                    let blockW = max(Double(widest), 0.01), blockH = Double(texts.count) * 1.2
                    size = CGFloat(min(min(Double(width) * 0.8 / (c * blockW + s * blockH), Double(height) * 0.8 / (s * blockW + c * blockH)), 400))
                }
                let leading = size * 1.2
                let top = CGFloat(texts.count - 1) * leading / 2 - size * 0.35
                var lines: [(PageMarkShaping.Line, CGPoint)] = []
                for (i, lineText) in texts.enumerated() {
                    let line = PageMarkShaping.shape(lineText, font: wm.font, size: size, avoiding: avoiding)
                    fonts.add(line)
                    lines.append((line, CGPoint(x: -line.width / 2, y: top - CGFloat(i) * leading)))
                }
                let angle = wm.rotation * .pi / 180
                let matrix = CGAffineTransform(a: CGFloat(cos(angle)), b: CGFloat(sin(angle)), c: CGFloat(-sin(angle)), d: CGFloat(cos(angle)), tx: width / 2, ty: height / 2)
                marks[page, default: []].append(ShapedMark(lines: lines, size: size, kind: wm.behindContent ? "WatermarkBehind" : "Watermark", artifact: "Watermark",
                                                           color: wm.color, opacity: wm.opacity, matrix: matrix, text: text))
                shapedWatermark.insert(page)
            }
        }
        return (marks, fonts, shapedWatermark)
    }

    /// Headers, footers and watermarks other apps added: the pages with any, and which kinds
    /// (header, footer, watermark) are found.
    public func otherAppsMarks() -> (pages: [Int], header: Bool, footer: Bool, watermark: Bool) {
        guard isPDF else { return ([], false, false, false) }
        let found: [Int: Int32] = withLockedDocument { ctx, doc in
            var found: [Int: Int32] = [:]
            for page in 0..<pageCount {
                let kinds = mupdf_page_foreign_marks(ctx, doc, Int32(page))
                if kinds != 0 { found[page] = kinds }
            }
            return found
        }
        let all = found.values.reduce(Int32(0)) { $0 | $1 }
        return (found.keys.sorted(), all & 1 != 0, all & 2 != 0, all & 4 != 0)
    }

    /// Takes off the headers, footers and watermarks other apps added to `pages`, leaving
    /// VectorPDF's own.
    public func removeOtherAppsMarks(pages: [Int]) throws {
        try withLockedDocument { ctx, doc in
            for page in pages {
                var error: UnsafePointer<CChar>?
                guard mupdf_page_remove_foreign_marks(ctx, doc, Int32(page), &error) == 0 else {
                    throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "The other app's marks can't be removed")
                }
            }
        }
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

/// Marks on several files at once, Bates numbers running on from one to the next.
public enum PageMarksBatch {
    public struct Result: Sendable {
        /// The files written, in order.
        public var written: [URL] = []
        /// Files that couldn't be marked, with why.
        public var failed: [(file: String, reason: String)] = []
        /// The first and last Bates numbers used, if any pages were marked.
        public var firstBates: String?
        public var lastBates: String?
    }

    /// Marks each of `files`, in name order, with `settings`, writing a copy of each into
    /// `folder` (never over the file itself); each file's Bates numbers start where the last
    /// one's ended. `progress` is told after each file; `isCancelled` stops before the next.
    public static func mark(_ files: [URL], with settings: PageMarkSettings, into folder: URL, date: Date = Date(),
                            progress: (Int) -> Void = { _ in }, isCancelled: () -> Bool = { false }) -> Result {
        var result = Result()
        var next = settings.bates.start
        let ordered = files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for (index, file) in ordered.enumerated() {
            if isCancelled() { break }
            defer { progress(index + 1) }
            let destination = folder.appendingPathComponent(file.lastPathComponent)
            guard destination.standardizedFileURL.path != file.standardizedFileURL.path else {
                result.failed.append((file.lastPathComponent, "It would be saved over itself. Choose another folder."))
                continue
            }
            do {
                let doc = try PDFDocumentCore(filePath: file.path)
                guard doc.isPDF else { throw PDFError.operationFailed("It isn't a PDF.") }
                var own = settings
                own.bates.start = next
                // Its own marks, if it has some from VectorPDF, are replaced.
                let marked = own.pages.indices(pageCount: doc.pageCount).count
                try doc.applyPageMarks(own, date: date)
                try doc.save(to: destination.path)
                if marked > 0 {
                    if result.firstBates == nil { result.firstBates = own.bates.number(0) }
                    result.lastBates = own.bates.number(marked - 1)
                }
                next += marked
                result.written.append(destination)
            } catch PDFError.passwordRequired {
                result.failed.append((file.lastPathComponent, "It needs a password."))
            } catch {
                result.failed.append((file.lastPathComponent, error.localizedDescription))
            }
        }
        return result
    }
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
    public func image(_ settings: PageMarkSettings, width: CGFloat, removingOtherAppsMarks: Bool = false, date: Date = Date()) throws -> CGImage? {
        let doc = try PDFDocumentCore(filePath: copy.path)
        if removingOtherAppsMarks { try doc.removeOtherAppsMarks(pages: [0]) }
        let shown = Self.settings(settings, forPage: pageIndex, of: pageCount)
        try doc.applyPageMarks(shown, date: date, pageCount: pageCount, fileName: fileName)
        guard let bounds = doc.pageBounds.first, bounds.width > 0,
              let data = doc.renderPageRect(pageIndex: 0, rect: bounds, scale: width / bounds.width) else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
