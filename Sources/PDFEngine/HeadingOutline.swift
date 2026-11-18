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

import CoreGraphics
import Foundation
import MuPDFBridge

/// A heading found in a document, for an outline built from its headings.
public struct FoundHeading: Sendable, Equatable {
    /// 1 for the top level.
    public var level: Int
    public var title: String
    public var page: Int
    /// The top of its first line, in page space (y down).
    public var top: CGFloat
}

/// Finds a document's headings: from its tags when it's tagged, otherwise from how its text is
/// set. Body text is the style (size, weight, font) most of the text is in; lines set apart from
/// it, larger or bold, are headings when they're short and their style isn't used for running
/// text. Styles rank into levels by size, then weight; within one style, section numbers
/// (`3.2.1`) give the levels.
public enum HeadingOutline {
    /// One line of a page's text, as heading detection sees it.
    struct StyledLine {
        var text: String
        var bbox: CGRect
        var style: Style
        var block: Int
        var firstInBlock: Bool
        /// Which of the page's text columns it's in, from the left; -1 across columns.
        var column = 0
        /// Characters, without spaces.
        var length: Int
    }

    struct Style: Hashable {
        /// In half points.
        var halfPoints: Int
        var isBold: Bool
        var font: String
        var size: CGFloat { CGFloat(halfPoints) / 2 }
    }

    /// The lines of a page's text with the style most of each is set in, in reading order
    /// (column by column).
    static func styledLines(of page: StructuredPage) -> [StyledLine] {
        let lines = unorderedStyledLines(of: page)
        let gutters = PDFLayoutEngine.columnGutters(lines.map(\.bbox), pageWidth: page.bounds.width)
        return PDFLayoutEngine.readingOrdered(lines, gutters: gutters) { $0.bbox }.map { line in
            var line = line
            line.column = gutters.contains { line.bbox.minX < $0 && line.bbox.maxX > $0 } ? -1 : gutters.filter { $0 <= line.bbox.midX }.count
            return line
        }
    }

    private static func unorderedStyledLines(of page: StructuredPage) -> [StyledLine] {
        var result: [StyledLine] = []
        let isLineNumber = SpatialTextSelector.lineNumberTest(for: page.blocks.filter { $0.type == .text }.flatMap(\.lines))
        for (blockIndex, block) in page.blocks.enumerated() where block.type == .text {
            for (lineIndex, line) in block.lines.enumerated() where !isLineNumber(line) {
                let visible = line.characters.filter { !$0.char.isWhitespace }
                guard !visible.isEmpty else { continue }
                let sizes = visible.map(\.size).sorted()
                let size = sizes[sizes.count / 2]
                let letters = visible.filter(\.char.isLetter)
                let bold = !letters.isEmpty && Double(letters.filter(\.isBold).count) >= Double(letters.count) * 0.9
                var fonts: [String: Int] = [:]
                for character in visible { fonts[Self.family(character.fontName), default: 0] += 1 }
                let font = fonts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? ""
                let text = line.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                result.append(StyledLine(text: text, bbox: line.bbox, style: Style(halfPoints: Int((size * 2).rounded()), isBold: bold, font: font),
                                         block: blockIndex, firstInBlock: lineIndex == 0, length: visible.count))
            }
        }
        return result
    }

    /// A font's name without a subset tag (`ABCDEF+`).
    private static func family(_ name: String) -> String {
        if let plus = name.firstIndex(of: "+"), name.distance(from: name.startIndex, to: plus) == 6 {
            return String(name[name.index(after: plus)...])
        }
        return name
    }

    /// Lines next to each other on one baseline in one style ("3.2" and its title, set apart):
    /// joined into one.
    static func joinedRows(_ lines: [StyledLine]) -> [StyledLine] {
        var result: [StyledLine] = []
        for line in lines {
            if let last = result.last, last.style == line.style,
               abs(last.bbox.midY - line.bbox.midY) < min(last.bbox.height, line.bbox.height) * 0.3,
               line.bbox.minX >= last.bbox.maxX - 1, line.bbox.minX - last.bbox.maxX < line.style.size * 3 {
                result[result.count - 1].text += " " + line.text
                result[result.count - 1].bbox = last.bbox.union(line.bbox)
                result[result.count - 1].length += line.length
                continue
            }
            result.append(line)
        }
        return result
    }

    /// Lines in one style one under the other in one block: a paragraph, or a heading over two
    /// lines.
    struct Run {
        var page: Int
        var lines: [StyledLine]
        var isRunning: Bool
        var style: Style { lines[0].style }
        var text: String { lines.map(\.text).joined(separator: " ") }
        var length: Int { lines.reduce(0) { $0 + $1.length } }
        var top: CGFloat { lines[0].bbox.minY }
        /// Another line in its style on its first line's row: a table's headings.
        var sharesRow = false
        /// Another line in its column on its first line's row: a label with its text beside it.
        var hasNeighbour = false
    }

    static func runs(page: Int, lines: [StyledLine], running: Set<Int>) -> [Run] {
        var runs: [Run] = []
        for (index, line) in lines.enumerated() {
            let isRunning = running.contains(index)
            if var last = runs.last, !isRunning, !last.isRunning, let previous = last.lines.last,
               previous.style == line.style, line.bbox.minY > previous.bbox.midY,
               // Not the start of a heading of its own ("TITLE II", "3.2 Scope").
               numberingDepth(line.text) == nil,
               // In one block, or a heading set line by line (centred, say).
               previous.block == line.block
                   ? line.bbox.minY - previous.bbox.maxY < line.style.size
                   : line.bbox.minX < previous.bbox.maxX && line.bbox.maxX > previous.bbox.minX && line.bbox.minY - previous.bbox.maxY < line.style.size {
                last.lines.append(line)
                runs[runs.count - 1] = last
                continue
            }
            runs.append(Run(page: page, lines: [line], isRunning: isRunning))
        }
        for i in runs.indices {
            let first = runs[i].lines[0].bbox
            runs[i].sharesRow = runs.indices.contains { j in
                j != i && runs[j].style == runs[i].style && !runs[j].isRunning
                    && abs(runs[j].lines[0].bbox.midY - first.midY) < first.height * 0.5
            }
        }
        for i in runs.indices {
            let first = runs[i].lines[0]
            runs[i].hasNeighbour = lines.contains { line in
                line.bbox != first.bbox && line.column == first.column && line.bbox.minY < first.bbox.maxY && line.bbox.maxY > first.bbox.minY
                    && abs(line.bbox.midY - first.bbox.midY) < first.bbox.height * 0.5
            }
        }
        return runs
    }

    private static let contentsLine = try! NSRegularExpression(pattern: "(\\.\\s?){4,}\\s*\\S*\\d+\\s*$|\\s(\\.\\s?){2,}\\d+$")
    private static let caption = try! NSRegularExpression(pattern: "^(Figure|Fig\\.|Table|Listing|Algorithm|Equation|Exhibit|Chart|Plate)\\s*[0-9A-Z]")

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static let numbered = try! NSRegularExpression(pattern: "^(?:(\\d+(?:\\.\\d+)*)|([A-Z](?:\\.\\d+)+)|([A-Z]|[IVXL]+)\\.)\\.?\\s+[^\\sa-z]")
    private static let appendix = try! NSRegularExpression(pattern: "^(?i:appendix|annex|chapter|part|title|division|subtitle|article|section|book|schedule)\\s+([A-Z]|[0-9]+|[IVXLC]+)\\b")

    /// How deep a heading's number is: 2 for "3.1 Scope" or "A.1 Tables", 1 for "3 Scope",
    /// "Annex B", "TITLE II" or "IV. Results"; nil for none.
    static func numberingDepth(_ title: String) -> Int? {
        let range = NSRange(title.startIndex..., in: title)
        if let match = numbered.firstMatch(in: title, range: range) {
            for group in 1...2 {
                if let r = Range(match.range(at: group), in: title) {
                    return title[r].split(separator: ".").count
                }
            }
            return 1
        }
        if appendix.firstMatch(in: title, range: range) != nil { return 1 }
        return nil
    }

    /// The headings of `pages` (their bounds and text lines), in order.
    static func headings(pages: [(bounds: CGRect, lines: [StyledLine])]) -> [FoundHeading] {
        let pages = pages.map { ($0.bounds, joinedRows($0.lines)) }
        let running = ComparedText.runningLines(pages: pages.map { bounds, lines in
            (bounds, lines.map { ComparedText.Line(text: $0.text, bbox: $0.bbox, words: [], joinsNext: false) })
        })
        let allRuns = pages.enumerated().flatMap { index, page in runs(page: index, lines: page.1, running: running[index]) }

        // Body text: the style with the most characters.
        var characters: [Style: Int] = [:]
        for run in allRuns where !run.isRunning { characters[run.style, default: 0] += run.length }
        guard let body = characters.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key.halfPoints > $1.key.halfPoints) })?.key else { return [] }
        let bodyCharacters = characters[body] ?? 0

        func isStrong(_ style: Style) -> Bool { style.size >= body.size * 1.12 }
        let candidates = allRuns.filter { run in
            guard !run.isRunning, run.style != body, run.lines.count <= 3, run.length <= 160,
                  run.text.filter(\.isLetter).count >= 2,
                  !matches(contentsLine, run.text), !matches(caption, run.text), !isSentence(run.text) else { return false }
            if isStrong(run.style) { return true }
            // Bold, at about the body's size: only on a line of its own at the start of a block,
            // not one of a row (a table's headings).
            return run.style.isBold && !body.isBold && run.style.size >= body.size * 0.92
                && run.lines[0].firstInBlock && run.lines.count <= 2 && !run.sharesRow && !run.hasNeighbour
                && !(run.text.hasPrefix("[") && run.text.hasSuffix("]"))
        }

        // Words set in a style within running text, by style.
        var inline: [Style: Int] = [:]
        for run in allRuns where !run.isRunning && run.hasNeighbour { inline[run.style, default: 0] += run.length }

        // Styles that set running text, not headings, are left out.
        var byStyle: [Style: [Run]] = [:]
        for run in candidates { byStyle[run.style, default: []].append(run) }
        let pageCount = pages.count
        let accepted = byStyle.filter { style, runs in
            let total = runs.reduce(0) { $0 + $1.length }
            let used = characters[style] ?? total
            guard used <= bodyCharacters / 2, total / runs.count <= 90, runs.count <= max(8, pageCount * 6) else { return false }
            // Mostly headings, not words emphasized in running text.
            guard total * 10 >= (total + (inline[style] ?? 0)) * 6 else { return false }
            // A title: once or twice, on the first page only, of a longer document.
            if pageCount > 3, runs.count <= 2, runs.allSatisfy({ $0.page == 0 }) { return false }
            return true
        }
        guard !accepted.isEmpty else { return [] }

        // Levels: larger first, then bold first; within a style, by section number depth if most
        // of its headings are numbered at more than one depth.
        let styles = accepted.keys.sorted { a, b in
            if isStrong(a) != isStrong(b) { return isStrong(a) }
            if a.halfPoints != b.halfPoints { return a.halfPoints > b.halfPoints }
            if a.isBold != b.isBold { return a.isBold }
            return firstOccurrence(of: a, in: candidates) < firstOccurrence(of: b, in: candidates)
        }
        var numberedStyles = Set<Style>()
        for style in styles {
            let depths = accepted[style]!.compactMap { numberingDepth($0.text) }
            if depths.count * 2 >= accepted[style]!.count, Set(depths).count > 1 { numberedStyles.insert(style) }
        }
        func key(_ run: Run) -> [Int] {
            let rank = styles.firstIndex(of: run.style)!
            guard numberedStyles.contains(run.style) else { return [rank, 0] }
            return [rank, numberingDepth(run.text) ?? 1]
        }
        let keys = Set(candidates.filter { accepted[$0.style] != nil }.map(key)).sorted { $0.lexicographicallyPrecedes($1) }
        return candidates.compactMap { run in
            guard accepted[run.style] != nil, let level = keys.firstIndex(of: key(run)) else { return nil }
            return FoundHeading(level: min(level + 1, 6), title: run.text, page: run.page, top: run.top)
        }
    }

    /// Reads as a sentence, not a heading: ends in a colon (an instruction, "as follows:"), or
    /// is long and ends in a full stop.
    static func isSentence(_ text: String) -> Bool {
        text.hasSuffix(":") || (text.hasSuffix(".") && text.split(separator: " ").count >= 10)
    }

    private static func firstOccurrence(of style: Style, in runs: [Run]) -> Int {
        runs.firstIndex { $0.style == style } ?? .max
    }

    /// The entries of an outline of `headings`, each nested in the one before it of a higher
    /// level, going to `uri(page, y)`.
    static func entries(_ headings: [FoundHeading], uri: (Int, CGFloat) throws -> String) rethrows -> [OutlineEntryCopy] {
        var stack: [Int] = []  // levels of the entries open, outermost first
        var result: [OutlineEntryCopy] = []
        for heading in headings {
            while let last = stack.last, last >= heading.level { stack.removeLast() }
            result.append(OutlineEntryCopy(level: stack.count, title: heading.title, uri: try uri(heading.page, max(0, heading.top - 4)),
                                           isOpen: stack.isEmpty, flags: 0, color: (0, 0, 0)))
            stack.append(heading.level)
        }
        return result
    }
}

extension PDFDocumentCore {
    /// The document's headings, from its tags if it's tagged and they give some, otherwise from
    /// its text's styles. `progress` is told each page read; `isCancelled` stops it (nil).
    public func findHeadings(progress: (Int) -> Void = { _ in }, isCancelled: () -> Bool = { false }) -> [FoundHeading]? {
        guard isPDF else { return [] }
        if (try? withLockedDocument({ ctx, doc in mupdf_pdf_is_tagged(ctx, doc) != 0 })) == true {
            var tagged: [FoundHeading] = []
            for page in 0..<pageCount {
                if isCancelled() { return nil }
                tagged += taggedHeadings(onPage: page)
                progress(page + 1)
            }
            if tagged.count >= 2 { return tagged }
        }
        var pages: [(bounds: CGRect, lines: [HeadingOutline.StyledLine])] = []
        for page in 0..<pageCount {
            if isCancelled() { return nil }
            let structured = loadStructuredPage(for: page)
            pages.append((structured?.bounds ?? .zero, structured.map(HeadingOutline.styledLines) ?? []))
            progress(page + 1)
        }
        return HeadingOutline.headings(pages: pages)
    }

    private func taggedHeadings(onPage page: Int) -> [FoundHeading] {
        (try? withLockedDocument { ctx, doc -> [FoundHeading] in
            var list: UnsafeMutablePointer<vp_tagged_heading>?
            var count: Int32 = 0
            guard mupdf_page_tagged_headings(ctx, doc, Int32(page), &list, &count, nil) == 0 else { return [] }
            defer { mupdf_tagged_headings_free(ctx, list, count) }
            return UnsafeBufferPointer(start: list, count: Int(count)).compactMap { h in
                let title = String(cString: h.text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
                guard !title.isEmpty else { return nil }
                return FoundHeading(level: max(1, Int(h.level)), title: title, page: page, top: CGFloat(h.bbox.y0))
            }
        }) ?? []
    }

    /// Replaces the outline with one of `headings`; returns the edits that undo it, to make in
    /// order.
    public func replaceOutline(with headings: [FoundHeading]) throws -> [OutlineEdit] {
        let entries = try HeadingOutline.entries(headings) { page, y in try outlinePageURI(page: page, y: y) }
        var undo: [OutlineEdit] = []
        if !outline.isEmpty {
            undo.append(try applyOutlineEdit(.deleteSeveral([0], count: outline.count)))
        }
        if !entries.isEmpty {
            undo.append(try applyOutlineEdit(.insert([0], entries)))
        }
        return undo.reversed()
    }
}
