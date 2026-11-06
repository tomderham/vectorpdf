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
import Synchronization
import MuPDFBridge

// Compares the text of two documents (Compare Documents). Each document is read as one stream of
// words in reading order, so page breaks don't matter: text that moves ten pages because of an
// insertion before it still matches. The streams are aligned with a patience diff (words that
// occur once in each, in the same order, become anchors), with a Myers diff in the gaps between.
// What comes out is the changes, for highlighting, and the matched positions, for scrolling one
// document to follow the other.

/// What a comparison treats as the same word.
public struct CompareOptions: Sendable, Equatable {
    public var ignoresCase: Bool
    public var ignoresPunctuation: Bool

    public init(ignoresCase: Bool = false, ignoresPunctuation: Bool = false) {
        self.ignoresCase = ignoresCase
        self.ignoresPunctuation = ignoresPunctuation
    }

    /// The form of `word` that's compared; empty for a word these options leave out entirely.
    /// Typographic quotes and dashes always count as their plain forms, and compatibility
    /// characters (ligatures, full-width forms) as what they stand for.
    func key(for word: String) -> String {
        var key = word.precomposedStringWithCompatibilityMapping
        if key.unicodeScalars.contains(where: { Self.plainForms[$0] != nil }) {
            key = String(String.UnicodeScalarView(key.unicodeScalars.map { Self.plainForms[$0] ?? $0 }))
        }
        if ignoresPunctuation {
            key.unicodeScalars.removeAll { CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0) }
        }
        if ignoresCase {
            key = key.lowercased()
        }
        return key
    }

    private static let plainForms: [Unicode.Scalar: Unicode.Scalar] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{2032}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{2033}": "\"",
        "\u{2010}": "-", "\u{2011}": "-", "\u{2012}": "-", "\u{2013}": "-", "\u{2212}": "-",
    ]
}

/// A word of a compared document.
public struct CompareWord: Sendable, Equatable {
    /// As it appears in the document.
    public let text: String
    public let pageIndex: Int
    /// Its box on the page, in page coordinates; two for a word hyphenated across lines.
    public let rects: [CGRect]
    /// Which line it's on, counted through the document, so highlights for neighbouring words on
    /// one line merge into one.
    public let line: Int

    public init(text: String, pageIndex: Int, rects: [CGRect], line: Int) {
        self.text = text
        self.pageIndex = pageIndex
        self.rects = rects
        self.line = line
    }
}

/// A document's text as compared: its words in reading order, without running headers, footers,
/// page numbers or margin line numbers.
public struct ComparedText: Sendable {
    public let words: [CompareWord]
    public let pageCount: Int
    /// Pages with no text at all, such as scans without OCR, where the comparison can't follow.
    public let pagesWithoutText: Int

    public init(words: [CompareWord], pageCount: Int, pagesWithoutText: Int = 0) {
        self.words = words
        self.pageCount = pageCount
        self.pagesWithoutText = pagesWithoutText
    }
}

/// One of the two documents compared.
public enum CompareSide: Sendable, Equatable {
    case original
    case revised

    public var other: CompareSide { self == .original ? .revised : .original }
}

/// A run of words that differs between the documents: deleted from the original, inserted in
/// the revision, or replaced (both).
public struct CompareChange: Sendable, Equatable {
    public let original: Range<Int>
    public let revised: Range<Int>

    public init(original: Range<Int>, revised: Range<Int>) {
        self.original = original
        self.revised = revised
    }

    public func words(on side: CompareSide) -> Range<Int> {
        side == .original ? original : revised
    }
}

/// A place on a page: the page and a height on it, in page coordinates.
public struct ComparePoint: Sendable, Equatable {
    public let pageIndex: Int
    public let y: CGFloat

    public init(pageIndex: Int, y: CGFloat) {
        self.pageIndex = pageIndex
        self.y = y
    }
}

/// A line of text at the same place in both documents.
public struct CompareAnchor: Sendable, Equatable {
    public let original: ComparePoint
    public let revised: ComparePoint

    public init(original: ComparePoint, revised: ComparePoint) {
        self.original = original
        self.revised = revised
    }

    public func point(on side: CompareSide) -> ComparePoint {
        side == .original ? original : revised
    }
}

/// The result of comparing two documents' text.
public struct DocumentComparison: Sendable {
    public let original: ComparedText
    public let revised: ComparedText
    /// In document order.
    public let changes: [CompareChange]
    /// The matched lines, in the original's reading order.
    public let anchors: [CompareAnchor]
    /// Words common to both, as a share of the longer document's words: 1 for the same text.
    public let similarity: Double

    public func text(on side: CompareSide) -> ComparedText {
        side == .original ? original : revised
    }

    /// Compares two documents' words.
    public init(original: ComparedText, revised: ComparedText, options: CompareOptions = CompareOptions()) {
        self.original = original
        self.revised = revised

        // Each word as a number, the same for words compared as equal. Words the options leave
        // out (punctuation, with ignoresPunctuation) aren't compared: they are part of whatever
        // change is around them, or of nothing.
        var ids: [String: Int32] = [:]
        func tokens(_ words: [CompareWord]) -> (tokens: [Int32], wordIndex: [Int]) {
            var tokens: [Int32] = []
            var wordIndex: [Int] = []
            tokens.reserveCapacity(words.count)
            wordIndex.reserveCapacity(words.count)
            for (index, word) in words.enumerated() {
                let key = options.key(for: word.text)
                guard !key.isEmpty else { continue }
                let id: Int32
                if let known = ids[key] {
                    id = known
                } else {
                    id = Int32(ids.count)
                    ids[key] = id
                }
                tokens.append(id)
                wordIndex.append(index)
            }
            return (tokens, wordIndex)
        }
        let a = tokens(original.words)
        let b = tokens(revised.words)
        let tokenMatches = TextDiff.matches(a.tokens, b.tokens)
        let matches = tokenMatches.map { (a.wordIndex[$0.0], b.wordIndex[$0.1]) }

        let changes = Self.changes(from: matches, originalCount: original.words.count, revisedCount: revised.words.count, isComparedOriginal: Set(a.wordIndex), isComparedRevised: Set(b.wordIndex))
        self.changes = changes.map { Self.slidToLineStart($0, original: original.words, revised: revised.words, options: options) }
        self.anchors = Self.anchors(from: matches, original: original.words, revised: revised.words)
        let longer = max(a.tokens.count, b.tokens.count)
        self.similarity = longer == 0 ? 1 : Double(tokenMatches.count) / Double(longer)
    }

    /// The runs between matched words. A word left out of the comparison (by the options) is part
    /// of the change it's inside, and of no change otherwise. Two changes with only one or two
    /// words in common between them are one change, which reads better than a highlight broken
    /// by a "the" or an "of".
    private static func changes(from matches: [(Int, Int)], originalCount: Int, revisedCount: Int, isComparedOriginal: Set<Int>, isComparedRevised: Set<Int>) -> [CompareChange] {
        var raw: [CompareChange] = []
        var equalAfter: [Int] = []
        var previous = (-1, -1)
        var equalRun = 0
        func addGap(to next: (Int, Int)) {
            var original = (previous.0 + 1)..<next.0
            var revised = (previous.1 + 1)..<next.1
            // Trim words that weren't compared off the ends, so a change doesn't take in the
            // punctuation around it.
            while let first = original.first, !isComparedOriginal.contains(first) { original = (first + 1)..<original.upperBound }
            while let last = original.last, !isComparedOriginal.contains(last) { original = original.lowerBound..<last }
            while let first = revised.first, !isComparedRevised.contains(first) { revised = (first + 1)..<revised.upperBound }
            while let last = revised.last, !isComparedRevised.contains(last) { revised = revised.lowerBound..<last }
            guard !original.isEmpty || !revised.isEmpty else { return }
            if !raw.isEmpty { equalAfter.append(equalRun) }
            raw.append(CompareChange(original: original, revised: revised))
            equalRun = 0
        }
        for match in matches {
            if match.0 > previous.0 + 1 || match.1 > previous.1 + 1 {
                addGap(to: match)
            }
            equalRun += 1
            previous = match
        }
        addGap(to: (originalCount, revisedCount))

        // Merge changes separated by a short equal run. Ranges keep their place even when empty,
        // so the merged change runs from the first's start to the second's end on each side.
        var merged: [CompareChange] = []
        for (index, change) in raw.enumerated() {
            if let last = merged.last, index > 0, equalAfter[index - 1] <= 2 {
                merged[merged.count - 1] = CompareChange(original: last.original.lowerBound..<change.original.upperBound,
                                                         revised: last.revised.lowerBound..<change.revised.upperBound)
            } else {
                merged.append(change)
            }
        }
        return merged
    }

    /// A change on one side only, moved to start at the start of a line where it can be. A run
    /// of words added after a repeated phrase can as well be put before it ("…site. Clause 250:
    /// … to the" or "Clause 250: … to the site."); the one that starts a line reads as what was
    /// added.
    private static func slidToLineStart(_ change: CompareChange, original: [CompareWord], revised: [CompareWord], options: CompareOptions) -> CompareChange {
        guard change.original.isEmpty != change.revised.isEmpty else { return change }
        let side: CompareSide = change.original.isEmpty ? .revised : .original
        let words = side == .original ? original : revised
        let range = change.words(on: side)
        func startsLine(_ index: Int) -> Bool {
            index == 0 || words[index - 1].line != words[index].line
        }
        guard !startsLine(range.lowerBound) else { return change }
        func same(_ i: Int, _ j: Int) -> Bool {
            let key = options.key(for: words[i].text)
            return !key.isEmpty && key == options.key(for: words[j].text)
        }
        // Back while the word before equals the change's last word, then forward while its first
        // equals the word after it; at most a line's worth each way.
        var shift = 0
        var best: Int?
        while shift > -range.count, range.lowerBound + shift > 0, -shift < 40,
              same(range.lowerBound + shift - 1, range.upperBound + shift - 1) {
            shift -= 1
            if startsLine(range.lowerBound + shift) { best = shift; break }
        }
        if best == nil {
            shift = 0
            while shift < range.count, range.upperBound + shift < words.count, shift < 40,
                  same(range.lowerBound + shift, range.upperBound + shift) {
                shift += 1
                if startsLine(range.lowerBound + shift) { best = shift; break }
            }
        }
        guard let best else { return change }
        let moved = (range.lowerBound + best)..<(range.upperBound + best)
        let other = change.words(on: side.other)
        let otherMoved = (other.lowerBound + best)..<(other.lowerBound + best)
        return side == .original ? CompareChange(original: moved, revised: otherMoved) : CompareChange(original: otherMoved, revised: moved)
    }

    /// One anchor per line: the first matched word of each line, in either document, plus the
    /// last matched word, so scrolling follows to the end.
    private static func anchors(from matches: [(Int, Int)], original: [CompareWord], revised: [CompareWord]) -> [CompareAnchor] {
        var anchors: [CompareAnchor] = []
        var lastLines = (-1, -1)
        func anchor(_ match: (Int, Int)) -> CompareAnchor {
            let a = original[match.0], b = revised[match.1]
            return CompareAnchor(original: ComparePoint(pageIndex: a.pageIndex, y: a.rects.first?.midY ?? 0),
                                 revised: ComparePoint(pageIndex: b.pageIndex, y: b.rects.first?.midY ?? 0))
        }
        for match in matches {
            let lines = (original[match.0].line, revised[match.1].line)
            if lines.0 != lastLines.0 && lines.1 != lastLines.1 {
                anchors.append(anchor(match))
            }
            lastLines = lines
        }
        if let last = matches.last, anchors.last != anchor(last) {
            anchors.append(anchor(last))
        }
        return anchors
    }

    /// The boxes to highlight on `side`, by page: each change's words there (of all the changes,
    /// or just `changes`), a box per line.
    public func highlights(on side: CompareSide, for changes: [CompareChange]? = nil) -> [Int: [CGRect]] {
        let words = text(on: side).words
        var result: [Int: [CGRect]] = [:]
        for change in changes ?? self.changes {
            var current: (page: Int, line: Int, rect: CGRect)?
            func flush() {
                if let current { result[current.page, default: []].append(current.rect) }
                current = nil
            }
            for index in change.words(on: side) {
                let word = words[index]
                for (part, rect) in word.rects.enumerated() {
                    // A hyphenated word's second part is on the next line.
                    let line = word.line + part
                    if let open = current, open.page == word.pageIndex, open.line == line {
                        current = (open.page, line, open.rect.union(rect))
                    } else {
                        flush()
                        current = (word.pageIndex, line, rect)
                    }
                }
            }
            flush()
        }
        return result
    }

    /// Where text is missing on `side` for a change with no words there: just after the last
    /// word before it, or if it's at the start, just before the first word after it. Last as the
    /// page shows it, not in reading order: a PDF can keep text such as a link's for the end of
    /// the page, so of the few words before the gap on that page, the lowest and furthest right.
    func gapPosition(at position: Int, on side: CompareSide) -> (pageIndex: Int, rect: CGRect, isAfter: Bool)? {
        let words = text(on: side).words
        if position > 0 {
            let page = words[position - 1].pageIndex
            let candidates = (max(0, position - 30)..<position).filter { words[$0].pageIndex == page }
            func isBefore(_ a: CGRect, _ b: CGRect) -> Bool {
                let sameLine = abs(a.maxY - b.maxY) <= min(a.height, b.height) / 2
                return sameLine ? a.maxX < b.maxX : a.maxY < b.maxY
            }
            let rects: [CGRect] = candidates.compactMap { words[$0].rects.last }
            let last = rects.max(by: isBefore)
            if let last { return (page, last, true) }
        }
        if position < words.count, let first = words[position].rects.first {
            return (words[position].pageIndex, first, false)
        }
        return nil
    }

    /// Where text is missing on `side`: for each change with no words on this side, a thin box
    /// where the other side's text would be (see `gapPosition`), by page.
    public func gapMarkers(on side: CompareSide) -> [Int: [CGRect]] {
        var result: [Int: [CGRect]] = [:]
        for change in changes where change.words(on: side).isEmpty {
            guard let gap = gapPosition(at: change.words(on: side).lowerBound, on: side) else { continue }
            let x = gap.isAfter ? gap.rect.maxX + 1 : gap.rect.minX - 3
            result[gap.pageIndex, default: []].append(CGRect(x: x, y: gap.rect.minY, width: 2, height: gap.rect.height))
        }
        return result
    }

    /// Where `change` is on `side`: its first word's page and box, or for a change with no words
    /// there, where the missing text would be.
    public func location(of change: CompareChange, on side: CompareSide) -> (pageIndex: Int, rect: CGRect)? {
        let words = text(on: side).words
        let range = change.words(on: side)
        if let first = range.first, let rect = words[first].rects.first {
            let sameLine = range.prefix { words[$0].line == words[first].line && words[$0].pageIndex == words[first].pageIndex }
            let union = sameLine.compactMap { words[$0].rects.first }.reduce(rect) { $0.union($1) }
            return (words[first].pageIndex, union)
        }
        return gapPosition(at: range.lowerBound, on: side).map { ($0.pageIndex, $0.rect) }
    }
}

// MARK: - Following one document with the other

/// Maps a position in one compared document to the matching position in the other, for scrolling
/// them together. Positions are vertical offsets in each document's own layout, as the caller
/// lays the pages out; the map is built from the comparison's anchors and is always increasing,
/// so scrolling one way never moves the other back.
public struct CompareScrollMap: Sendable {
    /// (original offset, revised offset), increasing in both.
    public let points: [(CGFloat, CGFloat)]

    /// `offset(side, point)` is the point's vertical offset in that side's layout.
    public init(anchors: [CompareAnchor], offset: (CompareSide, ComparePoint) -> CGFloat) {
        let mapped = anchors.map { (offset(.original, $0.original), offset(.revised, $0.revised)) }
        self.init(points: mapped)
    }

    /// Keeps the longest run of `points` increasing in both offsets: an anchor out of step (a
    /// second column, a moved paragraph) would make scrolling jump back and forth.
    public init(points unsorted: [(CGFloat, CGFloat)]) {
        let points = unsorted.sorted { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
        let keep = TextDiff.longestIncreasingSubsequence(points.map(\.1), strictly: false)
        var result: [(CGFloat, CGFloat)] = []
        for index in keep {
            let point = points[index]
            // Equal offsets on one side would make the map a step; keep the first.
            if let last = result.last, point.0 <= last.0 || point.1 < last.1 { continue }
            result.append(point)
        }
        self.points = result
    }

    /// The offset on `side.other` matching `offset` on `side`: between the anchors either side of
    /// it, in proportion; before the first anchor or after the last, offset by the same amount.
    /// Through text only `side` has, the other side holds still at the start of the gap until
    /// the text after it, so the two documents meet again where their text does.
    public func offset(_ offset: CGFloat, from side: CompareSide) -> CGFloat {
        guard !points.isEmpty else { return offset }
        let from: (Int) -> CGFloat = side == .original ? { points[$0].0 } : { points[$0].1 }
        let to: (Int) -> CGFloat = side == .original ? { points[$0].1 } : { points[$0].0 }
        // The first anchor past `offset`.
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if from(mid) <= offset { low = mid + 1 } else { high = mid }
        }
        if low == 0 { return to(0) - (from(0) - offset) }
        if low == points.count { return to(points.count - 1) + (offset - from(points.count - 1)) }
        let before = low - 1
        let fromSpan = from(low) - from(before)
        let toSpan = to(low) - to(before)
        guard fromSpan > 0 else { return to(before) }
        // An anchor every line moves the other side line for line; a long gap between anchors
        // on this side but not the other (an insertion) leaves the other side waiting, and one
        // on the other side only (a deletion) moves it on faster.
        let fraction = (offset - from(before)) / fromSpan
        let gapThreshold: CGFloat = 60
        if fromSpan > toSpan + gapThreshold {
            // Inserted text on this side: the other holds still until the last stretch.
            let lead = fromSpan - toSpan
            let progressed = max(0, offset - from(before) - lead)
            return to(before) + progressed
        }
        return to(before) + fraction * toSpan
    }
}

// MARK: - Diff

/// Diffs two sequences of word numbers. A patience diff picks anchors from the words that occur
/// exactly once in each (or, where there are none, the rarest that occur equally often in each)
/// and recurses into the gaps between them; small gaps get a Myers diff. Large documents with
/// edits spread throughout diff in O(n log n).
enum TextDiff {
    /// The largest number of differences a Myers diff looks for before giving up on a gap and
    /// calling all of it changed. Its memory grows with the square of this.
    static let maxEditDistance = 1000

    /// The pairs of positions that match, increasing in both.
    static func matches(_ a: [Int32], _ b: [Int32]) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        var work: [(Range<Int>, Range<Int>)] = [(0..<a.count, 0..<b.count)]
        while var (ra, rb) = work.popLast() {
            // Common prefix and suffix.
            while !ra.isEmpty, !rb.isEmpty, a[ra.lowerBound] == b[rb.lowerBound] {
                result.append((ra.lowerBound, rb.lowerBound))
                ra = (ra.lowerBound + 1)..<ra.upperBound
                rb = (rb.lowerBound + 1)..<rb.upperBound
            }
            while !ra.isEmpty, !rb.isEmpty, a[ra.upperBound - 1] == b[rb.upperBound - 1] {
                result.append((ra.upperBound - 1, rb.upperBound - 1))
                ra = ra.lowerBound..<(ra.upperBound - 1)
                rb = rb.lowerBound..<(rb.upperBound - 1)
            }
            guard !ra.isEmpty, !rb.isEmpty else { continue }

            let anchors = patienceAnchors(a, ra, b, rb)
            if anchors.isEmpty {
                result.append(contentsOf: myers(a, ra, b, rb) ?? [])
                continue
            }
            var previous = (ra.lowerBound, rb.lowerBound)
            for anchor in anchors {
                result.append(anchor)
                if anchor.0 > previous.0 || anchor.1 > previous.1 {
                    work.append((previous.0..<anchor.0, previous.1..<anchor.1))
                }
                previous = (anchor.0 + 1, anchor.1 + 1)
            }
            if previous.0 < ra.upperBound || previous.1 < rb.upperBound {
                work.append((previous.0..<ra.upperBound, previous.1..<rb.upperBound))
            }
        }
        result.sort { $0.0 < $1.0 }
        return result
    }

    /// Anchors for the gap between `ra` and `rb`: the longest increasing run of the runs of three
    /// words that occur once in each range; failing that, of single words that do; failing that,
    /// of the rarest words occurring equally often in each (up to eight times), paired in order.
    /// Runs of words come first because a single word can be unique in both and still be two
    /// different places: "Clause 40:" in one and "Added 40:" in the other.
    private static func patienceAnchors(_ a: [Int32], _ ra: Range<Int>, _ b: [Int32], _ rb: Range<Int>) -> [(Int, Int)] {
        if ra.count >= 3, rb.count >= 3 {
            let anchors = anchors(a, ra, b, rb, length: 3, maxCount: 1)
            if !anchors.isEmpty { return anchors }
        }
        return anchors(a, ra, b, rb, length: 1, maxCount: 8)
    }

    /// The longest increasing run of pairs of `length`-word runs occurring equally often in each
    /// range, the rarest such (at most `maxCount` times) only, the n-th in a paired with the n-th
    /// in b.
    private static func anchors(_ a: [Int32], _ ra: Range<Int>, _ b: [Int32], _ rb: Range<Int>, length: Int, maxCount: Int) -> [(Int, Int)] {
        func key(_ tokens: [Int32], _ i: Int) -> Int64 {
            guard length > 1 else { return Int64(tokens[i]) }
            var hasher = Hasher()
            for t in tokens[i..<(i + length)] { hasher.combine(t) }
            return Int64(hasher.finalize())
        }
        let startsA = ra.lowerBound...(ra.upperBound - length)
        let startsB = rb.lowerBound...(rb.upperBound - length)
        struct Count { var a = 0, b = 0 }
        var counts: [Int64: Count] = [:]
        counts.reserveCapacity(min(ra.count, 1 << 16))
        var keysA: [Int64] = []
        keysA.reserveCapacity(startsA.count)
        for i in startsA {
            let k = key(a, i)
            keysA.append(k)
            counts[k, default: Count()].a += 1
        }
        var keysB: [Int64] = []
        keysB.reserveCapacity(startsB.count)
        for j in startsB {
            let k = key(b, j)
            keysB.append(k)
            if counts[k] != nil { counts[k]!.b += 1 }
        }
        var rarest = Int.max
        for count in counts.values where count.a == count.b && count.a < rarest {
            rarest = count.a
            if rarest == 1 { break }
        }
        guard rarest <= maxCount else { return [] }
        let chosen = Set(counts.compactMap { $0.value.a == rarest && $0.value.b == rarest ? $0.key : nil })

        var positionsInA: [Int64: [Int]] = [:]
        for (offset, k) in keysA.enumerated() where chosen.contains(k) {
            positionsInA[k, default: []].append(startsA.lowerBound + offset)
        }
        var seenInB: [Int64: Int] = [:]
        var pairs: [(Int, Int)] = []
        for (offset, k) in keysB.enumerated() where chosen.contains(k) {
            let j = startsB.lowerBound + offset
            let n = seenInB[k, default: 0]
            seenInB[k] = n + 1
            let i = positionsInA[k]![n]
            // A hash collision isn't a match.
            guard length == 1 || a[i..<(i + length)].elementsEqual(b[j..<(j + length)]) else { continue }
            pairs.append((i, j))
        }
        pairs.sort { $0.0 < $1.0 }
        return longestIncreasingSubsequence(pairs.map { CGFloat($0.1) }, strictly: true).map { pairs[$0] }
    }

    /// The indices of a longest increasing subsequence of `values` (patience sorting).
    static func longestIncreasingSubsequence(_ values: [CGFloat], strictly: Bool) -> [Int] {
        var tails: [Int] = []            // index of the smallest tail of each length
        var predecessor = [Int](repeating: -1, count: values.count)
        for (index, value) in values.enumerated() {
            var low = 0, high = tails.count
            while low < high {
                let mid = (low + high) / 2
                let tail = values[tails[mid]]
                if strictly ? tail < value : tail <= value { low = mid + 1 } else { high = mid }
            }
            if low > 0 { predecessor[index] = tails[low - 1] }
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        var result: [Int] = []
        var index = tails.last ?? -1
        while index >= 0 {
            result.append(index)
            index = predecessor[index]
        }
        return result.reversed()
    }

    /// The matching pairs of a shortest edit script between the ranges, or nil if it needs more
    /// than `maxEditDistance` edits.
    static func myers(_ a: [Int32], _ ra: Range<Int>, _ b: [Int32], _ rb: Range<Int>, maxEditDistance: Int = maxEditDistance) -> [(Int, Int)]? {
        let n = ra.count, m = rb.count
        let maxD = min(n + m, maxEditDistance)
        let offset = maxD + 1
        var v = [Int](repeating: 0, count: 2 * maxD + 3)
        // The furthest x on each diagonal -d...d before step d, for backtracking.
        var trace: [[Int]] = []
        var found: Int?
        search: for d in 0...maxD {
            trace.append(Array(v[(offset - d)...(offset + d)]))
            for k in stride(from: -d, through: d, by: 2) {
                var x = (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) ? v[offset + k + 1] : v[offset + k - 1] + 1
                var y = x - k
                while x < n, y < m, a[ra.lowerBound + x] == b[rb.lowerBound + y] {
                    x += 1
                    y += 1
                }
                v[offset + k] = x
                if x >= n && y >= m {
                    found = d
                    break search
                }
            }
        }
        guard let distance = found else { return nil }

        var matches: [(Int, Int)] = []
        var x = n, y = m
        for d in stride(from: distance, to: 0, by: -1) {
            let row = trace[d]          // v before step d, diagonals -d...d
            func at(_ k: Int) -> Int { row[k + d] }
            let k = x - y
            let previousK = (k == -d || (k != d && at(k - 1) < at(k + 1))) ? k + 1 : k - 1
            let previousX = at(previousK)
            let previousY = previousX - previousK
            // The snake after the edit.
            let startX = previousK == k + 1 ? previousX : previousX + 1
            let startY = startX - k
            while x > startX && y > startY {
                x -= 1
                y -= 1
                matches.append((ra.lowerBound + x, rb.lowerBound + y))
            }
            x = previousX
            y = previousY
        }
        while x > 0 && y > 0 {
            x -= 1
            y -= 1
            matches.append((ra.lowerBound + x, rb.lowerBound + y))
        }
        return matches.reversed()
    }
}

// MARK: - Reading a document's words

extension ComparedText {
    /// A line of a page, with its words.
    struct Line {
        let text: String
        let bbox: CGRect
        var words: [(text: String, rect: CGRect)]
        /// Ends in a hyphen that splits a word across to the next line.
        let joinsNext: Bool
    }

    /// The lines of a page's text in reading order, without margin line numbers, each split
    /// into words.
    static func lines(of page: StructuredPage) -> [Line] {
        let textBlocks = page.blocks.filter { $0.type == .text && !$0.lines.isEmpty }
        let all = textBlocks.flatMap(\.lines)
        let isLineNumber = SpatialTextSelector.lineNumberTest(for: all)
        let body = all.filter { !isLineNumber($0) }
        // OCR text is held upright on a skewed scan; its boxes go back onto the page.
        let transform = page.pageTransform
        return body.enumerated().map { index, line in
            var words: [(String, CGRect)] = []
            var current = ""
            var rect = CGRect.null
            for character in line.characters {
                if character.char.isWhitespace {
                    if !current.isEmpty { words.append((current, rect)) }
                    current = ""
                    rect = .null
                } else {
                    current.append(character.char)
                    rect = rect.union(transform.isIdentity ? character.boundingRect : character.boundingRect.applying(transform))
                }
            }
            if !current.isEmpty { words.append((current, rect)) }
            let next = index + 1 < body.count ? body[index + 1].text : ""
            return Line(text: line.text, bbox: line.bbox, words: words, joinsNext: LineJoin(line.text, next) == .wordBreak)
        }
    }

    /// The share of pages a line must repeat on, at the same place, to be a running header or
    /// footer.
    static let runningLineShare = 0.4

    /// The share of the page's height, at the top and the bottom, a running header or footer can
    /// be in. Footers sit higher than headers sit low: an RFC's is 13% up from the bottom.
    static let runningLineBand = 0.15

    /// The lines at the top and bottom edges of a page set apart from the body: from each edge,
    /// the lines (in the band) up to the first gap of more than `separation` line heights. Body
    /// text runs on at even spacing, so a page that starts or ends with body text has none.
    static func edgeLines(_ lines: [Line], bounds: CGRect, separation: CGFloat = 1.8) -> Set<Int> {
        let band = bounds.height * runningLineBand
        let order = lines.indices.sorted { lines[$0].bbox.midY < lines[$1].bbox.midY }
        var result = Set<Int>()
        func walk(_ order: [Int], isInBand: (CGRect) -> Bool) {
            var cluster: [Int] = []
            for index in order {
                let box = lines[index].bbox
                if let last = cluster.last {
                    let previous = lines[last].bbox
                    let gap = abs(box.midY - previous.midY)
                    let height = max(1, min(box.height, previous.height))
                    // Side by side on one row (a header's left, middle and right parts).
                    if gap < height / 2 {
                        cluster.append(index)
                        continue
                    }
                    if gap > height * separation {
                        result.formUnion(cluster)
                        return
                    }
                }
                guard isInBand(box) else { return }
                cluster.append(index)
            }
        }
        walk(order) { $0.midY < bounds.minY + band }
        walk(order.reversed()) { $0.midY > bounds.maxY - band }
        return result
    }

    /// Running headers and footers: lines set apart at the top or bottom of the page (see
    /// `edgeLines`) whose text, with its numbers taken out, repeats at the same height on at
    /// least `runningLineShare` of the pages (and at least three). Page numbers are among them.
    /// They'd otherwise anchor the text around them to the wrong pages, and show up as changes
    /// wherever the pages shift.
    static func runningLines(pages: [(bounds: CGRect, lines: [Line])]) -> [Set<Int>] {
        let edges = pages.map { edgeLines($0.lines, bounds: $0.bounds) }
        func key(_ line: Line, bounds: CGRect) -> String {
            let text = line.text.lowercased()
                .replacingOccurrences(of: "\\b([0-9]+|[ivxlc]+)\\b", with: "#", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            // To within a few points, so a line repeated at a different height isn't one.
            let height = Int(((line.bbox.midY - bounds.minY) / 4).rounded())
            return "\(height):" + text
        }
        var pagesWithKey: [String: Set<Int>] = [:]
        for (pageIndex, page) in pages.enumerated() {
            for index in edges[pageIndex] {
                pagesWithKey[key(page.lines[index], bounds: page.bounds), default: []].insert(pageIndex)
            }
        }
        let threshold = max(3, Int((Double(pages.count) * runningLineShare).rounded(.up)))
        let running = Set(pagesWithKey.filter { $0.value.count >= threshold }.keys)
        return pages.enumerated().map { pageIndex, page in
            Set(edges[pageIndex].filter { running.contains(key(page.lines[$0], bounds: page.bounds)) })
        }
    }

    /// The words of `pages` in order, without running headers and footers, a word hyphenated
    /// across two lines joined into one.
    init(pages: [(bounds: CGRect, lines: [Line])]) {
        let running = Self.runningLines(pages: pages)
        var words: [CompareWord] = []
        var lineNumber = 0
        var pending: (text: String, pageIndex: Int, rect: CGRect, line: Int)?
        var pagesWithoutText = 0
        for (pageIndex, page) in pages.enumerated() {
            if page.lines.isEmpty { pagesWithoutText += 1 }
            for (index, line) in page.lines.enumerated() where !running[pageIndex].contains(index) {
                lineNumber += 1
                for (wordIndex, word) in line.words.enumerated() {
                    var text = word.text
                    var rects = [word.rect]
                    var line0 = lineNumber
                    var start = pageIndex
                    if wordIndex == 0, let first = pending {
                        text = first.text + text
                        rects = [first.rect, word.rect]
                        line0 = first.line
                        start = first.pageIndex
                        pending = nil
                    }
                    if wordIndex == line.words.count - 1 && line.joinsNext {
                        // Held for the first word of the next line, without its hyphen.
                        let trimmed = text.last.map { "-\u{00AD}\u{2010}".contains($0) } == true ? String(text.dropLast()) : text
                        if rects.count == 1 {
                            pending = (trimmed, start, rects[0], line0)
                            continue
                        }
                    }
                    words.append(CompareWord(text: text, pageIndex: start, rects: rects, line: line0))
                }
            }
        }
        if let pending {
            words.append(CompareWord(text: pending.text, pageIndex: pending.pageIndex, rects: [pending.rect], line: pending.line))
        }
        self.init(words: words, pageCount: pages.count, pagesWithoutText: pagesWithoutText)
    }

    /// Reads the words of the document at `filePath`, several pages at once on contexts of their
    /// own (as search does). Pages with OCR text in `ocrPages` use it. Stops early, returning
    /// nil, if `isCancelled` says so.
    public static func load(filePath: String, password: String? = nil, ocrPages: [Int: PDFOCRPageResult] = [:], workerCount: Int = PDFSearchActor.defaultWorkerCount, isCancelled: @Sendable () -> Bool = { false }) throws -> ComparedText? {
        let first = try SearchResource(filePath: filePath, password: password)
        let pageCount = first.pageCount
        let pages = Mutex([(bounds: CGRect, lines: [Line])](repeating: (.zero, []), count: pageCount))
        let next = Atomic<Int>(0)
        let workers = Mutex<[SearchResource]>([first])

        DispatchQueue.concurrentPerform(iterations: max(1, min(workerCount, pageCount))) { _ in
            let worker: SearchResource
            if let idle = workers.withLock({ $0.popLast() }) {
                worker = idle
            } else if let opened = try? SearchResource(filePath: filePath, password: password) {
                worker = opened
            } else {
                return
            }
            while !isCancelled() {
                let pageIndex = next.add(1, ordering: .relaxed).oldValue
                guard pageIndex < pageCount else { break }
                guard let page = structuredPage(pageIndex, of: worker, ocr: ocrPages[pageIndex]) else {
                    continue
                }
                let lines = lines(of: page)
                pages.withLock { $0[pageIndex] = (page.bounds, lines) }
            }
        }
        guard !isCancelled() else { return nil }
        return ComparedText(pages: pages.withLock { $0 })
    }

    /// Page `pageIndex`'s text, from the worker's copy of the document, or its OCR result if it
    /// has no text of its own.
    private static func structuredPage(_ pageIndex: Int, of worker: SearchResource, ocr: PDFOCRPageResult?) -> StructuredPage? {
        let ctx = worker.ctx
        var pagePtr: FZPage?
        guard mupdf_page_load(ctx, worker.doc, Int32(pageIndex), &pagePtr, nil) == 0, let page = pagePtr else { return nil }
        defer { mupdf_page_drop(ctx, page) }
        var rect = fz_rect()
        mupdf_page_bounds(ctx, page, &rect, nil)
        let bounds = CGRect(x: CGFloat(rect.x0), y: CGFloat(rect.y0), width: CGFloat(rect.x1 - rect.x0), height: CGFloat(rect.y1 - rect.y0))
        guard let structured = try? StructuredPage.load(from: page, pageIndex: pageIndex, ctx: ctx) else { return nil }
        if let ocr, structured.blocks.allSatisfy({ $0.type != .text || $0.lines.isEmpty }) {
            return ocr.structuredPage(bounds: bounds)
        }
        return structured
    }
}
