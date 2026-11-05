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
import SwiftUI
import Testing
@testable import PDFEngine

@MainActor
@Suite(.serialized)
struct RecentSearchTests {

    private func match(page: Int) -> SearchResult {
        SearchResult(pageIndex: page, matchedText: "x", snippet: "x", highlightQuads: [])
    }

    /// Puts `query` in the field with one result, as a finished search would, and goes to it.
    private func search(_ query: String, in vm: PDFViewerViewModel) {
        vm.searchQuery = query
        vm.searchResults = [match(page: 0)]
        vm.navigateToMatch(at: 0)
    }

    private func forgetStoredState(for url: URL) {
        ReadingStateManager.shared.updateState(for: url.path, lastPageIndex: 0, zoomScale: 1, snapshots: [], recentSearches: [])
    }

    @Test func addingMovesTheQueryToTheFrontAndDropsCaseDuplicates() {
        var list: [String] = []
        list = ReadingStateManager.addingRecentSearch("alpha", to: list)
        list = ReadingStateManager.addingRecentSearch("  bravo  ", to: list)
        list = ReadingStateManager.addingRecentSearch("Alpha", to: list)
        list = ReadingStateManager.addingRecentSearch("   ", to: list)
        #expect(list == ["Alpha", "bravo"])
    }

    @Test func theListKeepsOnlyTheMostRecentTen() {
        var list: [String] = []
        for i in 1...15 {
            list = ReadingStateManager.addingRecentSearch("term \(i)", to: list)
        }
        #expect(list.count == ReadingStateManager.maxRecentSearches)
        #expect(list.first == "term 15")
        #expect(list.last == "term 6")
    }

    @Test func stateSavedBeforeRecentSearchesExistedStillDecodes() throws {
        let json = #"{"lastPageIndex":3,"zoomScale":1.5,"snapshots":[]}"#
        let state = try JSONDecoder().decode(DocumentReadingState.self, from: Data(json.utf8))
        #expect(state.lastPageIndex == 3)
        #expect(state.recentSearches == nil)
    }

    @Test func typingWithoutGoingToAMatchRecordsNothing() {
        let vm = PDFViewerViewModel()
        for prefix in ["t", "th", "the"] {
            vm.searchQuery = prefix
            vm.searchResults = [match(page: 0)]
        }
        #expect(vm.recentSearches.isEmpty)

        vm.nextSearchMatch()
        #expect(vm.recentSearches == ["the"])
        // Stepping through more matches doesn't add it again.
        vm.searchResults = [match(page: 0), match(page: 1)]
        vm.nextSearchMatch()
        #expect(vm.recentSearches == ["the"])
    }

    @Test func recentSearchesAreKeptWithTheDocumentAndSharedWithItsOtherTabs() async throws {
        let dir = try makeScratchDirectory()
        let url = dir.appendingPathComponent("recents.pdf")
        defer {
            forgetStoredState(for: url)
            try? FileManager.default.removeItem(at: dir)
        }
        createSamplePDF(at: url)

        let first = PDFViewerViewModel()
        await first.loadDocument(from: url.path)
        let second = PDFViewerViewModel()
        await second.loadDocument(from: url.path)

        search("beam", in: first)
        search("column", in: first)
        #expect(first.recentSearches == ["column", "beam"])
        #expect(second.recentSearches == ["column", "beam"])

        // Saving the reading position (page changes, closing) leaves them alone.
        first.saveReadingStateIfNeeded()
        let reopened = PDFViewerViewModel()
        await reopened.loadDocument(from: url.path)
        #expect(reopened.recentSearches == ["column", "beam"])

        second.clearRecentSearches()
        #expect(first.recentSearches.isEmpty)
        #expect(ReadingStateManager.shared.state(for: url.path)?.recentSearches == nil)
    }

    @Test func choosingARecentSearchRunsItAndGoesToAMatch() async throws {
        let dir = try makeScratchDirectory()
        let url = dir.appendingPathComponent("choose.pdf")
        defer {
            forgetStoredState(for: url)
            try? FileManager.default.removeItem(at: dir)
        }
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo", "Charlie"])

        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        vm.selectRecentSearch("Charlie")
        let deadline = Date().addingTimeInterval(10)
        while vm.isSearching || !vm.hasNavigatedToActiveSearchMatch, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(vm.currentPageIndex == 2)
        #expect(vm.recentSearches == ["Charlie"])
    }

    @Test func redactingClearsTheDocumentsRecentSearches() async throws {
        let dir = try makeScratchDirectory()
        let url = dir.appendingPathComponent("redact.pdf")
        defer {
            forgetStoredState(for: url)
            try? FileManager.default.removeItem(at: dir)
        }
        createSamplePDF(at: url)

        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        search("secret", in: vm)
        #expect(ReadingStateManager.shared.state(for: url.path)?.recentSearches == ["secret"])

        vm.finalizeRedactionChanges(affectedPages: [0])
        #expect(vm.recentSearches.isEmpty)
        #expect(ReadingStateManager.shared.state(for: url.path)?.recentSearches == nil)
        vm.cleanupWorkingCopy()
    }

    @Test func theSearchFieldMenuListsRecentsAndClears() {
        var query = ""
        var chosen: String?
        var cleared = false
        let rep = NativeSearchField(
            text: Binding(get: { query }, set: { query = $0 }),
            onCommit: {},
            recents: ["beam", "column"],
            onSelectRecent: { chosen = $0 },
            onClearRecents: { cleared = true }
        )
        let coordinator = rep.makeCoordinator()
        let field = NSSearchField(frame: .zero)
        coordinator.updateRecentsMenu(on: field)

        let menu = try! #require(field.searchMenuTemplate)
        let titles = menu.items.map(\.title)
        #expect(titles == ["Recent Searches", "beam", "column", "", "Clear Recent Searches"])

        coordinator.selectRecent(menu.items[2])
        #expect(chosen == "column")
        coordinator.clearRecents(menu.items[4])
        #expect(cleared)

        let empty = NativeSearchField(text: .constant(""), onCommit: {})
        let emptyCoordinator = empty.makeCoordinator()
        emptyCoordinator.updateRecentsMenu(on: field)
        #expect(field.searchMenuTemplate == nil)
    }
}
