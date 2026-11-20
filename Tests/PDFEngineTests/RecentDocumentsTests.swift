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

import AppKit
import Foundation
import Testing
@testable import PDFEngine

@MainActor struct RecentDocumentsTests {
    private let suiteName = "RecentDocumentsTests-\(UUID().uuidString)"
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("RecentDocumentsTests-\(UUID().uuidString)", isDirectory: true)

    private func makeFiles(_ names: [String]) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return names.map { name in
            let url = directory.appendingPathComponent(name)
            createSamplePDF(at: url)
            return url
        }
    }

    private func makeList(limit: Int = 10) throws -> RecentDocuments {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return RecentDocuments(defaults: defaults, importingFrom: nil, maximumCount: { limit })
    }

    private func cleanUp() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

    @Test func listsMostRecentFirstWithoutDuplicates() throws {
        defer { cleanUp() }
        let files = try makeFiles(["a.pdf", "b.pdf", "c.pdf"])
        let recents = try makeList()
        files.forEach(recents.note)
        recents.note(files[0])
        #expect(names(recents.urls) == ["a.pdf", "c.pdf", "b.pdf"])
    }

    @Test func keepsToTheSystemLimit() throws {
        defer { cleanUp() }
        let files = try makeFiles(["a.pdf", "b.pdf", "c.pdf"])
        let recents = try makeList(limit: 2)
        files.forEach(recents.note)
        #expect(names(recents.urls) == ["c.pdf", "b.pdf"])
        // Recent items turned off in System Settings.
        #expect(try makeList(limit: 0).urls.isEmpty)
    }

    @Test func followsMovedFilesAndDropsDeletedOnes() throws {
        defer { cleanUp() }
        let files = try makeFiles(["a.pdf", "b.pdf"])
        let recents = try makeList()
        files.forEach(recents.note)

        let moved = directory.appendingPathComponent("moved.pdf")
        try FileManager.default.moveItem(at: files[0], to: moved)
        try FileManager.default.removeItem(at: files[1])
        #expect(names(recents.urls) == ["moved.pdf"])
    }

    @Test func clears() throws {
        defer { cleanUp() }
        let files = try makeFiles(["a.pdf"])
        let recents = try makeList()
        recents.note(files[0])
        recents.clear()
        #expect(recents.urls.isEmpty)
        // Cleared is not the same as never set: nothing is imported again.
        #expect(try makeList().urls.isEmpty)
    }

    @Test func persists() throws {
        defer { cleanUp() }
        let files = try makeFiles(["a.pdf", "b.pdf"])
        files.forEach(try makeList().note)
        #expect(names(try makeList().urls) == ["b.pdf", "a.pdf"])
    }
}
