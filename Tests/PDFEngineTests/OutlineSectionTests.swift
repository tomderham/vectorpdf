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
import Testing
@testable import PDFEngine

/// Which outline section a search result is in (`OutlineSections`, `searchSectionGroups`).
struct OutlineSectionTests {

    private func result(page: Int, y: CGFloat?) -> SearchResult {
        let quads = y.map { [PDFQuad(rect: CGRect(x: 72, y: $0 - 5, width: 40, height: 10))] } ?? []
        return SearchResult(pageIndex: page, matchedText: "x", snippet: "x", highlightQuads: quads)
    }

    /// 1 Intro (page 0), 2 Design mid-page 3 with 2.1 at the same place and 2.2 lower down,
    /// 3 Appendix (page 8) listed before 2 in the outline.
    private let outline = [
        PDFOutlineNode(title: "Intro", targetPage: 0),
        PDFOutlineNode(title: "Appendix", targetPage: 8, targetY: 100),
        PDFOutlineNode(title: "Design", targetPage: 3, targetY: 400, children: [
            PDFOutlineNode(title: "Loads", targetPage: 3, targetY: 400),
            PDFOutlineNode(title: "Wind", targetPage: 3, targetY: 600),
            PDFOutlineNode(title: "No page"),
        ]),
    ]

    @Test func sectionIsTheLastEntryStartingBeforeThePlace() {
        let sections = OutlineSections(outline: outline)
        #expect(sections.section(page: 0, y: 50)?.path == ["Intro"])
        #expect(sections.section(page: 3, y: 300)?.path == ["Intro"])
        // A chapter and its first section starting together give the section.
        #expect(sections.section(page: 3, y: 450)?.path == ["Design", "Loads"])
        #expect(sections.section(page: 3, y: 700)?.path == ["Design", "Wind"])
        #expect(sections.section(page: 5, y: nil)?.path == ["Design", "Wind"])
        // Outline order doesn't matter, only where entries point.
        #expect(sections.section(page: 8, y: 50)?.path == ["Design", "Wind"])
        #expect(sections.section(page: 8, y: 150)?.path == ["Appendix"])
    }

    /// An entry pointing at its heading's baseline still holds the heading's own text.
    @Test func headingTextJustAboveItsEntryIsInIt() {
        let sections = OutlineSections(outline: outline)
        #expect(sections.section(page: 3, y: 596)?.title == "Wind")
        #expect(sections.section(page: 3, y: 580)?.title == "Loads")
    }

    /// A subsection starting low on one page and ending just before the next one's heading on the
    /// following page is never the first entry on either page, so following the page alone
    /// skipped it (37.16.9 in 802.11bn D2.1); following the reading line finds it on both.
    @Test func readingLineFindsASectionThatIsNeverFirstOnAPage() {
        let eight = PDFOutlineNode(title: "37.16.8", targetPage: 10, targetY: 200)
        let nine = PDFOutlineNode(title: "37.16.9", targetPage: 10, targetY: 600)
        let ten = PDFOutlineNode(title: "37.16.10", targetPage: 11, targetY: 500)
        let outline = [PDFOutlineNode(title: "37.16", targetPage: 9, targetY: 100, children: [eight, nine, ten])]
        #expect(PDFOutlineNode.findActiveNodeId(in: outline, for: 10) == eight.id)
        #expect(PDFOutlineNode.findActiveNodeId(in: outline, for: 11) == ten.id)

        let sections = OutlineSections(outline: outline)
        #expect(sections.section(page: 10, y: 700)?.nodeId == nine.id)
        #expect(sections.section(page: 11, y: 80)?.nodeId == nine.id)
        #expect(sections.section(page: 11, y: 520)?.nodeId == ten.id)
    }

    @Test func nothingBeforeTheFirstEntry() {
        let sections = OutlineSections(outline: [PDFOutlineNode(title: "Late", targetPage: 2, targetY: 300)])
        #expect(sections.section(page: 1, y: 500) == nil)
        #expect(sections.section(page: 2, y: 100) == nil)
        #expect(sections.section(page: 2, y: nil) == nil)
        #expect(OutlineSections(outline: []).isEmpty)
    }

    /// Results are grouped by section, then page; a page holding the end of one section and the
    /// start of the next appears under both.
    @Test @MainActor func resultsGroupBySectionThenPage() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("sections.pdf")
        makeLabelledPDF(at: url, labels: (1...10).map(String.init))
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        try #require(vm.document).outline = outline
        vm.searchResults = [
            result(page: 1, y: 100), result(page: 3, y: 200),
            result(page: 3, y: 500), result(page: 3, y: 550), result(page: 4, y: 100),
            result(page: 9, y: nil),
        ]

        let groups = vm.searchSectionGroups
        #expect(groups.map { $0.section?.title } == ["Intro", "Loads", "Wind", "Appendix"])
        #expect(groups[0].pages.map(\.pageIndex) == [1, 3])
        #expect(groups[1].pages.map(\.pageIndex) == [3])
        #expect(groups[1].pages[0].matches.count == 2)
        #expect(Set(groups.flatMap(\.pages).map(\.id)).count == 5)
    }

    /// Choosing an outline entry beside Search on the right brings its results into view, or its
    /// subsections' when it has none of its own, without going to one.
    @Test @MainActor func choosingAnEntryRevealsItsResultsWithoutGoingToOne() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("reveal.pdf")
        makeLabelledPDF(at: url, labels: (1...10).map(String.init))
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        try #require(vm.document).outline = outline
        vm.searchResults = [result(page: 1, y: 100), result(page: 3, y: 500), result(page: 3, y: 700)]
        vm.activeSearchMatchIndex = 0
        let groups = vm.searchSectionGroups

        // Design starts where Loads does, so holds none of its own: Loads' come up.
        vm.revealSearchResults(in: outline[2])
        #expect(vm.searchReveal?.groupId == groups[1].id)
        vm.revealSearchResults(in: outline[2].children[1])
        #expect(vm.searchReveal?.groupId == groups[2].id)
        #expect(vm.activeSearchMatchIndex == 0)

        // Nothing in Appendix: the list stays where it is.
        let before = vm.searchReveal
        vm.revealSearchResults(in: outline[1])
        #expect(vm.searchReveal == before)
    }

    @Test @MainActor func noOutlineMeansOneGroupWithoutASection() {
        let vm = PDFViewerViewModel()
        vm.searchResults = [result(page: 0, y: 10), result(page: 2, y: 10)]
        let groups = vm.searchSectionGroups
        #expect(groups.count == 1)
        #expect(groups[0].section == nil)
        #expect(groups[0].pages.map(\.pageIndex) == [0, 2])
    }

    /// On a real document, where the outline's positions and search highlights both come from
    /// MuPDF, each section's heading is found in that section: the two use the same page space.
    @Test func headingsFallInTheirOwnSectionInARealDocument() async throws {
        let url = Fixture.url("rfc9457.pdf")
        let doc = try PDFDocumentCore(filePath: url.path)
        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: url.path)

        var entries: [PDFOutlineNode] = []
        func visit(_ nodes: [PDFOutlineNode]) {
            for node in nodes {
                if node.targetPage != nil, node.targetY != nil { entries.append(node) }
                visit(node.children)
            }
        }
        visit(doc.outline)
        try #require(entries.count >= 10, "The RFC's outline should point at places on its pages")

        var checked = 0
        for entry in entries {
            let page = try #require(entry.targetPage)
            let y = try #require(entry.targetY)
            // A heading reads like "3.1. Members of a Problem Details Object": search its words.
            let words = entry.title.split(separator: " ").drop { $0.first?.isNumber == true }.joined(separator: " ")
            guard words.count >= 4 else { continue }
            // Two entries close together can't be told apart by searching their words.
            let crowded = entries.contains { $0.id != entry.id && $0.targetPage == page && abs(($0.targetY ?? 0) - y) < 40 }
            guard !crowded else { continue }
            let hits = try await actor.search(query: words).filter { $0.pageIndex == page }
            // The heading is the hit nearest its entry, on the same page.
            guard let heading = hits.min(by: { abs($0.boundingRect.midY - y) < abs($1.boundingRect.midY - y) }),
                  abs(heading.boundingRect.midY - y) < 40 else { continue }
            let section = doc.outlineSections.section(page: page, y: heading.boundingRect.midY)
            #expect(section?.title == entry.title, "\(entry.title) at y \(y), heading at \(heading.boundingRect.midY)")
            checked += 1
        }
        #expect(checked >= 10, "Only \(checked) headings checked")
    }

    /// A closed entry counts the results in the entries inside it too; an open one only its own.
    @Test func aClosedEntryCountsTheResultsInsideIt() {
        let design = outline[2]
        let hits = [design.id: 1, design.children[0].id: 2, design.children[1].id: 4]
        let open = PDFOutlineNSView.searchMark(for: design, isOpen: true, hits: hits, activeSection: design.children[1].id)
        #expect(open.count == 1 && !open.holdsActive)
        let closed = PDFOutlineNSView.searchMark(for: design, isOpen: false, hits: hits, activeSection: design.children[1].id)
        #expect(closed.count == 7 && closed.holdsActive)
        #expect(PDFOutlineNSView.searchMark(for: outline[0], isOpen: false, hits: hits, activeSection: nil).count == 0)
    }

    /// The outline's counts agree with the sections the results list is grouped by, and follow
    /// the results as they stream in.
    @MainActor
    @Test func searchHitsBySectionMatchTheResultsList() async throws {
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: Fixture.url("nist-tn-2255.pdf").path)
        let doc = try #require(vm.document)
        try #require(!doc.outlineSections.isEmpty)
        vm.searchResults = stride(from: 0, to: doc.pageCount, by: 3).map { result(page: $0, y: 400) }

        var expected: [UUID: Int] = [:]
        for group in vm.searchSectionGroups {
            guard let section = group.section else { continue }
            expected[section.nodeId, default: 0] += group.pages.reduce(0) { $0 + $1.matches.count }
        }
        #expect(!expected.isEmpty)
        #expect(vm.searchHitsBySection == expected)

        // More results arrive: counted again.
        let last = try #require(vm.searchResults.last)
        vm.searchResults.append(result(page: last.pageIndex, y: 400))
        #expect(vm.searchHitsBySection.values.reduce(0, +) == expected.values.reduce(0, +) + 1)

        vm.activeSearchMatchIndex = vm.searchResults.count - 1
        #expect(vm.activeSearchSectionId == OutlineSections(outline: doc.outline).section(page: last.pageIndex, y: 400)?.nodeId)
        vm.searchResults = []
        #expect(vm.searchHitsBySection.isEmpty && vm.activeSearchSectionId == nil)
    }
}
