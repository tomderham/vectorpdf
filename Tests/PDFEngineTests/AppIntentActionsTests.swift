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

import Testing
import Foundation
@testable import PDFEngine

/// The Shortcuts actions' work (Sources/VectorPDF/AppIntents.swift calls these).
@Suite struct PageRangeListTests {
    @Test func parsesPagesAndRangesInTheOrderGiven() throws {
        #expect(try PageRangeList.parse("1-3, 5", pageCount: 8) == [1, 2, 3, 5])
        #expect(try PageRangeList.parse("7, 2", pageCount: 8) == [7, 2])
        #expect(try PageRangeList.parse(" 4 – 6 ;8", pageCount: 8) == [4, 5, 6, 8])
    }

    @Test func aBackwardRangeRunsBackwardAndAnOpenRangeRunsToTheEnd() throws {
        #expect(try PageRangeList.parse("3-1", pageCount: 8) == [3, 2, 1])
        #expect(try PageRangeList.parse("6-", pageCount: 8) == [6, 7, 8])
    }

    @Test func rejectsWhatIsntAPageList() {
        for text in ["", "abc", "0", "1-2-3", "-3", "2-x", ","] {
            #expect(throws: AppIntentActions.Failure.invalidPageRange(text)) {
                try PageRangeList.parse(text, pageCount: 8)
            }
        }
    }

    @Test func rejectsPagesPastTheEnd() {
        #expect(throws: AppIntentActions.Failure.pageOutOfRange(page: 9, pageCount: 8)) {
            try PageRangeList.parse("2, 7-9", pageCount: 8)
        }
    }

    @Test func describesARangeForAFileName() {
        #expect(PageRangeList.describe("1 -3,5") == "1-3, 5")
        #expect(PageRangeList.describe("6-") == "6-")
    }
}

@MainActor
@Suite struct AppIntentActionsTests {
    @Test func extractsTheListedPagesToANewPDF() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Report.pdf")
        makeLabelledPDF(at: source, labels: natoLabels)

        let output = try await AppIntentActions.extractPages(path: source.path, ranges: "6-7, 2")
        defer { try? FileManager.default.removeItem(at: output.deletingLastPathComponent()) }
        #expect(output.lastPathComponent == "Report (Pages 6-7, 2).pdf")
        #expect(try pageLabels(ofFileAt: output, among: natoLabels) == ["Foxtrot", "Golf", "Bravo"])
        // The source is untouched.
        #expect(try pageLabels(ofFileAt: source, among: natoLabels) == natoLabels)
    }

    @Test func extractingPastTheLastPageFails() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Short.pdf")
        makeLabelledPDF(at: source, labels: ["Alpha", "Bravo"])
        await #expect(throws: AppIntentActions.Failure.pageOutOfRange(page: 3, pageCount: 2)) {
            _ = try await AppIntentActions.extractPages(path: source.path, ranges: "3")
        }
    }

    @Test func aMissingFileIsReportedByName() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_missing_\(UUID().uuidString).pdf").path
        await #expect(throws: AppIntentActions.Failure.fileNotFound((path as NSString).lastPathComponent)) {
            _ = try await AppIntentActions.extractPages(path: path, ranges: "1")
        }
    }

    @Test func searchesAFileThatIsntOpen() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Labels.pdf")
        makeLabelledPDF(at: source, labels: natoLabels)

        let found = try await AppIntentActions.search(path: source.path, query: "golf")
        #expect(found.total == 1)
        #expect(found.hits.map(\.pageNumber) == [7])
        #expect(found.hits.first?.summary.hasPrefix("Page 7: ") == true)

        let matchingCase = try await AppIntentActions.search(path: source.path, query: "golf", matchCase: true)
        #expect(matchingCase.total == 0)
    }

    @Test func searchListsAtMostTheLimitButCountsEveryMatch() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Repeats.pdf")
        makeLabelledPDF(at: source, labels: Array(repeating: "Kilo", count: 5))

        let found = try await AppIntentActions.search(path: source.path, query: "Kilo", limit: 2)
        #expect(found.total == 5)
        #expect(found.hits.map(\.pageNumber) == [1, 2])
    }

    @Test func anEmptySearchFindsNothing() async throws {
        let found = try await AppIntentActions.search(path: "/nonexistent.pdf", query: "  ")
        #expect(found.total == 0 && found.hits.isEmpty)
    }
}
