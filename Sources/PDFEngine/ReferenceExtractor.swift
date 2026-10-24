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

/// A textual (unlinked) reference to a part of some document, such as "Section 4.2(b) of the
/// Master Agreement", "Appendix C" or “Payment Terms”.
public struct ParsedReference: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case section, clause, article, part, chapter
        case appendix, annex, schedule, exhibit
        case table, figure
        /// A quoted heading title, with no label or number.
        case quotedTitle
    }

    public let kind: Kind
    /// The label as written ("Section", "Sec.", "§"); empty for quoted titles.
    public let label: String
    /// "4.2(b)", "C", "II"; empty for quoted titles.
    public let identifier: String
    /// The quoted heading, for `.quotedTitle`.
    public let quotedTitle: String?
    /// The title written after a bare subclause number, IEEE/ISO style: "General" in
    /// "35.5.2.3.1 (General)".
    public var title: String? = nil
    /// The document the reference names, e.g. "Master Agreement" from "… of the Master Agreement".
    public let docHint: String?
    /// UTF-16 range of the reference in the text it was found in.
    public let range: NSRange
    /// Where it sits on its page, when extracted from page text.
    public var sourceRect: CGRect?

    /// "Section 4.2", "§ 12", "“Payment Terms”", "35.5.2.3.1 (General)".
    public var displayText: String {
        if let quotedTitle { return "“\(quotedTitle)”" }
        if label.isEmpty { return title.map { "\(identifier) (\($0))" } ?? identifier }
        return label == "§" ? "§ \(identifier)" : "\(label) \(identifier)"
    }

    /// The identifier without trailing parenthesised sub-items: "4.2(b)(iv)" → "4.2".
    public var baseIdentifier: String {
        guard let paren = identifier.firstIndex(of: "(") else { return identifier }
        return identifier[..<paren].trimmingCharacters(in: .whitespaces)
    }

    /// True for "Appendix C"-style references, whose bare identifier is too ambiguous to match
    /// without its label. Dotted ones ("C.3") are specific enough.
    public var needsLabelToMatch: Bool {
        guard kind != .quotedTitle else { return false }
        guard let first = identifier.first else { return true }
        return !first.isNumber && !identifier.contains(".")
    }
}

public enum ReferenceExtractor {
    /// Label spellings, lowercased, for each kind. Used to parse references and to recognise
    /// labelled headings ("Section 4 – Payment") when matching.
    static let labelsByKind: [(kind: ParsedReference.Kind, labels: [String])] = [
        (.section, ["sections", "section", "sec.", "§§", "§"]),
        (.clause, ["clauses", "clause", "cl."]),
        (.article, ["articles", "article", "art."]),
        (.part, ["parts", "part"]),
        (.chapter, ["chapters", "chapter", "ch."]),
        (.appendix, ["appendices", "appendix", "app."]),
        (.annex, ["annexes", "annex", "annexure"]),
        (.schedule, ["schedules", "schedule", "sch."]),
        (.exhibit, ["exhibits", "exhibit"]),
        (.table, ["tables", "table", "tbl."]),
        (.figure, ["figures", "figure", "fig."])
    ]

    static func kind(forLabel label: String) -> ParsedReference.Kind? {
        let lower = label.lowercased()
        return labelsByKind.first { $0.labels.contains(lower) }?.kind
    }

    private static let labelledPattern: NSRegularExpression = {
        // Longest spellings first so "sections" wins over "section".
        let labels = labelsByKind.flatMap(\.labels)
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let identifier = #"(?:\d+|[A-Z]|[IVXLC]+)(?:\.\d+)*(?:\s?\((?:[a-z]{1,4}|\d{1,3})\))*"#
        return try! NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}])("# + labels + #")\s*("# + identifier + #")(?![\p{L}\p{N}])"#,
            options: [.caseInsensitive]
        )
    }()

    /// Unlabelled subclause numbers, as IEEE and ISO standards cite them: "35.5.2.3.1 (General)",
    /// "9.4.2.1", "C.3 (MIB detail)". Group 1 is the number, group 2 the parenthesised title.
    private static let barePattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}.§])((?:\d{1,3}|[A-Z])(?:\.\d{1,3}){1,8})(?![\p{L}\p{N}]|\.\d)(?:\s?\(([A-Z][^()\n]{0,120})\))?"#
    )

    private static let quotedPattern = try! NSRegularExpression(
        pattern: #"[“"]([^”"\n]{3,80})[”"]"#
    )

    private static let docHintPattern = try! NSRegularExpression(
        pattern: #"^\s*,?\s*(?:of|in|to|under)\s+(?:the\s+|this\s+|that\s+)?((?:[A-Z][\p{L}\p{N}&'’\-]*)(?:\s+(?:[A-Z][\p{L}\p{N}&'’\-]*|of|and|&|for|on))*)"#
    )

    /// Every reference in `text`, in order.
    public static func references(in text: String) -> [ParsedReference] {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var results: [ParsedReference] = []

        for match in labelledPattern.matches(in: text, range: whole) {
            let label = ns.substring(with: match.range(at: 1))
            var identifier = ns.substring(with: match.range(at: 2))
            guard let kind = kind(forLabel: label) else { continue }
            // Case-insensitive matching lets "part a" through; a lettered or roman identifier has
            // to be written in capitals ("Appendix C", "Part II").
            if let first = identifier.first, first.isLetter, !first.isUppercase { continue }
            identifier = identifier.replacingOccurrences(of: " (", with: "(")
            results.append(ParsedReference(
                kind: kind,
                label: label,
                identifier: identifier,
                quotedTitle: nil,
                docHint: docHint(in: ns, after: match.range),
                range: match.range
            ))
        }

        for match in barePattern.matches(in: text, range: whole) {
            guard !results.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) else { continue }
            let identifier = ns.substring(with: match.range(at: 1))
            let title = match.range(at: 2).location == NSNotFound ? nil : ns.substring(with: match.range(at: 2))
            // "2.4 GHz", "802.11" and "1.5 times" are numbers, not references: a bare number has
            // to have three levels, or a title after it.
            let levels = identifier.split(separator: ".").count
            guard levels >= 3 || title != nil else { continue }
            var reference = ParsedReference(
                kind: .section,
                label: "",
                identifier: identifier,
                quotedTitle: nil,
                docHint: docHint(in: ns, after: match.range),
                range: match.range
            )
            reference.title = title
            results.append(reference)
        }

        for match in quotedPattern.matches(in: text, range: whole) {
            let title = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            // Headings start with a capital; skips quoted fragments and most scare quotes.
            guard let first = title.first, first.isUppercase || first.isNumber,
                  !results.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) else { continue }
            results.append(ParsedReference(
                kind: .quotedTitle,
                label: "",
                identifier: "",
                quotedTitle: title,
                docHint: docHint(in: ns, after: match.range),
                range: match.range
            ))
        }
        return results.sorted { $0.range.location < $1.range.location }
    }

    /// The reference containing, or else closest to, UTF-16 `offset`. Labelled references win
    /// over quoted titles at equal distance.
    public static func reference(in text: String, nearestTo offset: Int) -> ParsedReference? {
        references(in: text).min { a, b in
            let da = distance(from: offset, to: a.range), db = distance(from: offset, to: b.range)
            if da != db { return da < db }
            return a.kind != .quotedTitle && b.kind == .quotedTitle
        }
    }

    private static func distance(from offset: Int, to range: NSRange) -> Int {
        if offset < range.location { return range.location - offset }
        if offset >= NSMaxRange(range) { return offset - NSMaxRange(range) + 1 }
        return 0
    }

    private static func docHint(in text: NSString, after range: NSRange) -> String? {
        let start = NSMaxRange(range)
        let tail = NSRange(location: start, length: min(120, text.length - start))
        guard tail.length > 0, let match = docHintPattern.firstMatch(in: text as String, range: tail) else { return nil }
        var words = text.substring(with: match.range(at: 1)).split(separator: " ").map(String.init)
        // Trailing connectives belong to the next phrase: "of the Agreement and", "Act for".
        while let last = words.last, ["of", "and", "&", "for", "on"].contains(last) { words.removeLast() }
        // A reference to another labelled part ("Section 4 of Schedule 2") is not a document name.
        if let first = words.first, kind(forLabel: first) != nil { return nil }
        let hint = words.joined(separator: " ")
        return hint.count >= 3 ? hint : nil
    }
}

// MARK: - Page Text

extension ReferenceExtractor {
    /// The reference nearest `point` in the text block under it, with its rect on the page.
    /// Works on the whole block, so references wrapped across lines are still found.
    public static func reference(at point: CGPoint, on page: StructuredPage) -> ParsedReference? {
        let blocks = page.blocks.filter { $0.type == .text && !$0.lines.isEmpty }
        guard let block = blocks.first(where: { $0.bbox.insetBy(dx: -4, dy: -4).contains(point) }) else { return nil }
        let (text, rects) = blockText(block)

        // Nearest character to the click, as a UTF-16 offset into `text`.
        var bestOffset = 0
        var bestDistance = CGFloat.infinity
        for (offset, rect) in rects.enumerated() {
            guard let rect else { continue }
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            let d = dy * 4 + dx
            if d < bestDistance {
                bestDistance = d
                bestOffset = offset
            }
        }

        guard var reference = reference(in: text, nearestTo: bestOffset) else { return nil }
        let lower = reference.range.location, upper = min(NSMaxRange(reference.range), rects.count)
        if lower < upper {
            reference.sourceRect = rects[lower..<upper].compactMap { $0 }.reduce(nil) { $0?.union($1) ?? $1 }
        }
        // Elsewhere in the block, too far from the click to be what was meant.
        if let rect = reference.sourceRect, !rect.insetBy(dx: -120, dy: -24).contains(point) {
            return nil
        }
        return reference
    }

    /// Block text with lines joined by spaces, plus each UTF-16 unit's character rect (nil for
    /// inserted spaces).
    static func blockText(_ block: TextBlock) -> (String, [CGRect?]) {
        var text = ""
        var rects: [CGRect?] = []
        func append(_ ch: Character, _ rect: CGRect?) {
            text.append(ch)
            rects.append(contentsOf: Array(repeating: rect, count: String(ch).utf16.count))
        }
        for (lineIndex, line) in block.lines.enumerated() {
            if lineIndex > 0, text.last != " " {
                // A hyphen at a line end is usually a word break.
                if text.last == "-" || text.last == "\u{00AD}" {
                    text.removeLast()
                    rects.removeLast()
                } else {
                    append(" ", nil)
                }
            }
            for (i, ch) in line.characters.enumerated() {
                append(ch.char, ch.boundingRect)
                if i + 1 < line.characters.count {
                    let next = line.characters[i + 1]
                    let gap = next.boundingRect.minX - ch.boundingRect.maxX
                    if gap > CGFloat(ch.size) * 0.20 && ch.char != " " && next.char != " " {
                        append(" ", nil)
                    }
                }
            }
        }
        return (text, rects)
    }
}
