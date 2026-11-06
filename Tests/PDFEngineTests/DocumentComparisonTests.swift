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
import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import PDFEngine

/// A PDF with each page's lines in 11 pt Helvetica, 14 pt apart from the top, plus a running
/// header and a page number at the foot of every page.
private func writePagesPDF(at url: URL, pages: [[String]], header: String? = "ACME Standard 42 — Revision", footer: Bool = true) {
    func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
    }
    var objects: [String] = [
        "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
        "", // pages, filled in below
        "3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\nendobj\n",
    ]
    var kids: [String] = []
    for (index, lines) in pages.enumerated() {
        var content = ""
        if let header { content += "BT /F1 9 Tf 72 760 Td (\(escaped(header))) Tj ET\n" }
        var y = 720
        for line in lines {
            content += "BT /F1 11 Tf 72 \(y) Td (\(escaped(line))) Tj ET\n"
            y -= 14
        }
        if footer { content += "BT /F1 9 Tf 300 30 Td (\(index + 1)) Tj ET\n" }
        let pageObject = objects.count + 1
        let contentObject = pageObject + 1
        kids.append("\(pageObject) 0 R")
        objects.append("\(pageObject) 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents \(contentObject) 0 R /Resources << /Font << /F1 3 0 R >> >> >>\nendobj\n")
        objects.append("\(contentObject) 0 obj\n<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream\nendobj\n")
    }
    objects[1] = "2 0 obj\n<< /Type /Pages /Kids [\(kids.joined(separator: " "))] /Count \(pages.count) >>\nendobj\n"
    var pdf = "%PDF-1.4\n"
    var offsets: [Int] = []
    for object in objects {
        offsets.append(pdf.utf8.count)
        pdf += object
    }
    let xrefOffset = pdf.utf8.count
    pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets {
        pdf += String(format: "%010d 00000 n \n", offset)
    }
    pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
    try! Data(pdf.utf8).write(to: url)
}

/// `count` distinct sentences, numbered so each is unique, as a spec's clauses would be.
private func clauses(_ range: Range<Int>, prefix: String = "Clause") -> [String] {
    range.map { "\(prefix) \($0): the contractor shall supply item \($0 * 7 % 101) to the site." }
}

/// Lines split into pages of `perPage`.
private func paginate(_ lines: [String], perPage: Int = 40) -> [[String]] {
    stride(from: 0, to: lines.count, by: perPage).map { Array(lines[$0..<min($0 + perPage, lines.count)]) }
}

/// A document's text from plain lines, one page each list, without reading a PDF.
private func text(_ pages: [[String]]) -> ComparedText {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    return ComparedText(pages: pages.map { lines in
        (bounds, lines.enumerated().map { index, line in
            let y = CGFloat(100 + index * 14)
            var x: CGFloat = 72
            let words = line.split(separator: " ").map { word -> (text: String, rect: CGRect) in
                defer { x += CGFloat(word.count) * 6 + 3 }
                return (String(word), CGRect(x: x, y: y, width: CGFloat(word.count) * 6, height: 11))
            }
            return ComparedText.Line(text: line, bbox: CGRect(x: 72, y: y, width: 400, height: 11), words: words, joinsNext: LineJoin(line, index + 1 < lines.count ? lines[index + 1] : "") == .wordBreak)
        })
    })
}

private func words(_ change: CompareChange, on side: CompareSide, of comparison: DocumentComparison) -> String {
    change.words(on: side).map { comparison.text(on: side).words[$0].text }.joined(separator: " ")
}

@Suite struct TextDiffTests {
    private func tokens(_ s: String) -> [Int32] { s.unicodeScalars.map { Int32($0.value) } }

    @Test func myersFindsTheLongestCommonSubsequence() throws {
        let a = tokens("ABCABBA"), b = tokens("CBABAC")
        let matches = try #require(TextDiff.myers(a, 0..<a.count, b, 0..<b.count))
        #expect(matches.count == 4)
        #expect(matches.allSatisfy { a[$0.0] == b[$0.1] })
        #expect(zip(matches, matches.dropFirst()).allSatisfy { $0.0 < $1.0 && $0.1 < $1.1 })
    }

    @Test func myersGivesUpPastItsLimit() {
        let a = tokens("abcdefgh"), b = tokens("ijklmnop")
        #expect(TextDiff.myers(a, 0..<a.count, b, 0..<b.count, maxEditDistance: 4) == nil)
    }

    @Test func matchesSurviveALargeInsertion() {
        let a = Array(Int32(0)..<Int32(5000))
        let b = Array(a[0..<1000]) + Array(Int32(90000)..<Int32(93000)) + Array(a[1000...])
        let matches = TextDiff.matches(a, b)
        #expect(matches.count == 5000)
        #expect(matches[1000] == (1000, 4000))
    }

    @Test func repeatedWordsStillAlign() {
        // No word occurs once: the rarest shared count anchors instead.
        let row: [Int32] = [1, 2, 3, 1, 2, 3]
        let a = Array(repeating: row, count: 4).flatMap { $0 }
        var b = a
        b.insert(9, at: 7)
        #expect(TextDiff.matches(a, b).count == a.count)
    }

    @Test func longestIncreasingSubsequence() {
        let values: [CGFloat] = [3, 1, 4, 1, 5, 9, 2, 6]
        #expect(TextDiff.longestIncreasingSubsequence(values, strictly: true).map { values[$0] } == [1, 4, 5, 6])
        #expect(TextDiff.longestIncreasingSubsequence([1, 1, 1], strictly: false).count == 3)
        #expect(TextDiff.longestIncreasingSubsequence([1, 1, 1], strictly: true).count == 1)
    }
}

@Suite struct DocumentComparisonTests {
    @Test func identicalTextHasNoChanges() {
        let pages = paginate(clauses(0..<100))
        let comparison = DocumentComparison(original: text(pages), revised: text(pages))
        #expect(comparison.changes.isEmpty)
        #expect(comparison.similarity == 1)
        #expect(comparison.anchors.count == 100)
    }

    @Test func aReplacedWordIsOneChange() throws {
        let a = clauses(0..<50)
        var b = a
        b[20] = b[20].replacingOccurrences(of: "supply", with: "install")
        let comparison = DocumentComparison(original: text(paginate(a)), revised: text(paginate(b)))
        let change = try #require(comparison.changes.only)
        #expect(words(change, on: .original, of: comparison) == "supply")
        #expect(words(change, on: .revised, of: comparison) == "install")
    }

    @Test func anInsertionSpanningPagesShiftsTheRestWithoutChangingIt() throws {
        let a = clauses(0..<200)
        let inserted = clauses(0..<90, prefix: "New")
        let b = Array(a[0..<30]) + inserted + Array(a[30...])
        let comparison = DocumentComparison(original: text(paginate(a)), revised: text(paginate(b)))
        let change = try #require(comparison.changes.only)
        #expect(change.original.isEmpty)
        #expect(words(change, on: .revised, of: comparison) == inserted.joined(separator: " "))
        // Clause 150 is on page 3 of the original and page 6 of the revision.
        let anchor = try #require(comparison.anchors.first { $0.original.pageIndex == 150 / 40 && abs($0.original.y - CGFloat(100 + (150 % 40) * 14) - 5.5) < 1 })
        #expect(anchor.revised.pageIndex == (150 + 90) / 40)
    }

    @Test func shortRunsInCommonJoinNeighbouringChanges() throws {
        let a = [["alpha beta gamma of the delta epsilon zeta eta theta iota kappa"]]
        let b = [["alpha BETA GAMMA of the DELTA epsilon zeta eta theta iota kappa"]]
        let comparison = DocumentComparison(original: text(a), revised: text(b))
        let change = try #require(comparison.changes.only)
        #expect(words(change, on: .revised, of: comparison) == "BETA GAMMA of the DELTA")
    }

    @Test func optionsIgnoreCaseAndPunctuation() {
        let a = [["The Contractor shall, at its cost, supply the goods."]]
        let b = [["the contractor shall at its cost supply the goods"]]
        #expect(DocumentComparison(original: text(a), revised: text(b)).changes.count > 0)
        let lenient = DocumentComparison(original: text(a), revised: text(b), options: CompareOptions(ignoresCase: true, ignoresPunctuation: true))
        #expect(lenient.changes.isEmpty)
    }

    @Test func typographicQuotesAndDashesMatchPlainOnes() {
        let a = [["the \u{201C}Works\u{201D} \u{2013} as defined"]]
        let b = [["the \"Works\" - as defined"]]
        #expect(DocumentComparison(original: text(a), revised: text(b)).changes.isEmpty)
    }

    @Test func aWordHyphenatedAcrossLinesMatchesItWhole() throws {
        let a = [["the representa-", "tives shall meet"]]
        let b = [["the representatives shall meet"]]
        let comparison = DocumentComparison(original: text(a), revised: text(b))
        #expect(comparison.changes.isEmpty)
        let word = try #require(comparison.original.words.first { $0.text == "representatives" })
        #expect(word.rects.count == 2)
    }

    @Test func runningHeadersAndPageNumbersAreLeftOut() {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        func line(_ text: String, y: CGFloat) -> ComparedText.Line {
            ComparedText.Line(text: text, bbox: CGRect(x: 72, y: y, width: 300, height: 10), words: [(text, CGRect(x: 72, y: y, width: 300, height: 10))], joinsNext: false)
        }
        let pages = (0..<6).map { index in
            (bounds, [line("Spec 42 Revision", y: 30), line("Body\(index)", y: 400), line("Page \(index + 1) of 6", y: 760)])
        }
        #expect(ComparedText(pages: pages).words.map(\.text) == (0..<6).map { "Body\($0)" })
    }

    @Test func highlightsMergeWordsOnALine() throws {
        let a = [["one two three four five six seven"]]
        let b = [["one two THREE FOUR FIVE six seven"]]
        let comparison = DocumentComparison(original: text(a), revised: text(b))
        let boxes = try #require(comparison.highlights(on: .revised)[0])
        #expect(boxes.count == 1)
        #expect(comparison.gapMarkers(on: .revised).isEmpty)
    }

    @Test func aDeletionLeavesAMarkerOnTheOtherSide() throws {
        let a = [["one two three four five six seven eight"]]
        let b = [["one two three seven eight"]]
        let comparison = DocumentComparison(original: text(a), revised: text(b))
        let change = try #require(comparison.changes.only)
        #expect(change.revised.isEmpty)
        #expect(comparison.gapMarkers(on: .revised)[0]?.count == 1)
        #expect(comparison.location(of: change, on: .revised)?.pageIndex == 0)
    }
}

@Suite struct CompareScrollMapTests {
    @Test func followsLineForLine() {
        let map = CompareScrollMap(points: [(0, 100), (14, 114), (28, 128)])
        #expect(map.offset(7, from: .original) == 107)
        #expect(map.offset(121, from: .revised) == 21)
        #expect(map.offset(-10, from: .original) == 90)
        #expect(map.offset(40, from: .original) == 140)
    }

    @Test func holdsStillThroughAnInsertion() {
        // 500 points inserted on the revised side between two lines.
        let map = CompareScrollMap(points: [(0, 0), (14, 14), (28, 528)])
        #expect(map.offset(100, from: .revised) == 14)
        #expect(map.offset(400, from: .revised) == 14)
        #expect(map.offset(521, from: .revised) == 21)
        // From the side without it, the other moves on through the insertion.
        #expect(map.offset(21, from: .original) == 271)
    }

    @Test func dropsAnchorsOutOfStep() {
        let map = CompareScrollMap(points: [(0, 0), (10, 10), (20, 500), (30, 30), (40, 40)])
        #expect(map.points.map(\.1) == [0, 10, 30, 40])
    }
}

@Suite struct DocumentComparisonPDFTests {
    @Test func comparesRevisionsOfAPDF() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = clauses(0..<300)
        var b = Array(a[0..<40]) + clauses(0..<100, prefix: "Added") + Array(a[40...])
        b[300] = b[300].replacingOccurrences(of: "contractor", with: "supplier")
        b.remove(at: 350)
        let originalURL = dir.appendingPathComponent("original.pdf")
        let revisedURL = dir.appendingPathComponent("revised.pdf")
        writePagesPDF(at: originalURL, pages: paginate(a))
        writePagesPDF(at: revisedURL, pages: paginate(b), header: "ACME Standard 42 — Revision B")

        let original = try #require(try ComparedText.load(filePath: originalURL.path))
        let revised = try #require(try ComparedText.load(filePath: revisedURL.path))
        #expect(original.pageCount == 8)
        #expect(revised.pageCount == 10)
        // Headers and page numbers aren't part of the text.
        #expect(!original.words.contains { $0.text == "ACME" })
        #expect(original.words.first?.text == "Clause")

        let comparison = DocumentComparison(original: original, revised: revised)
        #expect(comparison.changes.count == 3)
        let inserted = comparison.changes[0]
        #expect(inserted.original.isEmpty)
        #expect(comparison.location(of: inserted, on: .revised)?.pageIndex == 1)
        #expect(words(comparison.changes[1], on: .revised, of: comparison) == "supplier")
        #expect(comparison.changes[2].revised.isEmpty)
        // The whole sentence, not "to the site. Clause 250: … item 33".
        #expect(words(comparison.changes[2], on: .original, of: comparison) == a[250])
        // The 100 added clauses run from page 2 to page 4 of the revision.
        #expect(Set(comparison.highlights(on: .revised).keys).isSuperset(of: [1, 2, 3]))
        #expect(comparison.highlights(on: .original).count == 2)
    }

    @Test func stopsWhenCancelled() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("doc.pdf")
        writePagesPDF(at: url, pages: paginate(clauses(0..<80)))
        #expect(try ComparedText.load(filePath: url.path, isCancelled: { true }) == nil)
    }
}

/// Two revisions of a 300-clause document: the revision adds 100 clauses after clause 40, so
/// everything after moves on two and a half pages, and changes a word in clause 200.
private func writeRevisions(in dir: URL) -> (original: URL, revised: URL) {
    let a = clauses(0..<300)
    var b = Array(a[0..<40]) + clauses(0..<100, prefix: "Added") + Array(a[40...])
    b[300] = b[300].replacingOccurrences(of: "contractor", with: "supplier")
    let original = dir.appendingPathComponent("original.pdf")
    let revised = dir.appendingPathComponent("revised.pdf")
    writePagesPDF(at: original, pages: paginate(a))
    writePagesPDF(at: revised, pages: paginate(b))
    return (original, revised)
}

@MainActor
private func eventually(_ condition: () -> Bool) async throws -> Bool {
    for _ in 0..<1000 where !condition() {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

@Suite @MainActor struct DocumentCompareSessionTests {
    /// A session comparing `original` with `revised`, opened in a view model as a Compare
    /// Documents tab opens it.
    private func compare(_ original: URL, _ revised: URL) async -> (PDFViewerViewModel, DocumentCompareSession) {
        let viewModel = PDFViewerViewModel()
        let session = DocumentCompareSession(original: original, revised: viewModel)
        viewModel.compareSession = session
        await viewModel.loadDocument(from: revised.path)
        return (viewModel, session)
    }

    @Test func comparesBothDocumentsAndHighlightsEachSide() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = writeRevisions(in: dir)
        let (viewModel, session) = await compare(urls.original, urls.revised)
        defer { session.end() }
        #expect(try await eventually { session.status == .done })
        #expect(session.changeCount == 2)
        #expect(session.title == "original.pdf ↔ revised.pdf")
        #expect(try await eventually { viewModel.documentTitle == session.title })

        // Both documents are read-only, and know which side they are.
        #expect(session.original.isReadOnlyDocument && viewModel.isReadOnlyDocument)
        #expect(viewModel.isTransientWindow)
        #expect(!session.original.compareMarks.isRevised && viewModel.compareMarks.isRevised)
        // The original has only the changed word; the revision has the added clauses too.
        #expect(session.original.compareMarks.changed.keys.sorted() == [5])
        #expect(Set(viewModel.compareMarks.changed.keys).isSuperset(of: [1, 2, 3, 7]))
        #expect(session.original.compareMarks.gaps[0]?.count == 1)
    }

    @Test func optionsCompareAgain() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.pdf"), b = dir.appendingPathComponent("b.pdf")
        writePagesPDF(at: a, pages: [["The Contractor shall supply the goods."]])
        writePagesPDF(at: b, pages: [["the contractor shall supply the goods"]])
        let (_, session) = await compare(a, b)
        defer { session.end() }
        #expect(try await eventually { session.status == .done })
        #expect(session.changeCount > 0)
        session.options = CompareOptions(ignoresCase: true, ignoresPunctuation: true)
        #expect(try await eventually { session.status == .done && session.changeCount == 0 })
        #expect(session.original.compareMarks.changed.isEmpty)
    }

    @Test(.showsWindows) func scrollsTogetherAndMovesBetweenChanges() async throws {
        _ = NSApplication.shared
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = writeRevisions(in: dir)
        let window = DocumentWindowing.openComparison(original: urls.original, revised: urls.revised, besides: nil)
        defer { window.close() }
        let viewModel = try #require((window.contentViewController as? NSHostingController<PDFViewerMainView>)?.rootView.viewModel)
        let session = try #require(viewModel.compareSession)
        #expect(try await eventually {
            session.status == .done && session.original.hostScrollView != nil && session.revised.hostScrollView != nil
        })
        try await Task.sleep(for: .milliseconds(300))
        #expect(window.title == "original.pdf ↔ revised.pdf")
        #expect(window.tab.title == "original.pdf ↔ revised.pdf")
        #expect(viewModel.isSidebarVisible)

        // Clause 150 is line 10 of page 7 of the revision (index 6), and line 30 of page 4 of the
        // original (index 3).
        let originalScroll = try #require(session.original.hostScrollView)
        let revisedScroll = try #require(session.revised.hostScrollView)
        func readingLine(_ scrollView: NSScrollView) -> CGFloat {
            scrollView.contentView.bounds.minY + scrollView.contentView.bounds.height * DocumentCompareSession.readingLine
        }
        func y(onPage page: Int, line: Int, of scrollView: NSScrollView) throws -> CGFloat {
            let canvas = try #require(scrollView.documentView as? PDFCanvasView)
            let geometry = try #require(canvas.pageGeometry(for: page))
            return geometry.canvasRect(forPageRect: CGRect(x: 100, y: CGFloat(72 + line * 14), width: 1, height: 1)).midY
        }
        let clip = revisedScroll.contentView
        let clauseY = try y(onPage: 6, line: 10, of: revisedScroll)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: clauseY - clip.bounds.height * DocumentCompareSession.readingLine))
        revisedScroll.reflectScrolledClipView(clip)
        try await Task.sleep(for: .milliseconds(100))
        #expect(abs(readingLine(originalScroll) - (try y(onPage: 3, line: 30, of: originalScroll))) < 4)

        // Zooming the tab's document zooms the original too, and they still line up after.
        viewModel.setZoom(1.25)
        #expect(try await eventually { abs(session.original.zoomScale - 1.25) < 0.001 })
        try await Task.sleep(for: .milliseconds(200))
        let zoomedY = try y(onPage: 6, line: 10, of: revisedScroll)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: zoomedY - clip.bounds.height * DocumentCompareSession.readingLine))
        revisedScroll.reflectScrolledClipView(clip)
        #expect(abs(readingLine(originalScroll) - (try y(onPage: 3, line: 30, of: originalScroll))) < 4)

        // A pinch, zooming frame by frame: the two zooms settle together (they don't pass the
        // zoom back and forth), and clause 150 stays on the reading line in both.
        for step in 0..<12 {
            viewModel.zoomScale = 1.25 + CGFloat(step) * 0.05
            try await Task.sleep(for: .milliseconds(16))
        }
        try await Task.sleep(for: .milliseconds(400))
        let settled = (viewModel.zoomScale, session.original.zoomScale)
        #expect(abs(settled.0 - 1.8) < 0.001 && abs(settled.1 - 1.8) < 0.001)
        try await Task.sleep(for: .milliseconds(300))
        #expect(viewModel.zoomScale == settled.0 && session.original.zoomScale == settled.1)
        #expect(abs(readingLine(revisedScroll) - (try y(onPage: 6, line: 10, of: revisedScroll))) < 4)
        #expect(abs(readingLine(originalScroll) - (try y(onPage: 3, line: 30, of: originalScroll))) < 4)

        // Zoomed in past the panes' width, scrolling across scrolls the other across too.
        let range = { (scrollView: NSScrollView) in (scrollView.documentView?.frame.width ?? 0) - scrollView.contentView.bounds.width }
        #expect(range(revisedScroll) > 1)
        clip.scroll(to: NSPoint(x: range(revisedScroll), y: clip.bounds.minY))
        revisedScroll.reflectScrolledClipView(clip)
        #expect(abs(originalScroll.contentView.bounds.minX - range(originalScroll)) < 1)
        viewModel.setZoom(1.25)
        try await Task.sleep(for: .milliseconds(400))
        clip.scroll(to: NSPoint(x: 0, y: (try y(onPage: 6, line: 10, of: revisedScroll)) - clip.bounds.height * DocumentCompareSession.readingLine))
        revisedScroll.reflectScrolledClipView(clip)

        // The original moving by itself (not scrolled by the user) is put back level.
        let originalClip = originalScroll.contentView
        let level = originalClip.bounds.minY
        originalClip.scroll(to: NSPoint(x: originalClip.bounds.minX, y: level + 300))
        originalScroll.reflectScrolledClipView(originalClip)
        #expect(abs(originalClip.bounds.minY - level) < 1)

        // With scrolling together off, the original stays put.
        session.isScrollingTogether = false
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: clip.bounds.minY + 200))
        revisedScroll.reflectScrolledClipView(clip)
        #expect(originalClip.bounds.minY == level)
        session.isScrollingTogether = true

        // Searching the revision from the sidebar: the original follows to the same clause.
        viewModel.searchQuery = "Clause 250:"
        viewModel.performSearch(autoNavigate: true)
        #expect(try await eventually { viewModel.currentPageIndex == 8 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs(readingLine(originalScroll) - readingLine(originalScroll)) < 1)
        #expect((5...6).contains(session.original.currentPageIndex))

        // Back above clause 200, then Next Change: the changed word in clause 200, past the
        // reading line.
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: clauseY - clip.bounds.height * DocumentCompareSession.readingLine))
        revisedScroll.reflectScrolledClipView(clip)
        session.nextChange()
        #expect(session.currentChange == 1)
        #expect(session.revised.compareMarks.active?.pageIndex == 7)
        #expect(session.original.compareMarks.active?.pageIndex == 5)
        session.previousChange()
        #expect(session.currentChange == 0)
        #expect(session.revised.compareMarks.active?.pageIndex == 1)
        #expect(session.original.compareMarks.active?.rects.count == 1)
    }
}

private extension Collection {
    /// The only element, or nil if there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
