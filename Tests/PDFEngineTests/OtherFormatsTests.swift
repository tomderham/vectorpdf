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

/// EPUB, XPS, CBZ and FB2 documents, which MuPDF reads but can't save.
@MainActor
@Suite(.serialized)
struct OtherFormatsTests {
    private func open(_ name: String) async throws -> PDFViewerViewModel {
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: Fixture.url(name).path)
        try #require(vm.document != nil, "\(name) didn't open")
        return vm
    }

    @Test(arguments: [
        ("sample.epub", ["The Mill", "The Barges", "Zanzibar Harbour"]),
        ("sample.fb2", ["The Mill", "The Barges"]),
        ("sample.cbz", []),
        ("sample.xps", []),
    ])
    func opensForReading(name: String, outline: [String]) async throws {
        let vm = try await open(name)
        let doc = try #require(vm.document)
        #expect(!doc.isPDF)
        #expect(vm.isReadOnlyDocument)
        #expect(doc.pageCount > 1)
        #expect(doc.outline.map(\.title) == outline)
        #expect(doc.pageLabels == nil)
        #expect(doc.renderPageRect(pageIndex: 1, rect: doc.pageBounds[1], scale: 1) != nil)
    }

    /// E-books are laid out into pages, whose text can be selected and searched like a PDF's.
    @Test func eBookTextIsSearchable() async throws {
        let epub = try await open("sample.epub")
        let hits = await epub.searchWholeDocument("Zanzibar Harbour")
        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { $0.pageIndex > 0 && !$0.highlightQuads.isEmpty })
        #expect(epub.document?.loadStructuredPage(for: 0)?.plainText.contains("The river ran past the mill") == true)

        let fb2 = try await open("sample.fb2")
        #expect(await !fb2.searchWholeDocument("barges came down").isEmpty)
    }

    /// Nothing that writes to the file can be turned on, and Save leaves the file alone.
    @Test func editingIsUnavailable() async throws {
        let vm = try await open("sample.epub")
        let path = try #require(vm.document?.filePath)
        let before = try Data(contentsOf: URL(fileURLWithPath: path))

        vm.isMarkupBarVisible = true
        vm.toggleMeasurementBar()
        vm.toggleRedactionBar()
        #expect(!vm.isMarkupBarVisible && !vm.isMeasurementBarVisible && !vm.isRedactionBarVisible)
        vm.canvasMode = .draw
        #expect(vm.canvasMode == .select)
        #expect(vm.addNoteAnnotation(pageIndex: 0, at: CGPoint(x: 100, y: 100), text: "No") == nil)
        vm.rotatePage(0)
        vm.deletePage(0)
        vm.saveDocument()

        #expect(!vm.isDocumentEdited)
        #expect(vm.document?.pageCount ?? 0 > 1)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
        #expect(!vm.hasAnnotationThreads)
    }

    /// A window that had the Markup toolbar open for a PDF closes it for an e-book.
    @Test func openingAnEBookClosesTheEditingToolbars() async throws {
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: Fixture.lcmsTutorial.path)
        vm.isMarkupBarVisible = true
        vm.canvasMode = .draw
        #expect(vm.isMarkupBarVisible && !vm.isReadOnlyDocument)

        await vm.loadDocument(from: Fixture.url("sample.cbz").path)
        #expect(vm.isReadOnlyDocument)
        #expect(!vm.isMarkupBarVisible)
        #expect(vm.canvasMode == .select)
    }

    @Test func openableTypes() {
        for name in ["a.pdf", "b.EPUB", "c.xps", "d.oxps", "e.cbz", "f.fb2"] {
            #expect(OpenableDocumentTypes.canOpen(URL(fileURLWithPath: "/Users/example/\(name)")))
        }
        #expect(!OpenableDocumentTypes.canOpen(URL(fileURLWithPath: "/Users/example/notes.txt")))
        #expect(OpenableDocumentTypes.contentTypes.contains(.epub))
    }
}
