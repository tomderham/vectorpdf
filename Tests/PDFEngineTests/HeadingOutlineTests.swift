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

/// An outline built from a document's headings: from its tags, or from how its text is set.
@Suite struct HeadingOutlineTests {
    /// Each entry of the RFC's own outline below its title, with its depth there.
    private func flattened(_ nodes: [PDFOutlineNode], depth: Int = 1) -> [(title: String, page: Int?, depth: Int)] {
        nodes.flatMap { [($0.title, $0.targetPage, depth)] + flattened($0.children, depth: depth + 1) }
    }

    /// An RFC's headings are bold at the body's size, their levels only in their numbers; its
    /// reference labels, also bold, aren't headings.
    @Test func anRFCsHeadingsMatchItsOwnOutline() throws {
        let doc = try PDFDocumentCore(filePath: Fixture.url("rfc9457.pdf").path)
        // Its outline is the RFC number, then the title with every section under it.
        let sections = flattened(try #require(doc.outline.last?.children))
        let found = try #require(doc.findHeadings())
        for section in sections {
            let heading = found.first { $0.title == section.title }
            #expect(heading?.page == section.page, "\(section.title)")
            #expect(heading?.level == section.depth, "\(section.title)")
        }
        #expect(!found.contains { $0.title.hasPrefix("[") })
        // In reading order: section 6 before 7, on the page both start on.
        let titles = found.map(\.title)
        #expect(titles.firstIndex(of: "6. IANA Considerations")! < titles.firstIndex(of: "7. References")!)
        #expect(found.count <= sections.count + 3)
    }

    /// A tagged document's headings come from its tags.
    @Test func aTaggedDocumentsHeadingsComeFromItsTags() throws {
        let doc = try PDFDocumentCore(filePath: Fixture.url("nist-tn-2255.pdf").path)
        let found = try #require(doc.findHeadings())
        // Its outline has the section numbers, which the tags leave out.
        let expected = doc.outline.map { $0.title.replacingOccurrences(of: "^\\d+\\. ", with: "", options: .regularExpression) }
        #expect(found.map(\.title) == expected)
        #expect(found.map(\.page) == doc.outline.map(\.targetPage))
    }

    /// A bill's headings, centred and in capitals, some over two lines, double spaced.
    @Test func headingsOverTwoLinesAreOne() throws {
        let doc = try PDFDocumentCore(filePath: Fixture.url("hr1968-ih.pdf").path)
        let found = try #require(doc.findHeadings())
        #expect(found.map(\.title) == [
            "DIVISION A—FULL-YEAR CONTINUING APPROPRIATIONS ACT, 2025", "DIVISION B—HEALTH", "TITLE I—PUBLIC HEALTH EXTENDERS",
            "TITLE II—MEDICARE", "TITLE III—HUMAN SERVICES", "TITLE IV—MEDICAID", "DIVISION C—OTHER MATTERS",
        ])
    }

    /// Bold editing instructions and margin line numbers in a standards draft aren't headings.
    @Test func instructionsAreNotHeadings() throws {
        let doc = try PDFDocumentCore(filePath: Fixture.url("ieee-802.11-draft-layout.pdf").path)
        let found = try #require(doc.findHeadings())
        let clauses = found.filter { HeadingOutline.numberingDepth($0.title) != nil }
        #expect(clauses.map { $0.title.split(separator: " ")[0] } == ["9.3.1.22.19", "9.3.1.22.20", "9.3.3", "9.3.3.2", "9.3.3.5", "9.4.1.4", "9.4.1.8", "9.4.1.8.1"])
        #expect(!found.contains { $0.title.hasSuffix(":") || $0.title.hasSuffix(":.") })
        // Deeper clauses, lower levels.
        let level = Dictionary(clauses.map { ($0.title.split(separator: " ")[0], $0.level) }, uniquingKeysWith: { a, _ in a })
        #expect(level["9.3.3"]! < level["9.3.3.2"]! && level["9.3.3.2"]! < level["9.3.1.22.19"]!)
        #expect(level["9.4.1.8"]! < level["9.4.1.8.1"]!)
    }

    @Test func numberingDepths() {
        #expect(HeadingOutline.numberingDepth("3.1.2. \"status\"") == 3)
        #expect(HeadingOutline.numberingDepth("3 Scope") == 1)
        #expect(HeadingOutline.numberingDepth("A.2 Tables") == 2)
        #expect(HeadingOutline.numberingDepth("IV. Results") == 1)
        #expect(HeadingOutline.numberingDepth("Annex B (informative)") == 1)
        #expect(HeadingOutline.numberingDepth("TITLE II—MEDICARE") == 1)
        #expect(HeadingOutline.numberingDepth("5.65 of the Farm Credit Act") == nil)
        #expect(HeadingOutline.numberingDepth("Title of the work") == nil)
        #expect(HeadingOutline.numberingDepth("Introduction") == nil)
    }

    /// Each entry goes in the one before it of a higher level, however many levels it skips.
    @Test func entriesNest() {
        let headings = [1, 3, 2, 1, 2].enumerated().map { FoundHeading(level: $1, title: "H\($0)", page: 0, top: 100) }
        let entries = HeadingOutline.entries(headings) { _, _ in "#page=1" }
        #expect(entries.map(\.level) == [0, 1, 1, 0, 1])
        #expect(entries.map(\.isOpen) == [true, false, false, true, false])
    }
}

@MainActor
@Suite(.serialized) struct HeadingOutlineViewModelTests {
    @Test func buildingReplacesTheOutlineAndUndoPutsItBack() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("rfc.pdf")
        try FileManager.default.copyItem(at: Fixture.url("rfc9457.pdf"), to: url)
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        let doc = try #require(vm.document)
        func everything() throws -> [[OutlineEntryCopy]] { try doc.outline.indices.map { try doc.copyOutlineEntry(at: [$0]) } }
        let original = try everything()
        vm.undoManager.groupsByEvent = false

        await vm.buildOutlineFromHeadings()
        #expect(doc.outline.first?.title == "Abstract")
        #expect(doc.outline.contains { $0.title == "3. The Problem Details JSON Object" && $0.children.first?.title == "3.1. Members of a Problem Details Object" })
        #expect(vm.isDocumentEdited)
        #expect(vm.undoManager.undoActionName == "Build Outline from Headings")
        let built = try everything()

        vm.undoManager.undo()
        #expect(try everything() == original)
        vm.undoManager.redo()
        #expect(try everything() == built)

        vm.saveDocument()
        let reopened = try PDFDocumentCore(filePath: url.path)
        #expect(reopened.outline.map(\.title) == doc.outline.map(\.title))
    }
}
