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

/// Outline entries (bookmarks) can be added, renamed, pointed elsewhere, moved, nested and deleted.
@Suite(.serialized) struct OutlineEditingTests {
    /// The outline's titles, nested as in the outline.
    private func shape(_ nodes: [PDFOutlineNode]) -> [String] {
        nodes.map { node in node.children.isEmpty ? node.title : "\(node.title) [\(shape(node.children).joined(separator: ", "))]" }
    }

    private func saved(_ doc: PDFDocumentCore, in dir: URL) throws -> PDFDocumentCore {
        let url = dir.appendingPathComponent("Saved \(UUID().uuidString).pdf")
        try doc.save(to: url.path)
        return try PDFDocumentCore(filePath: url.path)
    }

    @Test func aDocumentWithoutAnOutlineGetsOne() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Plain.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo", "Charlie"])
        let doc = try PDFDocumentCore(filePath: url.path)
        #expect(doc.outline.isEmpty)

        try doc.addOutlineEntry(title: "Introduction", page: 0, y: 0, at: [0])
        try doc.addOutlineEntry(title: "Results", page: 2, y: 300, at: [1])
        try doc.addOutlineEntry(title: "Table 1", page: 2, y: 500, at: [1, 0])
        #expect(shape(doc.outline) == ["Introduction", "Results [Table 1]"])

        let reopened = try saved(doc, in: dir)
        #expect(shape(reopened.outline) == ["Introduction", "Results [Table 1]"])
        let table = try #require(reopened.outline.node(at: [1, 0]))
        #expect(table.targetPage == 2)
        #expect(abs((table.targetY ?? 0) - 500) < 1)
    }

    @Test func renamingAndRepointingKeepTheRest() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Plain.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo", "Charlie"])
        let doc = try PDFDocumentCore(filePath: url.path)
        try doc.addOutlineEntry(title: "Draft", page: 1, y: 100, at: [0])
        try doc.renameOutlineEntry(at: [0], to: "Methods")
        #expect(doc.outline.first?.title == "Methods")
        #expect(doc.outline.first?.targetPage == 1)
        try doc.setOutlineEntryDestination(at: [0], page: 2, y: 40)
        #expect(doc.outline.first?.title == "Methods")
        #expect(doc.outline.first?.targetPage == 2)
    }

    @Test func movingTakesTheEntriesUnderIt() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Plain.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo", "Charlie"])
        let doc = try PDFDocumentCore(filePath: url.path)
        for (index, title) in ["A", "B", "C"].enumerated() {
            try doc.addOutlineEntry(title: title, page: index, y: 0, at: [index])
        }
        try doc.addOutlineEntry(title: "A1", page: 0, y: 200, at: [0, 0])
        try doc.addOutlineEntry(title: "A2", page: 0, y: 400, at: [0, 1])

        // Down past B: before C, as the outline is now.
        try doc.moveOutlineEntry(from: [0], to: [2])
        #expect(shape(doc.outline) == ["B", "A [A1, A2]", "C"])
        // Into B, after its last (it has none): indenting.
        try doc.moveOutlineEntry(from: [2], to: [0, 0])
        #expect(shape(doc.outline) == ["B [C]", "A [A1, A2]"])
        // Out of A, after it: outdenting.
        try doc.moveOutlineEntry(from: [1, 1], to: [2])
        #expect(shape(doc.outline) == ["B [C]", "A [A1]", "A2"])
        // Up to the top.
        try doc.moveOutlineEntry(from: [2], to: [0])
        #expect(shape(doc.outline) == ["A2", "B [C]", "A [A1]"])
        #expect(throws: (any Error).self) { try doc.moveOutlineEntry(from: [1], to: [1, 0]) }

        let reopened = try saved(doc, in: dir)
        #expect(shape(reopened.outline) == ["A2", "B [C]", "A [A1]"])
        #expect(reopened.outline.node(at: [2, 0])?.targetPage == 0)
        #expect(abs((reopened.outline.node(at: [2, 0])?.targetY ?? 0) - 200) < 1)

        try doc.deleteOutlineEntry(at: [1])
        #expect(shape(doc.outline) == ["A2", "A [A1]"])
    }

    @Test func aRealOutlineCanBeEdited() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("rfc.pdf")
        try FileManager.default.copyItem(at: Fixture.url("rfc9457.pdf"), to: url)
        let doc = try PDFDocumentCore(filePath: url.path)
        let before = doc.outline
        let first = try #require(before.first)
        try doc.moveOutlineEntry(from: [0], to: [before.count])
        #expect(doc.outline.last?.title == first.title)
        #expect(shape([doc.outline.last!]) == shape([first]))
        #expect(doc.outline.last?.targetPage == first.targetPage)
    }

    @Test func placesAfterTheEntryMovedMoveUp() {
        #expect(PDFDocumentCore.placeAfterRemoving([0], [2]) == [1])
        #expect(PDFDocumentCore.placeAfterRemoving([2], [0]) == [0])
        #expect(PDFDocumentCore.placeAfterRemoving([0], [1, 3]) == [0, 3])
        #expect(PDFDocumentCore.placeAfterRemoving([1, 1], [2]) == [2])
        #expect(PDFDocumentCore.placeAfterRemoving([1, 0], [1, 2, 0]) == [1, 1, 0])
    }
}

/// The outline's commands in the window: entries for the page being read, moved and nested.
@MainActor
@Suite(.serialized) struct OutlineEditingViewModelTests {
    @Test func entriesAreAddedForThePageBeingReadInPageOrder() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Plain.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo", "Charlie"])
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        #expect(vm.canEditOutline)

        vm.currentPageIndex = 2
        vm.promptToAddOutlineEntry()
        vm.currentPageIndex = 0
        vm.promptToAddOutlineEntry()
        let outline = try #require(vm.document?.outline)
        // In page order, named for their pages.
        #expect(outline.map(\.title) == ["Page 1", "Page 3"])
        #expect(outline.map(\.targetPage) == [0, 2])
        #expect(vm.isDocumentEdited)
        #expect(vm.outlineRevision == 2)

        let first = outline[0]
        vm.promptToAddOutlineEntry(near: first, asChild: true)
        vm.renameOutlineEntry(try #require(vm.document?.outline.first), to: "Introduction")
        let renamed = try #require(vm.document?.outline)
        #expect(renamed[0].title == "Introduction" && renamed[0].children.map(\.title) == ["Page 1"])

        // The child can come out, then go back in.
        let child = renamed[0].children[0]
        #expect(vm.canMoveOutlineEntry(child, .outdent) && !vm.canMoveOutlineEntry(child, .indent))
        vm.moveOutlineEntry(child, .outdent)
        #expect(vm.document?.outline.map(\.title) == ["Introduction", "Page 1", "Page 3"])
        let moved = try #require(vm.document?.outline[1])
        vm.moveOutlineEntry(moved, .indent)
        #expect(vm.document?.outline.map(\.title) == ["Introduction", "Page 3"])
        vm.moveOutlineEntry(try #require(vm.document?.outline[1]), .up)
        #expect(vm.document?.outline.map(\.title) == ["Page 3", "Introduction"])
        #expect(!vm.canMoveOutlineEntry(try #require(vm.document?.outline[0]), .up))

        vm.deleteOutlineEntry(try #require(vm.document?.outline[1]))
        #expect(vm.document?.outline.map(\.title) == ["Page 3"])

        vm.saveDocument()
        let reopened = try PDFDocumentCore(filePath: url.path)
        #expect(reopened.outline.map(\.title) == ["Page 3"])
    }
}
