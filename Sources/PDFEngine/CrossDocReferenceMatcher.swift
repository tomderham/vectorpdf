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

/// Scores how likely a heading is the target of a `ParsedReference`. Pure functions; scores run
/// roughly 0–120, and anything not returned (nil) is not a match.
public enum CrossDocReferenceMatcher {
    /// Lowest score worth offering at all.
    public static let minimumScore = 40
    /// A best candidate at or above this, clearly ahead of the next, is treated like a real link.
    public static let confidentScore = 80
    static let confidentMargin = 10

    // MARK: Outline headings

    /// Score of the outline entry `title` as the target of `reference`.
    public static func outlineScore(title: String, for reference: ParsedReference) -> Int? {
        let normalized = normalize(title)
        if let quoted = reference.quotedTitle {
            let bare = stripNumbering(normalized)
            let wanted = normalize(quoted)
            if bare == wanted || normalized == wanted { return 90 }
            if wanted.count >= 6, bare.hasPrefix(wanted) { return 60 }
            return nil
        }

        // "Section 4.2 Payment" → heading label "section", rest "4.2 payment".
        var rest = normalized
        var headingKind: ParsedReference.Kind?
        if let (kind, remainder) = leadingLabel(of: normalized) {
            headingKind = kind
            rest = remainder
        }
        var labelPenalty = 0
        if let headingKind, headingKind != reference.kind {
            guard let family = family(of: headingKind), family == self.family(of: reference.kind) else { return nil }
            labelPenalty = 20
        }
        if headingKind == nil, reference.needsLabelToMatch { return nil }

        let labelled = headingKind != nil
        let identifier = reference.identifier.lowercased()
        let base = reference.baseIdentifier.lowercased()
        if startsWithIdentifier(rest, identifier) {
            return (labelled ? 100 : 85) - labelPenalty + titleBonus(heading: rest.dropFirst(identifier.count), for: reference)
        }
        // "4.2(b)" has no heading of its own: its section is the next best thing.
        if base != identifier, startsWithIdentifier(rest, base) {
            return (labelled ? 70 : 60) - labelPenalty
        }
        return nil
    }

    /// Bonus when the title cited with a bare number ("35.5.2.3.1 (General)") agrees with the
    /// heading's own. No penalty when it doesn't: cited titles often lag the heading's wording.
    private static func titleBonus(heading: Substring, for reference: ParsedReference) -> Int {
        guard let cited = reference.title.map(normalize), !cited.isEmpty else { return 0 }
        let headingTitle = heading.trimmingCharacters(in: CharacterSet(charactersIn: " .:-"))
        if headingTitle == cited { return 10 }
        if headingTitle.hasPrefix(String(cited.prefix(16))) || cited.hasPrefix(String(headingTitle.prefix(16))) { return 5 }
        return 0
    }

    // MARK: Full-text hits

    /// Score of a search hit for `reference`: `hit` is the matched text, `prefix`/`suffix` the rest
    /// of its line, and `isEmphasised` whether the line is bold or larger than the body text.
    public static func headingHitScore(prefix: String, hit: String, suffix: String, isEmphasised: Bool, for reference: ParsedReference) -> Int? {
        let before = normalize(prefix)
        let after = normalize(suffix)

        if let quoted = reference.quotedTitle {
            // The quoted title should be (nearly) the whole line, after any numbering.
            let leadingOK = before.isEmpty || stripNumbering(before + " x") == "x"
            let trailing = after.trimmingCharacters(in: CharacterSet(charactersIn: ".:"))
            guard leadingOK, trailing.count <= 3, normalize(hit) == normalize(quoted) else { return nil }
            return 75 + (isEmphasised ? 10 : 0)
        }

        // "4.2" inside "4.25" or "4.2.1", or "C" inside "CPI".
        if let next = suffix.first, next.isLetter || next.isNumber { return nil }
        if suffix.hasPrefix("."), suffix.dropFirst().first?.isNumber == true { return nil }

        let hitIsLabelled = leadingLabel(of: normalize(hit)) != nil
        var score: Int
        if before.isEmpty || isEnumeratorOnly(before) {
            if hitIsLabelled {
                score = 70
            } else {
                guard !reference.needsLabelToMatch else { return nil }
                score = 55
            }
        } else {
            // Mid-sentence: almost always another reference ("see Section 4.2"), not the heading.
            let lastWord = before.split(separator: " ").last.map(String.init) ?? ""
            guard hitIsLabelled, !referenceLeadIns.contains(lastWord) else { return nil }
            score = 20
        }

        // What follows a heading number is its title: "4.2 Payment Terms", "4.2. Payment".
        let title = after.trimmingCharacters(in: CharacterSet(charactersIn: ".:)-–— "))
        if let firstOriginal = suffix.trimmingCharacters(in: CharacterSet(charactersIn: ".:)-–— ")).first {
            if firstOriginal.isUppercase { score += 10 }
            else if firstOriginal.isLowercase { score -= 25 }
        } else if title.isEmpty {
            score -= 5
        }
        // A table-of-contents entry ("4.2 Payment Terms ....... 12") is not the heading itself.
        if after.range(of: #"(\.\s?){4,}|\s\d+$"#, options: .regularExpression) != nil { score -= 30 }
        if isEmphasised { score += 10 }
        return score
    }

    /// Whether `line` is set like a heading: mostly bold, or larger than the body text. A bold
    /// term mid-sentence doesn't make a line a heading.
    static func isEmphasised(_ line: TextLine, bodySize: Float) -> Bool {
        let visible = line.characters.filter { !$0.char.isWhitespace }
        guard !visible.isEmpty else { return false }
        let bold = visible.filter(\.isBold).count
        return bold * 2 > visible.count || (visible.first.map { $0.size > bodySize + 0.5 } ?? false)
    }

    // MARK: Document hint

    /// Adjustment for how well a tab's title matches the reference's named document.
    public static func docHintAdjustment(documentTitle: String, hint: String?) -> Int {
        guard let hint else { return 0 }
        let titleWords = Set(words(of: (documentTitle as NSString).deletingPathExtension))
        let hintWords = words(of: hint).filter { $0.count >= 3 && !["the", "this", "that", "and"].contains($0) }
        guard !hintWords.isEmpty else { return 0 }
        // "Master Services Agreement" is often filed as "MSA.pdf".
        let initials = String(hint.split(separator: " ").compactMap { $0.first }.filter(\.isUppercase)).lowercased()
        if initials.count >= 2, titleWords.contains(initials) { return 20 }
        let found = hintWords.filter { titleWords.contains($0) }.count
        if found == hintWords.count { return 20 }
        if found > 0 { return 8 }
        return -10
    }

    // MARK: Ranking

    /// Candidates sorted best first, minus weak ones and near-duplicates, at most `limit`.
    public static func rank<C>(_ candidates: [C], limit: Int = 5, score: (C) -> Int, sameTarget: (C, C) -> Bool) -> [C] {
        var kept: [C] = []
        for candidate in candidates.sorted(by: { score($0) > score($1) }) where score(candidate) >= minimumScore {
            guard !kept.contains(where: { sameTarget($0, candidate) }) else { continue }
            kept.append(candidate)
            if kept.count == limit { break }
        }
        return kept
    }

    /// Whether the best of ranked `scores` is certain enough to present as the target.
    public static func isConfident(_ scores: [Int]) -> Bool {
        guard let best = scores.first, best >= confidentScore else { return false }
        return scores.count < 2 || best - scores[1] >= confidentMargin
    }

    // MARK: Helpers

    private static let referenceLeadIns: Set<String> = [
        "see", "in", "under", "of", "to", "and", "or", "per", "with", "by", "pursuant", "accordance",
        "also", "cf.", "cf", "from", "at", "on", "within", "below", "above", "this", "that", "the"
    ]

    static func normalize(_ s: String) -> String {
        var out = s.lowercased()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "’", with: "'")
        out = out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return out.trimmingCharacters(in: .whitespaces)
    }

    private static func words(of s: String) -> [String] {
        normalize(s).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// The heading label ("section", "appendix", …) a normalised title starts with, if any, and
    /// the rest of the title.
    static func leadingLabel(of normalized: String) -> (ParsedReference.Kind, String)? {
        for (kind, labels) in ReferenceExtractor.labelsByKind {
            for label in labels.sorted(by: { $0.count > $1.count }) where normalized.hasPrefix(label) {
                let rest = normalized.dropFirst(label.count)
                // "Partnership" isn't "Part".
                if let next = rest.first, next.isLetter { continue }
                return (kind, rest.trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private static func family(of kind: ParsedReference.Kind) -> Int? {
        switch kind {
        case .section, .clause, .article: return 0
        case .appendix, .annex, .schedule, .exhibit: return 1
        default: return nil
        }
    }

    /// `s` starts with `identifier` as a whole token: "4.2 payment" and "4.2. payment" but not
    /// "4.25", "4.2.1" or "ii" in "iii".
    static func startsWithIdentifier(_ s: String, _ identifier: String) -> Bool {
        guard !identifier.isEmpty, s.hasPrefix(identifier) else { return false }
        let rest = s.dropFirst(identifier.count)
        guard let next = rest.first else { return true }
        if next.isLetter || next.isNumber { return false }
        if next == ".", rest.dropFirst().first?.isNumber == true { return false }
        // "4.2" against "4.2(b) …" heading is a sub-item heading, not 4.2 itself.
        if next == "(" && !identifier.hasSuffix(")") { return false }
        return true
    }

    /// Strips leading numbering and labels: "section 4.2 - payment terms" → "payment terms".
    static func stripNumbering(_ normalized: String) -> String {
        var rest = normalized
        if let (_, remainder) = leadingLabel(of: rest) { rest = remainder }
        let pattern = #"^(?:[0-9]+(?:\.[0-9]+)*|[a-z]|[ivxlc]+)\.?\)?\s*[-:.]?\s*"#
        if let range = rest.range(of: pattern, options: .regularExpression), !range.isEmpty,
           rest[range].contains(where: { $0 == " " || $0 == "." || $0 == ")" || $0 == ":" || $0 == "-" }) {
            rest = String(rest[range.upperBound...])
        }
        return rest
    }

    /// Text before a hit that is only list/section numbering ("§", "1.", "(a)").
    private static func isEnumeratorOnly(_ normalized: String) -> Bool {
        normalized.count <= 6 && normalized.allSatisfy { "§().-0123456789 ".contains($0) }
    }
}

// MARK: - Finding candidates in open tabs

/// A likely target of a reference in another open document.
public struct ReferenceCandidate: Identifiable {
    public let id = UUID()
    public let viewModel: PDFViewerViewModel
    public let documentTitle: String
    /// The heading or line that matched.
    public let heading: String
    public let target: SnapshotTarget
    public let score: Int
}

@MainActor
public enum CrossDocReferenceFinder {
    /// Outline-only candidates: instant, since outlines are already loaded.
    public static func outlineCandidates(for reference: ParsedReference, in viewModels: [PDFViewerViewModel]) -> [ReferenceCandidate] {
        var found: [ReferenceCandidate] = []
        // Cheap substring test first: standards have outlines thousands of entries long, and
        // this runs on every right-click.
        let needle = reference.quotedTitle ?? reference.baseIdentifier
        for vm in viewModels {
            guard let doc = vm.document else { continue }
            let adjustment = CrossDocReferenceMatcher.docHintAdjustment(documentTitle: vm.documentTitle, hint: reference.docHint)
            func visit(_ nodes: [PDFOutlineNode]) {
                for node in nodes {
                    if node.title.range(of: needle, options: .caseInsensitive) != nil,
                       let score = CrossDocReferenceMatcher.outlineScore(title: node.title, for: reference),
                       let target = outlineTarget(node, in: doc) {
                        found.append(ReferenceCandidate(viewModel: vm, documentTitle: vm.documentTitle, heading: node.title, target: target, score: score + adjustment))
                    }
                    visit(node.children)
                }
            }
            visit(doc.outline)
        }
        return rank(found)
    }

    /// Outline matches, best first; failing those, heading-like full-text hits.
    public static func candidates(for reference: ParsedReference, in viewModels: [PDFViewerViewModel]) async -> [ReferenceCandidate] {
        // Any outline match beats waiting: full-text search of a long standard takes seconds.
        let outline = outlineCandidates(for: reference, in: viewModels)
        if !outline.isEmpty { return outline }
        // The reference names a document none of these tabs is ("… of NIST SP 800-56A").
        let adjustments = viewModels.map { CrossDocReferenceMatcher.docHintAdjustment(documentTitle: $0.documentTitle, hint: reference.docHint) }
        if reference.docHint != nil, adjustments.allSatisfy({ $0 < 0 }) { return [] }

        let queries = searchQueries(for: reference)
        let options = SearchOptions(matchCase: false, wholeWord: reference.quotedTitle == nil, smartSearch: true)
        var found: [ReferenceCandidate] = []
        for (vm, adjustment) in zip(viewModels, adjustments) {
            var perDocument: [ReferenceCandidate] = []
            var pages: [Int: HitPage] = [:]
            for query in queries {
                let hits = await vm.searchWholeDocument(query, options: options)
                if Task.isCancelled { return [] }
                for hit in hits.prefix(80) {
                    if let candidate = hitCandidate(hit, in: vm, for: reference, adjustment: adjustment, pages: &pages) {
                        perDocument.append(candidate)
                    }
                }
            }
            found += perDocument.sorted { $0.score > $1.score }.prefix(3)
        }
        return rank(found)
    }

    /// The current document's own outline match for `reference`, when that is where it points:
    /// it names no other document, and no other tab's outline has a confident match.
    public static func sameDocumentTarget(for reference: ParsedReference, in viewModel: PDFViewerViewModel, others: [PDFViewerViewModel]) -> [ReferenceCandidate]? {
        guard reference.docHint == nil, !isConfident(outlineCandidates(for: reference, in: others)) else { return nil }
        let own = outlineCandidates(for: reference, in: [viewModel])
        return isConfident(own) ? own : nil
    }

    /// Whether the best candidate is a clear match. Only rivals in its own document count: the
    /// same heading in another tab (another draft, or an amendment repeating the clause) is
    /// another place to look, not doubt about which heading is meant.
    public static func isConfident(_ ranked: [ReferenceCandidate]) -> Bool {
        guard let best = ranked.first else { return false }
        return CrossDocReferenceMatcher.isConfident(ranked.filter { $0.viewModel === best.viewModel }.map(\.score))
    }

    // MARK: Private

    private static func rank(_ candidates: [ReferenceCandidate]) -> [ReferenceCandidate] {
        CrossDocReferenceMatcher.rank(candidates, score: \.score) { a, b in
            a.viewModel === b.viewModel && a.target.targetPage == b.target.targetPage
                && abs((a.target.targetPoint?.y ?? 0) - (b.target.targetPoint?.y ?? 0)) < 40
        }
    }

    nonisolated static func searchQueries(for reference: ParsedReference) -> [String] {
        if let quoted = reference.quotedTitle { return [quoted] }
        if reference.label.isEmpty { return [reference.identifier] }
        var queries = ["\(reference.label) \(reference.identifier)"]
        if reference.label == "§" { queries = ["§\(reference.identifier)", "§ \(reference.identifier)"] }
        if !reference.needsLabelToMatch { queries.append(reference.identifier) }
        return queries
    }

    private static func outlineTarget(_ node: PDFOutlineNode, in doc: PDFDocumentCore) -> SnapshotTarget? {
        if let uri = node.uri, let dest = doc.resolveLinkDestination(uri: uri) {
            return SnapshotTarget(label: node.title, targetPage: dest.page, targetPoint: dest.point, uri: uri)
        }
        guard let page = node.targetPage, page >= 0, page < doc.pageCount else { return nil }
        return SnapshotTarget(label: node.title, targetPage: page, uri: node.uri)
    }

    /// A hit's page text and body font size, loaded once however many hits share the page.
    private typealias HitPage = (page: StructuredPage, bodySize: Float)

    private static func hitCandidate(_ hit: SearchResult, in vm: PDFViewerViewModel, for reference: ParsedReference, adjustment: Int, pages: inout [Int: HitPage]) -> ReferenceCandidate? {
        guard let doc = vm.document, let quad = hit.highlightQuads.first else { return nil }
        if pages[hit.pageIndex] == nil, let page = vm.pageStructuredData[hit.pageIndex] ?? doc.loadStructuredPage(for: hit.pageIndex) {
            pages[hit.pageIndex] = (page, medianCharacterSize(page))
        }
        guard let (page, bodySize) = pages[hit.pageIndex] else { return nil }
        let hitRect = hit.boundingRect
        let center = CGPoint(x: quad.boundingRect.midX, y: quad.boundingRect.midY)
        let lines = page.blocks.lazy.filter { $0.type == .text }.flatMap(\.lines)
        guard let line = lines.first(where: { $0.bbox.insetBy(dx: -1, dy: -1).contains(center) }) else { return nil }

        var prefix = "", suffix = ""
        for ch in line.characters {
            let mid = ch.boundingRect.midX
            if mid < hitRect.minX { prefix.append(ch.char) }
            else if mid > hitRect.maxX { suffix.append(ch.char) }
        }
        let isEmphasised = CrossDocReferenceMatcher.isEmphasised(line, bodySize: bodySize)
        guard let score = CrossDocReferenceMatcher.headingHitScore(prefix: prefix, hit: hit.matchedText, suffix: suffix, isEmphasised: isEmphasised, for: reference) else {
            return nil
        }
        let lineText = line.text.trimmingCharacters(in: .whitespaces)
        let target = SnapshotTarget(
            label: lineText,
            targetPage: hit.pageIndex,
            targetPoint: CGPoint(x: line.bbox.minX, y: line.bbox.minY),
            targetRect: line.bbox
        )
        return ReferenceCandidate(viewModel: vm, documentTitle: vm.documentTitle, heading: lineText, target: target, score: score + adjustment)
    }

    private static func medianCharacterSize(_ page: StructuredPage) -> Float {
        let sizes = page.blocks.lazy.filter { $0.type == .text }.flatMap(\.lines).compactMap { $0.characters.first?.size }.sorted()
        return sizes.isEmpty ? 0 : sizes[sizes.count / 2]
    }
}
