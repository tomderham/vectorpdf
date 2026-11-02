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

@Suite("Tour document")
struct TourDocumentTests {
    private var tourURL: URL {
        get throws { try #require(TourDocument.bundledURL) }
    }

    /// The tour promises a fitted preview for each kind of target, which depends on the names
    /// `Scripts/make_tour_pdf.py` gives its destinations.
    @Test func firstPageLinksReachEachKindOfTarget() throws {
        let doc = try PDFDocumentCore(filePath: tourURL.path)
        let links = doc.loadLinks(for: 0)
        let kinds = Set(links.map { LinkTargetKind(uri: $0.uri, outlineDestinationKeys: []) })
        #expect(kinds == [.equation, .figure, .table, .heading, .citation])
        for link in links {
            let uri = try #require(link.uri)
            let target = try #require(doc.resolveLinkDestination(uri: uri))
            #expect(target.page > 0)
        }
    }

    /// "End to end" appears three ways on the first page: with hyphens, with spaces, and broken
    /// across two lines. The first is the tour's own instruction to search for it.
    @Test func smartSearchFindsEveryFormTheTourPromises() async throws {
        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: tourURL.path)
        let matches = try await actor.search(query: "end to end", options: SearchOptions())
        #expect(matches.count == 3)
    }

    @Test func installedCopyIsWritableAndKeepsTheReadersChanges() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        try Data("original".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: source.path)
        let installDirectory = directory.appendingPathComponent("support/VectorPDF")

        let copy = try TourDocument.installedCopy(of: source, in: installDirectory)
        #expect(FileManager.default.isWritableFile(atPath: copy.path))

        try Data("marked up".utf8).write(to: copy)
        let again = try TourDocument.installedCopy(of: source, in: installDirectory)
        #expect(try String(contentsOf: again, encoding: .utf8) == "marked up")
    }
}
