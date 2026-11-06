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
    /// Leave out numbers that changed only because others were added or removed before them:
    /// in links that go to the same place in both documents (contents entries, cross-references),
    /// and the same change of number at the place they go to (the heading or caption). Which
    /// links go to the same place comes from the documents themselves, not from what the text
    /// looks like: a destination named the same in both (FrameMaker keeps the names from one
    /// revision to the next), or else destinations at text the comparison has matched.
    public var ignoresRenumbering: Bool

    public init(ignoresCase: Bool = false, ignoresPunctuation: Bool = false, ignoresRenumbering: Bool = false) {
        self.ignoresCase = ignoresCase
        self.ignoresPunctuation = ignoresPunctuation
        self.ignoresRenumbering = ignoresRenumbering
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

/// A link within a compared document, such as a contents entry or a cross-reference: the words
/// it covers and where it goes.
public struct CompareLink: Sendable, Equatable {
    /// The words it covers, in the document's words; never empty.
    public let words: Range<Int>
    /// The named destination it goes to, if it goes to one rather than to a page and position.
    public let name: String?
    /// The first word at the place it goes to, if there's text there.
    public let target: Int?
    /// The page it goes to.
    public let targetPage: Int?

    public init(words: Range<Int>, name: String?, target: Int?, targetPage: Int? = nil) {
        self.words = words
        self.name = name
        self.target = target
        self.targetPage = targetPage
    }
}

/// A document's text as compared: its words in reading order, without running headers, footers,
/// page numbers or margin line numbers.
public struct ComparedText: Sendable {
    public let words: [CompareWord]
    public let pageCount: Int
    /// Pages with no text at all, such as scans without OCR, where the comparison can't follow.
    public let pagesWithoutText: Int
    /// Its links to other places in it, in document order, none overlapping.
    public let links: [CompareLink]
    /// By page, the numbers it goes by: its label (by default, its position from 1) and the
    /// numbers in its running header and footer, which can count from a later page.
    public let pageNumbers: [Set<String>]

    public init(words: [CompareWord], pageCount: Int, pagesWithoutText: Int = 0, links: [CompareLink] = [], pageNumbers: [Set<String>] = []) {
        self.words = words
        self.pageCount = pageCount
        self.pagesWithoutText = pagesWithoutText
        self.links = links
        self.pageNumbers = pageNumbers
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
    /// Text that's the same in both, but in another place: in the revision's order. Not among
    /// `changes`, as the text itself didn't change.
    public let moves: [CompareChange]
    /// The matched lines, in the original's reading order.
    public let anchors: [CompareAnchor]
    /// Words common to both, as a share of the longer document's words: 1 for the same text.
    public let similarity: Double
    /// How these options compare words, apart from renumbering, and for each word of the
    /// original the word of the revision it's matched to (or -1), comparing them so: the plain
    /// comparison Ignore Renumbering starts from, kept to start from again. Nil when renumbering
    /// was ignored, or there are no links to follow.
    let plainMatches: (options: CompareOptions, revisedOf: [Int32])?

    public func text(on side: CompareSide) -> ComparedText {
        side == .original ? original : revised
    }

    /// Compares two documents' words. With ignoresRenumbering, `previous`, a comparison of the
    /// same two documents, saves comparing them plainly first if it did (see `plainMatches`).
    public init(original: ComparedText, revised: ComparedText, options: CompareOptions = CompareOptions(), previous: DocumentComparison? = nil) {
        self.original = original
        self.revised = revised

        // Each word as a number, the same for words compared as equal. Words the options leave
        // out (punctuation, with ignoresPunctuation) aren't compared: they are part of whatever
        // change is around them, or of nothing.
        var ids: [String: Int32] = [:]
        func id(_ key: String) -> Int32 {
            if let known = ids[key] { return known }
            let id = Int32(ids.count)
            ids[key] = id
            return id
        }
        // By the word as it appears: far fewer than the words, and finding a word's key takes
        // longer than looking it up. -1 for a word left out.
        var idOfWord: [String: Int32] = [:]
        func tokens(_ text: ComparedText) -> Tokens {
            var result = Tokens()
            result.tokens.reserveCapacity(text.words.count)
            result.wordIndex.reserveCapacity(text.words.count)
            result.compared = [Bool](repeating: false, count: text.words.count)
            for (index, word) in text.words.enumerated() {
                let wordID: Int32
                if let known = idOfWord[word.text] {
                    wordID = known
                } else {
                    let key = options.key(for: word.text)
                    wordID = key.isEmpty ? -1 : id(key)
                    idOfWord[word.text] = wordID
                }
                guard wordID >= 0 else { continue }
                result.tokens.append(wordID)
                result.wordIndex.append(index)
                result.compared[index] = true
            }
            result.link = [Int32](repeating: -1, count: result.tokens.count)
            return result
        }
        // `plain` with each link one token, by its key, where the other document has a link with
        // that key; a link without one is compared as its words, as it would be plainly.
        func collapsingLinks(_ plain: Tokens, _ text: ComparedText, keys: [String], isPaired: (String) -> Bool) -> Tokens {
            var result = Tokens()
            result.tokens.reserveCapacity(plain.tokens.count)
            result.wordIndex.reserveCapacity(plain.tokens.count)
            result.link.reserveCapacity(plain.tokens.count)
            result.compared = plain.compared
            var token = 0
            for (index, link) in text.links.enumerated() where isPaired(keys[index]) {
                while token < plain.tokens.count, plain.wordIndex[token] < link.words.lowerBound {
                    result.tokens.append(plain.tokens[token])
                    result.wordIndex.append(plain.wordIndex[token])
                    result.link.append(-1)
                    token += 1
                }
                result.tokens.append(id("\u{1}link:" + keys[index]))
                result.wordIndex.append(link.words.lowerBound)
                result.link.append(Int32(index))
                for word in link.words { result.compared[word] = false }
                result.compared[link.words.lowerBound] = true
                while token < plain.tokens.count, plain.wordIndex[token] < link.words.upperBound { token += 1 }
            }
            result.tokens.append(contentsOf: plain.tokens[token...])
            result.wordIndex.append(contentsOf: plain.wordIndex[token...])
            result.link.append(contentsOf: repeatElement(-1, count: plain.tokens.count - token))
            return result
        }
        var a = tokens(original)
        var b = tokens(revised)
        let hasLinks = !original.links.isEmpty || !revised.links.isEmpty
        var plainOptions = options
        plainOptions.ignoresRenumbering = false
        // Revised words compared as the original's, by ignoresRenumbering, and as which word.
        var renumbered: [Int: String] = [:]
        if options.ignoresRenumbering, hasLinks {
            let plain: [Int32]
            if let previous = previous?.plainMatches, previous.options == plainOptions, previous.revisedOf.count == original.words.count {
                plain = previous.revisedOf
            } else {
                plain = Self.revisedOf(TextDiff.matches(a.tokens, b.tokens), a, b, count: original.words.count)
            }
            let keys = Self.linkKeys(original: original, revised: revised, plain: plain, a, b, key: options.key(for:))
            func isPaired(_ key: String) -> Bool { keys.links[key].map { !$0.original.isEmpty && !$0.revised.isEmpty } == true }
            a = collapsingLinks(a, original, keys: keys.original, isPaired: isPaired)
            b = collapsingLinks(b, revised, keys: keys.revised, isPaired: isPaired)
            renumbered = Self.renumberTargets(&b, a, original: original, revised: revised, keys: keys, key: options.key(for:), id: { ids[$0] })
        }
        let ordered = TextDiff.matches(a.tokens, b.tokens)
        self.plainMatches = !options.ignoresRenumbering && hasLinks ? (plainOptions, Self.revisedOf(ordered, a, b, count: original.words.count)) : nil
        let (tokenMatches, moved, moves) = Self.findingMoves(Self.slidToLines(ordered, a, b, original: original, revised: revised), a, b, original: original, revised: revised)
        self.moves = moves
        let matches = tokenMatches.map { (a.wordIndex[$0.0], b.wordIndex[$0.1]) }
        // A link's other words are compared with it: those of a link matched are matched, and
        // those of one that isn't are part of the change.
        func withUnmatchedLinks(_ tokens: inout Tokens, _ text: ComparedText, matched: [Int]) {
            var isMatched = [Bool](repeating: false, count: tokens.tokens.count)
            for token in matched { isMatched[token] = true }
            for (token, link) in tokens.link.enumerated() where link >= 0 && !isMatched[token] {
                for word in text.links[Int(link)].words { tokens.compared[word] = true }
            }
        }
        if a.link.contains(where: { $0 >= 0 }) || b.link.contains(where: { $0 >= 0 }) {
            withUnmatchedLinks(&a, original, matched: tokenMatches.map(\.0))
            withUnmatchedLinks(&b, revised, matched: tokenMatches.map(\.1))
        }

        let changes = Self.changes(from: matches, originalCount: original.words.count, revisedCount: revised.words.count, isComparedOriginal: a.compared, isComparedRevised: b.compared, moved: moved)
        self.changes = changes.map { Self.slidToLineStart($0, original: original.words, revised: revised.words, options: options, renumbered: renumbered) }
        self.anchors = Self.anchors(from: matches, original: original.words, revised: revised.words)
        let longer = max(a.tokens.count, b.tokens.count)
        self.similarity = longer == 0 ? 1 : Double(tokenMatches.count) / Double(longer)
    }

    /// A document's words as compared: each a number, the same for words compared as equal.
    struct Tokens {
        var tokens: [Int32] = []
        /// The word each token stands for (a link's first word, for a link).
        var wordIndex: [Int] = []
        /// The link each token stands for, in the document's links; -1 for a word.
        var link: [Int32] = []
        /// By word, whether it's compared: all but those the options leave out, and the words
        /// of a link after its first, while it's one token.
        var compared: [Bool] = []

        /// The first token at or after `word`.
        func token(atOrAfter word: Int) -> Int {
            var low = 0, high = wordIndex.count
            while low < high {
                let mid = (low + high) / 2
                if wordIndex[mid] < word { low = mid + 1 } else { high = mid }
            }
            return low
        }
    }

    /// What each link is compared as, with ignoresRenumbering: where it goes, in a form the same
    /// for two links (one in each document) that go to the same place. That's the name of the
    /// destination, where both documents have one by that name; FrameMaker keeps them from one
    /// revision to the next, unless the text says otherwise (see below). Otherwise it's the text
    /// there, by the plain comparison of the two (`plain`, with links compared as words, by
    /// original word): a destination in the original is paired with the one in the revision that
    /// most of the words just after it (two at least) are matched to words just after. That's the
    /// words, not the first, which can be the number that changed, and can even be matched to the
    /// number of a heading put in before. A link with neither is compared as itself, the same as
    /// no other, and so as its words (see `collapsingLinks`).
    struct LinkKeys {
        var original: [String]
        var revised: [String]
        /// Where links with each key go, in each document (the first word there), and the links.
        var targets: [String: (original: Int, revised: Int)] = [:]
        var links: [String: (original: [Int], revised: [Int])] = [:]
    }

    /// For each word of the original, the word of the revision `matches` matches it to, or -1.
    static func revisedOf(_ matches: [(Int, Int)], _ a: Tokens, _ b: Tokens, count: Int) -> [Int32] {
        var result = [Int32](repeating: -1, count: count)
        for (i, j) in matches { result[a.wordIndex[i]] = Int32(b.wordIndex[j]) }
        return result
    }

    static func linkKeys(original: ComparedText, revised: ComparedText, plain revisedOf: [Int32], _ a: Tokens, _ b: Tokens, key: (String) -> String) -> LinkKeys {
        // Each destination by its first token; in the original, paired with the destination in
        // the revision with most of the words after it matched to words after this one.
        var revisedTargets = Set<Int>()
        for link in revised.links {
            if let target = link.target { revisedTargets.insert(b.token(atOrAfter: target)) }
        }
        var pairedTarget: [Int: Int] = [:]
        var votes: [Int: [Int: Int]] = [:]
        for link in original.links {
            guard let target = link.target else { continue }
            let ta = a.token(atOrAfter: target)
            guard votes[ta] == nil else { continue }
            var count: [Int: Int] = [:]
            for i in ta..<min(ta + 8, a.tokens.count) where revisedOf[a.wordIndex[i]] >= 0 {
                let j = b.token(atOrAfter: Int(revisedOf[a.wordIndex[i]]))
                for tb in max(0, j - 7)...j where revisedTargets.contains(tb) { count[tb, default: 0] += 1 }
            }
            votes[ta] = count
            // More than a stray word in common.
            if let best = count.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }), best.value >= 2 {
                pairedTarget[ta] = best.key
            }
        }

        // A name both documents have, unless the text says it goes to different places in each:
        // a name made from a number (LaTeX's "section.2") goes to another clause once they're
        // renumbered. The text says so when the words after the destination in the original are
        // matched to words after another destination in the revision, more of them than to words
        // after the one by that name. Where the plain comparison has matched little there, the
        // name is taken at its word, and so it is where the links to it read the same in both but
        // for the pages they go to: the same contents entry, moved to another page.
        var linksOfName: [String: (original: [Int], revised: [Int])] = [:]
        for (index, link) in original.links.enumerated() { if let name = link.name { linksOfName[name, default: ([], [])].original.append(index) } }
        for (index, link) in revised.links.enumerated() { if let name = link.name { linksOfName[name, default: ([], [])].revised.append(index) } }
        func readsTheSame(_ name: String) -> Bool {
            guard let links = linksOfName[name] else { return false }
            return links.original.count == links.revised.count && zip(links.original, links.revised).allSatisfy { i, j in
                let linkA = original.links[i], linkB = revised.links[j]
                guard linkA.words.count == linkB.words.count else { return false }
                return zip(linkA.words, linkB.words).allSatisfy { x, y in
                    let wordA = original.words[x].text, wordB = revised.words[y].text
                    if key(wordA) == key(wordB) { return true }
                    guard let pageA = linkA.targetPage, let pageB = linkB.targetPage,
                          pageA < original.pageNumbers.count, pageB < revised.pageNumbers.count else { return false }
                    return original.pageNumbers[pageA].contains(withoutLeader(wordA)) && revised.pageNumbers[pageB].contains(withoutLeader(wordB))
                }
            }
        }
        var targetsOfName: [String: (original: Int?, revised: Int?)] = [:]
        for link in original.links {
            if let name = link.name, let target = link.target { targetsOfName[name, default: (nil, nil)].original = a.token(atOrAfter: target) }
        }
        for link in revised.links {
            if let name = link.name, let target = link.target { targetsOfName[name, default: (nil, nil)].revised = b.token(atOrAfter: target) }
        }
        var names = Set(original.links.compactMap(\.name)).intersection(revised.links.compactMap(\.name))
        for name in names {
            guard let targets = targetsOfName[name], let ta = targets.original, let tb = targets.revised else { continue }
            if let paired = pairedTarget[ta], paired != tb, (votes[ta]?[paired] ?? 0) > (votes[ta]?[tb] ?? 0), !readsTheSame(name) {
                names.remove(name)
            }
        }
        func isNamed(_ link: CompareLink) -> Bool { link.name.map(names.contains) == true }

        var keyOfRevisedTarget: [Int: String] = [:]
        for (ta, tb) in pairedTarget.sorted(by: { $0.key < $1.key }) where keyOfRevisedTarget[tb] == nil {
            keyOfRevisedTarget[tb] = "t:\(ta)"
        }
        var keys = LinkKeys(original: [], revised: [])
        keys.original = original.links.enumerated().map { index, link in
            if isNamed(link), let name = link.name { return "n:" + name }
            if let target = link.target {
                let ta = a.token(atOrAfter: target)
                if let tb = pairedTarget[ta], keyOfRevisedTarget[tb] == "t:\(ta)" { return "t:\(ta)" }
            }
            return "a:\(index)"
        }
        keys.revised = revised.links.enumerated().map { index, link in
            if isNamed(link), let name = link.name { return "n:" + name }
            if let target = link.target, let key = keyOfRevisedTarget[b.token(atOrAfter: target)] { return key }
            return "b:\(index)"
        }
        for (index, key) in keys.original.enumerated() { keys.links[key, default: ([], [])].original.append(index) }
        for (index, key) in keys.revised.enumerated() { keys.links[key, default: ([], [])].revised.append(index) }
        for (key, links) in keys.links {
            guard let a = links.original.first.flatMap({ original.links[$0].target }),
                  let b = links.revised.first.flatMap({ revised.links[$0].target }) else { continue }
            keys.targets[key] = (a, b)
        }
        return keys
    }

    /// With ignoresRenumbering, the numbers at the places links go to (a heading's or a
    /// caption's) that changed as the links' text did, made the same as the original's in `b`:
    /// for links going to one place, the words of their text that differ, word for word, once the
    /// words it starts and ends with alike are set aside ("9-806" for "9-809", from "Figure 9-806
    /// … 1501" and "Figure 9-809 … 1510"). Only words at the same place on the row the
    /// destination is on, on both sides, are changed. Returns, by word, the original's word each
    /// changed one is now compared as.
    static func renumberTargets(_ b: inout Tokens, _ a: Tokens, original: ComparedText, revised: ComparedText, keys: LinkKeys, key: (String) -> String, id: (String) -> Int32?) -> [Int: String] {
        struct Swap: Hashable { let from: Int32, to: Int32 }
        func sameRow(_ x: CompareWord, _ y: CompareWord) -> Bool {
            guard x.pageIndex == y.pageIndex, let r = x.rects.first, let s = y.rects.first else { return false }
            return min(r.maxY, s.maxY) - max(r.minY, s.minY) > min(r.height, s.height) / 2
        }
        var result: [Int: String] = [:]
        // After each link, before the next, a word that differs only as the pages the links go
        // to do: a contents entry whose link takes in its number, or its first row, but not its
        // page number, which can be rows after.
        for links in keys.links.values {
            for (i, j) in zip(links.original, links.revised) {
                let linkA = original.links[i], linkB = revised.links[j]
                guard let pageA = linkA.targetPage, let pageB = linkB.targetPage,
                      pageA < original.pageNumbers.count, pageB < revised.pageNumbers.count else { continue }
                let startA = a.token(atOrAfter: linkA.words.upperBound), startB = b.token(atOrAfter: linkB.words.upperBound)
                let pageOfA = original.words[linkA.words.lowerBound].pageIndex, pageOfB = revised.words[linkB.words.lowerBound].pageIndex
                // Up to the next link, or as far as the longest entry runs.
                for offset in 0..<40 {
                    let x = startA + offset, y = startB + offset
                    guard x < a.tokens.count, y < b.tokens.count, a.link[x] < 0, b.link[y] < 0,
                          original.words[a.wordIndex[x]].pageIndex == pageOfA, revised.words[b.wordIndex[y]].pageIndex == pageOfB else { break }
                    let wordA = Self.withoutLeader(original.words[a.wordIndex[x]].text), wordB = Self.withoutLeader(revised.words[b.wordIndex[y]].text)
                    if a.tokens[x] != b.tokens[y], original.pageNumbers[pageA].contains(wordA), revised.pageNumbers[pageB].contains(wordB) {
                        b.tokens[y] = a.tokens[x]
                        result[b.wordIndex[y]] = key(original.words[a.wordIndex[x]].text)
                    }
                }
            }
        }
        for (linkKey, targets) in keys.targets {
            guard let links = keys.links[linkKey] else { continue }
            // The links in each document in order, paired.
            var swaps = Set<Swap>()
            for (i, j) in zip(links.original, links.revised) {
                let wordsA = original.links[i].words.map { id(key(original.words[$0].text)) }
                let wordsB = revised.links[j].words.map { id(key(revised.words[$0].text)) }
                var start = 0
                while start < min(wordsA.count, wordsB.count), wordsA[start] == wordsB[start] { start += 1 }
                var end = 0
                while end < min(wordsA.count, wordsB.count) - start, wordsA[wordsA.count - 1 - end] == wordsB[wordsB.count - 1 - end] { end += 1 }
                let middleA = wordsA[start..<(wordsA.count - end)], middleB = wordsB[start..<(wordsB.count - end)]
                guard middleA.count == middleB.count else { continue }
                for (x, y) in zip(middleA, middleB) {
                    if let x, let y, x != y { swaps.insert(Swap(from: y, to: x)) }
                }
            }
            guard !swaps.isEmpty else { continue }
            let firstA = a.token(atOrAfter: targets.original), firstB = b.token(atOrAfter: targets.revised)
            guard firstA < a.tokens.count, firstB < b.tokens.count else { continue }
            let rowA = original.words[a.wordIndex[firstA]], rowB = revised.words[b.wordIndex[firstB]]
            for offset in 0..<8 {
                let i = firstA + offset, j = firstB + offset
                guard i < a.tokens.count, j < b.tokens.count, a.link[i] < 0, b.link[j] < 0,
                      sameRow(original.words[a.wordIndex[i]], rowA), sameRow(revised.words[b.wordIndex[j]], rowB) else { break }
                if a.tokens[i] != b.tokens[j], swaps.contains(Swap(from: b.tokens[j], to: a.tokens[i])) {
                    b.tokens[j] = a.tokens[i]
                    result[b.wordIndex[j]] = key(original.words[a.wordIndex[i]].text)
                }
            }
        }
        return result
    }

    /// `word` without the dots leading up to it, as a contents entry's page number can have.
    static func withoutLeader(_ word: String) -> String {
        String(word.drop { ".…·\u{2024}\u{2025}".contains($0) })
    }

    /// The runs between matched words. A word left out of the comparison (by the options) is part
    /// of the change it's inside, and of no change otherwise. Two changes with only one or two
    /// words in common between them are one change, which reads better than a highlight broken
    /// by a "the" or an "of".
    private static func changes(from matches: [(Int, Int)], originalCount: Int, revisedCount: Int, isComparedOriginal: [Bool], isComparedRevised: [Bool], moved: (original: [Bool], revised: [Bool])) -> [CompareChange] {
        var raw: [CompareChange] = []
        var equalAfter: [Int] = []
        var previous = (-1, -1)
        var equalRun = 0
        // Trim words that weren't compared off the ends, so a change doesn't take in the
        // punctuation around it.
        func trimmed(_ range: Range<Int>, _ isCompared: [Bool]) -> Range<Int> {
            var range = range
            while let first = range.first, !isCompared[first] { range = (first + 1)..<range.upperBound }
            while let last = range.last, !isCompared[last] { range = range.lowerBound..<last }
            return range
        }
        // The runs of `range` that didn't move.
        func unmoved(_ range: Range<Int>, _ isMoved: [Bool], _ isCompared: [Bool]) -> [Range<Int>] {
            var result: [Range<Int>] = []
            var start: Int?
            for index in range.lowerBound...range.upperBound {
                if index < range.upperBound, !isMoved[index] {
                    if start == nil { start = index }
                } else if let first = start {
                    let run = trimmed(first..<index, isCompared)
                    if !run.isEmpty { result.append(run) }
                    start = nil
                }
            }
            return result
        }
        func add(_ change: CompareChange, after equal: Int) {
            if !raw.isEmpty { equalAfter.append(equal) }
            raw.append(change)
        }
        func addGap(to next: (Int, Int)) {
            let original = trimmed((previous.0 + 1)..<next.0, isComparedOriginal)
            let revised = trimmed((previous.1 + 1)..<next.1, isComparedRevised)
            guard !original.isEmpty || !revised.isEmpty else { return }
            let isMoved = (moved.original.isEmpty ? false : original.contains { moved.original[$0] })
                || (moved.revised.isEmpty ? false : revised.contains { moved.revised[$0] })
            if !isMoved {
                add(CompareChange(original: original, revised: revised), after: equalRun)
            } else {
                // What's left once text that moved is set aside: each run on its own, taken out or
                // put in, and not merged with the others, which the moved text is between.
                let pieces = unmoved(original, moved.original, isComparedOriginal).map { CompareChange(original: $0, revised: revised.lowerBound..<revised.lowerBound) }
                    + unmoved(revised, moved.revised, isComparedRevised).map { CompareChange(original: original.lowerBound..<original.lowerBound, revised: $0) }
                for (index, piece) in pieces.enumerated() {
                    add(piece, after: index == 0 ? equalRun : Int.max)
                }
                if pieces.isEmpty { return }
            }
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

    /// The fewest words in a row, the same in both documents, that count as text that moved
    /// rather than text taken out in one place and put in at another.
    static let movedRun = 10

    /// The most words in a row a match can be and still be compared again for text that moved.
    static let strayRun = 5

    /// `matches` with each run taken out or put in, on one side only, moved to start a line where
    /// it can (as `slidToLineStart` does for what's shown), so text that moved is cut at the same
    /// place on both sides. Repeated words let a diff end a run in several places equally well:
    /// "… site. Clause 250: … to the" or "Clause 250: … to the site.".
    static func slidToLines(_ matches: [(Int, Int)], _ a: Tokens, _ b: Tokens, original: ComparedText, revised: ComparedText) -> [(Int, Int)] {
        var m = matches
        func startsLine(_ tokens: Tokens, _ text: ComparedText, _ token: Int) -> Bool {
            token == 0 || text.words[tokens.wordIndex[token - 1]].line != text.words[tokens.wordIndex[token]].line
        }
        for p in m.indices.dropFirst() {
            let previous = m[p - 1], next = m[p]
            let gapA = (previous.0 + 1)..<next.0, gapB = (previous.1 + 1)..<next.1
            guard gapA.isEmpty != gapB.isEmpty else { continue }
            // The side with the run, as (token in it, token on the other side) pairs.
            let onA = !gapA.isEmpty
            let gap = onA ? gapA : gapB
            let tokens = onA ? a : b, text = onA ? original : revised
            func side(_ match: (Int, Int)) -> Int { onA ? match.0 : match.1 }
            func other(_ match: (Int, Int)) -> Int { onA ? match.1 : match.0 }
            func make(_ here: Int, _ there: Int) -> (Int, Int) { onA ? (here, there) : (there, here) }
            guard !startsLine(tokens, text, gap.lowerBound) else { continue }
            // Back: while the token before the run equals its last, and is matched just before.
            var shift = 0
            var found: Int?
            while shift < gap.count, shift < 40, p - 1 - shift >= 0 {
                let match = m[p - 1 - shift]
                guard side(match) == gap.lowerBound - 1 - shift, shift == 0 || other(match) == other(m[p - shift]) - 1,
                      tokens.tokens[gap.lowerBound - 1 - shift] == tokens.tokens[gap.upperBound - 1 - shift] else { break }
                shift += 1
                if startsLine(tokens, text, gap.lowerBound - shift) { found = shift; break }
            }
            if let found {
                // The matches the run passes over now match the same words at its far end.
                for k in 1...found {
                    m[p - k] = make(gap.upperBound - k, other(m[p - k]))
                }
                continue
            }
            // Forward: while the token after the run equals its first, and is matched just after.
            shift = 0
            var forward: Int?
            while shift < gap.count, shift < 40, p + shift < m.count {
                let match = m[p + shift]
                guard side(match) == gap.upperBound + shift, shift == 0 || other(match) == other(m[p + shift - 1]) + 1,
                      tokens.tokens[gap.lowerBound + shift] == tokens.tokens[gap.upperBound + shift] else { break }
                shift += 1
                if startsLine(tokens, text, gap.lowerBound + shift) { forward = shift; break }
            }
            guard let forward else { continue }
            for k in 0..<forward {
                m[p + k] = make(gap.lowerBound + k, other(m[p + k]))
            }
        }
        return m.sorted { $0.0 < $1.0 }
    }

    /// Words taken out in one place and put in at another, unchanged: what's left unmatched,
    /// compared again on its own, in runs of `movedRun` words in a row or more in both. The
    /// comparison keeps the documents' order, so a table that comes before a heading in one and
    /// after it in the other (as a page break falls) is matched one way and not the other. Short
    /// runs it matched (fewer than `strayRun`), which text that moved can share with what's
    /// around it, are compared again too, and give way to text that moved. Whether the layout
    /// moved it (a table floating past a page break) or its author did, the PDF doesn't say, so
    /// it's shown as moved, not hidden. Returns the matches left, by word which moved, and each
    /// run that moved.
    static func findingMoves(_ matches: [(Int, Int)], _ a: Tokens, _ b: Tokens, original: ComparedText, revised: ComparedText) -> (matches: [(Int, Int)], moved: (original: [Bool], revised: [Bool]), moves: [CompareChange]) {
        // Matches in short runs: in a row in both, fewer than strayRun of them.
        var isStray = [Bool](repeating: false, count: matches.count)
        var runStart = 0
        for index in stride(from: 1, through: matches.count, by: 1) {
            let continues = index < matches.count && matches[index].0 == matches[index - 1].0 + 1 && matches[index].1 == matches[index - 1].1 + 1
            if !continues {
                if index - runStart < strayRun { for k in runStart..<index { isStray[k] = true } }
                runStart = index
            }
        }
        var leftA = [Bool](repeating: true, count: a.tokens.count)
        var leftB = [Bool](repeating: true, count: b.tokens.count)
        // For a token in a short run, what it's matched to.
        var strayPartner = [Int32](repeating: -1, count: a.tokens.count)
        for (index, (i, j)) in matches.enumerated() {
            if isStray[index] {
                strayPartner[i] = Int32(j)
            } else {
                leftA[i] = false
                leftB[j] = false
            }
        }
        let restA = a.tokens.indices.filter { leftA[$0] }, restB = b.tokens.indices.filter { leftB[$0] }
        guard restA.count >= movedRun, restB.count >= movedRun else { return (matches, ([], []), []) }
        let again = TextDiff.matches(restA.map { a.tokens[$0] }, restB.map { b.tokens[$0] })
        var movedTokenA = [Bool](repeating: false, count: a.tokens.count)
        var movedTokenB = [Bool](repeating: false, count: b.tokens.count)
        var moves: [CompareChange] = []
        func lastWord(_ token: Int, _ tokens: Tokens, _ text: ComparedText) -> Int {
            tokens.link[token] >= 0 ? text.links[Int(tokens.link[token])].words.upperBound - 1 : tokens.wordIndex[token]
        }
        var start = 0
        var found = false
        while start < again.count {
            // A run: in a row among what's left, and in a row in each document's text.
            var end = start + 1
            while end < again.count,
                  restA[again[end].0] == restA[again[end - 1].0] + 1, restB[again[end].1] == restB[again[end - 1].1] + 1 {
                end += 1
            }
            if end - start >= movedRun {
                // Matched where it is in both already: not a move.
                let inPlace = (start..<end).allSatisfy { k in strayPartner[restA[again[k].0]] == Int32(restB[again[k].1]) }
                if !inPlace {
                    for k in start..<end {
                        movedTokenA[restA[again[k].0]] = true
                        movedTokenB[restB[again[k].1]] = true
                    }
                    let firstA = a.wordIndex[restA[again[start].0]], firstB = b.wordIndex[restB[again[start].1]]
                    moves.append(CompareChange(original: firstA..<(lastWord(restA[again[end - 1].0], a, original) + 1),
                                               revised: firstB..<(lastWord(restB[again[end - 1].1], b, revised) + 1)))
                    found = true
                }
            }
            start = end
        }
        guard found else { return (matches, ([], []), []) }
        var movedA = [Bool](repeating: false, count: original.words.count)
        var movedB = [Bool](repeating: false, count: revised.words.count)
        func mark(_ moved: [Bool], _ tokens: Tokens, _ text: ComparedText, into words: inout [Bool]) {
            // Each run of moved tokens, with the words between them (punctuation, a link's).
            var token = 0
            while token < moved.count {
                guard moved[token] else { token += 1; continue }
                var last = token
                while last + 1 < moved.count, moved[last + 1] { last += 1 }
                let end = tokens.link[last] >= 0 ? text.links[Int(tokens.link[last])].words.upperBound - 1 : tokens.wordIndex[last]
                for word in tokens.wordIndex[token]...end { words[word] = true }
                token = last + 1
            }
        }
        mark(movedTokenA, a, original, into: &movedA)
        mark(movedTokenB, b, revised, into: &movedB)
        let kept = matches.filter { !movedTokenA[$0.0] && !movedTokenB[$0.1] }
        return (kept, (movedA, movedB), moves.sorted { $0.revised.lowerBound < $1.revised.lowerBound })
    }

    /// A change on one side only, moved to start at the start of a line where it can be. A run
    /// of words added after a repeated phrase can as well be put before it ("…site. Clause 250:
    /// … to the" or "Clause 250: … to the site."); the one that starts a line reads as what was
    /// added.
    private static func slidToLineStart(_ change: CompareChange, original: [CompareWord], revised: [CompareWord], options: CompareOptions, renumbered: [Int: String]) -> CompareChange {
        guard change.original.isEmpty != change.revised.isEmpty else { return change }
        let side: CompareSide = change.original.isEmpty ? .revised : .original
        let words = side == .original ? original : revised
        let range = change.words(on: side)
        func startsLine(_ index: Int) -> Bool {
            index == 0 || words[index - 1].line != words[index].line
        }
        guard !startsLine(range.lowerBound) else { return change }
        func same(_ i: Int, _ j: Int) -> Bool {
            func key(_ index: Int) -> String {
                (side == .revised ? renumbered[index] : nil) ?? options.key(for: words[index].text)
            }
            let first = key(i)
            return !first.isEmpty && first == key(j)
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
        /// For each word, the link on its page it's in (see `PageLink`), or -1; empty for none.
        var wordLinks: [Int] = []
    }

    /// A link on a page to another place in the document.
    struct PageLink: Sendable {
        let rect: CGRect
        /// What identifies where it goes: two links with the same go to the same place.
        let uri: String
        /// The named destination it goes to, if any.
        let name: String?
        /// Where it goes.
        let target: ComparePoint?
    }

    /// Notes which of `links` each word of `lines` is in: the link its middle is in.
    static func assignLinks(_ links: [PageLink], to lines: inout [Line]) {
        guard !links.isEmpty else { return }
        for index in lines.indices {
            let nearby = links.indices.filter { links[$0].rect.intersects(lines[index].bbox) }
            guard !nearby.isEmpty else { continue }
            lines[index].wordLinks = lines[index].words.map { word in
                let middle = CGPoint(x: word.rect.midX, y: word.rect.midY)
                return nearby.first { links[$0].rect.contains(middle) } ?? -1
            }
        }
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
    /// least `runningLineShare` of the odd pages or of the even pages (and on three at least): a
    /// book's facing pages put them at different heights, or on different sides, so each is on
    /// only half the pages, and less with pages laid out otherwise (landscape tables, the front
    /// matter). Page numbers are among them.
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
        // By key, how many odd and how many even pages it's on (counting from page 1).
        var pagesWithKey: [String: (odd: Set<Int>, even: Set<Int>)] = [:]
        for (pageIndex, page) in pages.enumerated() {
            for index in edges[pageIndex] {
                let key = key(page.lines[index], bounds: page.bounds)
                if pageIndex % 2 == 0 {
                    pagesWithKey[key, default: ([], [])].odd.insert(pageIndex)
                } else {
                    pagesWithKey[key, default: ([], [])].even.insert(pageIndex)
                }
            }
        }
        func threshold(_ count: Int) -> Int { Int((Double(count) * runningLineShare).rounded(.up)) }
        let odd = threshold((pages.count + 1) / 2), even = threshold(pages.count / 2)
        let running = Set(pagesWithKey.filter { key, pages in
            pages.odd.count + pages.even.count >= 3 && (pages.odd.count >= odd || pages.even.count >= even)
        }.keys)
        return pages.enumerated().map { pageIndex, page in
            Set(edges[pageIndex].filter { running.contains(key(page.lines[$0], bounds: page.bounds)) })
        }
    }

    /// The words of `pages` in order, without running headers and footers, a word hyphenated
    /// across two lines joined into one.
    init(pages: [(bounds: CGRect, lines: [Line])], links pageLinks: [[PageLink]] = [], labels: [String]? = nil) {
        let running = Self.runningLines(pages: pages)
        let pageNumbers = pages.indices.map { pageIndex -> Set<String> in
            var numbers: Set<String> = [labels.flatMap { pageIndex < $0.count ? $0[pageIndex] : nil } ?? String(pageIndex + 1)]
            for index in running[pageIndex] {
                for word in pages[pageIndex].lines[index].words where Self.isPageNumber(word.text) {
                    numbers.insert(word.text)
                }
            }
            return numbers
        }
        var words: [CompareWord] = []
        var lineNumber = 0
        var pending: (text: String, pageIndex: Int, rect: CGRect, line: Int, link: PageLink?)?
        var pagesWithoutText = 0
        // Runs of words in links that go to the same place, which become `CompareLink`s once
        // the words their destinations are at are known. A link broken across lines is several.
        var spans: [(words: Range<Int>, link: PageLink)] = []
        func append(_ word: CompareWord, link: PageLink?) {
            if let link {
                if let last = spans.last, last.words.upperBound == words.count, last.link.uri == link.uri {
                    spans[spans.count - 1].words = last.words.lowerBound..<(words.count + 1)
                } else {
                    spans.append((words.count..<(words.count + 1), link))
                }
            }
            words.append(word)
        }
        for (pageIndex, page) in pages.enumerated() {
            if page.lines.isEmpty { pagesWithoutText += 1 }
            let links = pageIndex < pageLinks.count ? pageLinks[pageIndex] : []
            for (index, line) in page.lines.enumerated() where !running[pageIndex].contains(index) {
                lineNumber += 1
                for (wordIndex, word) in line.words.enumerated() {
                    var text = word.text
                    var rects = [word.rect]
                    var line0 = lineNumber
                    var start = pageIndex
                    var link = wordIndex < line.wordLinks.count && line.wordLinks[wordIndex] >= 0 ? links[line.wordLinks[wordIndex]] : nil
                    if wordIndex == 0, let first = pending {
                        text = first.text + text
                        rects = [first.rect, word.rect]
                        line0 = first.line
                        start = first.pageIndex
                        link = first.link
                        pending = nil
                    }
                    if wordIndex == line.words.count - 1 && line.joinsNext {
                        // Held for the first word of the next line, without its hyphen.
                        let trimmed = text.last.map { "-\u{00AD}\u{2010}".contains($0) } == true ? String(text.dropLast()) : text
                        if rects.count == 1 {
                            pending = (trimmed, start, rects[0], line0, link)
                            continue
                        }
                    }
                    append(CompareWord(text: text, pageIndex: start, rects: rects, line: line0), link: link)
                }
            }
        }
        if let pending {
            append(CompareWord(text: pending.text, pageIndex: pending.pageIndex, rects: [pending.rect], line: pending.line), link: pending.link)
        }

        // The word a destination is at: the highest on its page whose middle is below it, and of
        // those on that row, the first in reading order. A destination is the top of what it's
        // at, or a little above it, which can be just inside the line before's descenders. (Not
        // the first below it in reading order: that can be a footer, written first.)
        var pageStart = [Int](repeating: words.count, count: pages.count + 1)
        for (index, word) in words.enumerated().reversed() where word.pageIndex < pages.count {
            pageStart[word.pageIndex] = index
        }
        for page in stride(from: pages.count - 1, through: 0, by: -1) {
            pageStart[page] = min(pageStart[page], pageStart[page + 1])
        }
        var targets: [String: Int?] = [:]
        func target(of link: PageLink) -> Int? {
            if let known = targets[link.uri] { return known }
            var found: Int?
            if let point = link.target, point.pageIndex >= 0, point.pageIndex < pages.count {
                var best: (index: Int, rect: CGRect)?
                for index in pageStart[point.pageIndex]..<pageStart[point.pageIndex + 1] {
                    guard words[index].pageIndex == point.pageIndex, let rect = words[index].rects.first, rect.midY >= point.y else { continue }
                    if let current = best, rect.midY >= current.rect.midY - min(rect.height, current.rect.height) / 2 { continue }
                    best = (index, rect)
                }
                found = best?.index
            }
            targets[link.uri] = found
            return found
        }
        let links = spans.map { CompareLink(words: $0.words, name: $0.link.name, target: target(of: $0.link), targetPage: $0.link.target?.pageIndex) }
        self.init(words: words, pageCount: pages.count, pagesWithoutText: pagesWithoutText, links: links, pageNumbers: pageNumbers)
    }

    /// Whether `word` is a number as `runningLines` takes them out of its lines: in digits, or
    /// in Roman numerals.
    static func isPageNumber(_ word: String) -> Bool {
        !word.isEmpty && (word.allSatisfy { $0.isASCII && $0.isNumber } || word.lowercased().allSatisfy { "ivxlc".contains($0) })
    }

    /// Reads the words of the document at `filePath`, several pages at once on contexts of their
    /// own (as search does). Pages with OCR text in `ocrPages` use it. Stops early, returning
    /// nil, if `isCancelled` says so.
    public static func load(filePath: String, password: String? = nil, ocrPages: [Int: PDFOCRPageResult] = [:], workerCount: Int = PDFSearchActor.defaultWorkerCount, isCancelled: @Sendable () -> Bool = { false }) throws -> ComparedText? {
        let first = try SearchResource(filePath: filePath, password: password)
        let pageCount = first.pageCount
        let labels = pageLabels(of: first, pageCount: pageCount)
        let pages = Mutex([(bounds: CGRect, lines: [Line])](repeating: (.zero, []), count: pageCount))
        let links = Mutex([[PageLink]](repeating: [], count: pageCount))
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
            var destinations: [String: ComparePoint?] = [:]
            while !isCancelled() {
                let pageIndex = next.add(1, ordering: .relaxed).oldValue
                guard pageIndex < pageCount else { break }
                guard let (page, pageLinks) = structuredPage(pageIndex, of: worker, ocr: ocrPages[pageIndex], destinations: &destinations) else {
                    continue
                }
                var lines = lines(of: page)
                assignLinks(pageLinks, to: &lines)
                pages.withLock { $0[pageIndex] = (page.bounds, lines) }
                if !pageLinks.isEmpty { links.withLock { $0[pageIndex] = pageLinks } }
            }
        }
        guard !isCancelled() else { return nil }
        return ComparedText(pages: pages.withLock { $0 }, links: links.withLock { $0 }, labels: labels)
    }

    /// Page `pageIndex`'s text, from the worker's copy of the document, or its OCR result if it
    /// has no text of its own, and its links to other places in the document. `destinations`
    /// keeps where each link the worker has seen goes, as many links go to one place.
    private static func structuredPage(_ pageIndex: Int, of worker: SearchResource, ocr: PDFOCRPageResult?, destinations: inout [String: ComparePoint?]) -> (StructuredPage, [PageLink])? {
        let ctx = worker.ctx
        var pagePtr: FZPage?
        guard mupdf_page_load(ctx, worker.doc, Int32(pageIndex), &pagePtr, nil) == 0, let page = pagePtr else { return nil }
        defer { mupdf_page_drop(ctx, page) }
        var rect = fz_rect()
        mupdf_page_bounds(ctx, page, &rect, nil)
        let bounds = CGRect(x: CGFloat(rect.x0), y: CGFloat(rect.y0), width: CGFloat(rect.x1 - rect.x0), height: CGFloat(rect.y1 - rect.y0))
        guard let structured = try? StructuredPage.load(from: page, pageIndex: pageIndex, ctx: ctx) else { return nil }
        let links = internalLinks(on: page, of: worker, destinations: &destinations)
        if let ocr, structured.blocks.allSatisfy({ $0.type != .text || $0.lines.isEmpty }) {
            return (ocr.structuredPage(bounds: bounds), links)
        }
        return (structured, links)
    }

    /// The document's page labels, if it has any.
    private static func pageLabels(of worker: SearchResource, pageCount: Int) -> [String]? {
        guard mupdf_pdf_has_page_labels(worker.ctx, worker.doc) != 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 256)
        return (0..<pageCount).map { index in
            buffer[0] = 0
            mupdf_pdf_page_label(worker.ctx, worker.doc, Int32(index), &buffer, Int32(buffer.count), nil)
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let label = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? String(index + 1) : label
        }
    }

    /// The links on `page` to places in its document. MuPDF gives a link to a named destination
    /// as "#nameddest=" and the name.
    private static func internalLinks(on page: FZPage, of worker: SearchResource, destinations: inout [String: ComparePoint?]) -> [PageLink] {
        let ctx = worker.ctx
        var linksPtr: FZLink?
        guard mupdf_links_load(ctx, page, &linksPtr, nil) == 0, let first = linksPtr else { return [] }
        defer { mupdf_links_drop(ctx, first) }
        var result: [PageLink] = []
        var current: FZLink? = first
        while let link = current {
            current = mupdf_link_next(link)
            guard let cURI = mupdf_link_uri(link) else { continue }
            let uri = String(cString: cURI)
            let destination: ComparePoint?
            if let known = destinations[uri] {
                destination = known
            } else {
                var page: Int32 = -1
                var x: Float = 0, y: Float = 0
                destination = mupdf_resolve_link_page(ctx, worker.doc, uri, &page, &x, &y) == 0 ? ComparePoint(pageIndex: Int(page), y: CGFloat(y)) : nil
                destinations[uri] = destination
            }
            guard let destination else { continue }
            let r = mupdf_link_rect(link)
            let rect = CGRect(x: CGFloat(r.x0), y: CGFloat(r.y0), width: CGFloat(r.x1 - r.x0), height: CGFloat(r.y1 - r.y0))
            let prefix = "#nameddest="
            let name = uri.hasPrefix(prefix) ? String(uri.dropFirst(prefix.count)) : nil
            result.append(PageLink(rect: rect, uri: uri, name: name, target: destination))
        }
        return result
    }
}
