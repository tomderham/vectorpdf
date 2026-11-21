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
import SwiftUI
import Testing
@testable import PDFEngine

/// Search can move to the column on the window's right, which it shares with the Inspector, and
/// each document keeps the side it was last moved to.
@Suite(.serialized)
struct SearchPlacementTests {

    @MainActor
    private func open(_ url: URL) async -> PDFViewerViewModel {
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        return vm
    }

    private func labelledPDF(pages: Int) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_searchside_\(UUID().uuidString).pdf")
        makeLabelledPDF(at: url, labels: (1...pages).map { "Page\($0)" })
        return url
    }

    @MainActor
    @Test func eachDocumentKeepsTheSideSearchWasMovedTo() async {
        let moved = labelledPDF(pages: 3), other = labelledPDF(pages: 3)
        defer { [moved, other].forEach { try? FileManager.default.removeItem(at: $0) } }

        let vm = await open(moved)
        #expect(!vm.isSearchOnRight)
        vm.moveSearch(toRight: true)
        #expect(vm.isSearchOnRight && vm.isRightSearchOnScreen && vm.isRightColumnShown)
        // Saving the reading position keeps it.
        vm.saveReadingStateIfNeeded()

        let reopened = await open(moved)
        #expect(reopened.isSearchOnRight && reopened.isRightSearchShown)
        #expect(!(await open(other)).isSearchOnRight)

        reopened.moveSearch(toRight: false)
        #expect(!reopened.isRightColumnShown)
        #expect(!(await open(moved)).isSearchOnRight)
    }

    @MainActor
    @Test func openingAnotherDocumentInTheWindowTakesItsSide() async {
        let moved = labelledPDF(pages: 3), other = labelledPDF(pages: 3)
        defer { [moved, other].forEach { try? FileManager.default.removeItem(at: $0) } }
        let vm = await open(moved)
        vm.moveSearch(toRight: true)
        await vm.loadDocument(from: other.path)
        #expect(!vm.isSearchOnRight && !vm.isRightColumnShown)
    }

    @MainActor
    @Test func searchAndTheInspectorShareTheRightColumn() async {
        let url = labelledPDF(pages: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let vm = await open(url)
        vm.isTransientWindow = true   // keeps the moves out of the stored state
        vm.moveSearch(toRight: true)
        #expect(!vm.isRightColumnShared)

        // Opening the Inspector puts it in front.
        vm.toggleInspector()
        #expect(vm.isRightColumnShared && vm.isInspectorOnScreen && !vm.isRightSearchOnScreen)
        // Find brings Search forward, and then the Inspector command brings the Inspector back
        // rather than closing it.
        vm.showRightSearch()
        #expect(vm.isRightSearchOnScreen && !vm.isInspectorOnScreen && vm.isInspectorVisible)
        vm.toggleInspector()
        #expect(vm.isInspectorOnScreen)
        // Closing the Inspector leaves Search.
        vm.toggleInspector()
        #expect(!vm.isInspectorVisible && vm.isRightSearchOnScreen)

        // Closing the column closes both; Search stays on the right for next time.
        vm.toggleInspector()
        vm.closeRightColumn()
        #expect(!vm.isRightColumnShown && vm.isSearchOnRight)
        vm.showRightSearch()
        #expect(vm.isRightSearchOnScreen)

        // Hiding Search leaves the Inspector.
        vm.toggleInspector()
        vm.closeRightSearch()
        #expect(vm.isInspectorOnScreen && !vm.isRightColumnShared)
        vm.showRightSearch()

        // Moving Search back leaves the Inspector on its own.
        vm.toggleInspector()
        vm.moveSearch(toRight: false)
        #expect(vm.isInspectorOnScreen && !vm.isRightColumnShared)
    }

    @MainActor
    @Test func twoPageModeHidesSearchOnTheRightAndBringsItBack() async {
        let url = labelledPDF(pages: 5)
        defer { try? FileManager.default.removeItem(at: url) }
        let vm = await open(url)
        vm.isTransientWindow = true
        vm.moveSearch(toRight: true)
        vm.toggleTwoPageMode()
        #expect(!vm.isRightColumnShown)
        vm.toggleTwoPageMode()
        #expect(vm.isRightSearchOnScreen)

        // Closed before, it stays closed after.
        vm.closeRightColumn()
        vm.toggleTwoPageMode()
        vm.toggleTwoPageMode()
        #expect(!vm.isRightColumnShown)
    }

    /// Moved right, the search field is in the column on the window's right and the sidebar
    /// stays open beside it. (Find itself needs the key window, which tests don't get.)
    @MainActor
    @Test(.showsWindows) func searchMovedRightShowsBesideTheSidebar() async throws {
        _ = NSApplication.shared
        let url = labelledPDF(pages: 5)
        defer { try? FileManager.default.removeItem(at: url) }
        let window = DocumentWindowing.makeWindow(for: url)
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        let viewModel = try #require((window.contentViewController as? NSHostingController<PDFViewerMainView>)?.rootView.viewModel)
        for _ in 0..<50 where viewModel.document == nil { try await Task.sleep(for: .milliseconds(100)) }
        try await Task.sleep(for: .milliseconds(500))
        viewModel.isTransientWindow = true
        let content = try #require(window.contentView)
        func searchFields() -> [NSSearchField] {
            func collect(_ view: NSView) -> [NSSearchField] {
                ((view as? NSSearchField).map { [$0] } ?? []) + view.subviews.flatMap(collect)
            }
            return collect(content).filter { $0.placeholderString == "Search document..." && $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }
        }

        viewModel.moveSearch(toRight: true)
        try await Task.sleep(for: .milliseconds(800))
        #expect(viewModel.isSidebarVisible)
        let fields = searchFields()
        #expect(fields.count == 1)
        let field = try #require(fields.first)
        #expect(field.convert(field.bounds, to: nil).minX > content.bounds.midX)

        // Closed, Search comes back where it was.
        viewModel.closeRightColumn()
        try await Task.sleep(for: .milliseconds(500))
        #expect(searchFields().isEmpty)
        viewModel.showRightSearch()
        try await Task.sleep(for: .milliseconds(800))
        #expect(searchFields().count == 1)

        // Closed again, the sidebar's Search segment shows it on the right, not in the sidebar.
        viewModel.closeRightColumn()
        try await Task.sleep(for: .milliseconds(500))
        func segmentedControls(_ view: NSView) -> [NSSegmentedControl] {
            ((view as? NSSegmentedControl).map { [$0] } ?? []) + view.subviews.flatMap(segmentedControls)
        }
        let sidebarPicker = try #require(segmentedControls(content).first { $0.segmentCount > 2 && !$0.isHiddenOrHasHiddenAncestor })
        sidebarPicker.selectedSegment = 1
        _ = sidebarPicker.sendAction(sidebarPicker.action, to: sidebarPicker.target)
        try await Task.sleep(for: .milliseconds(800))
        #expect(viewModel.isRightSearchOnScreen)
        let reshown = try #require(searchFields().first)
        #expect(searchFields().count == 1)
        #expect(reshown.convert(reshown.bounds, to: nil).minX > content.bounds.midX)
        #expect(sidebarPicker.selectedSegment == 0)
    }

    /// Choosing an outline entry beside Search on the right scrolls the results list to that
    /// section's results, and leaves the current result alone.
    @MainActor
    @Test(.showsWindows) func choosingAnOutlineEntryScrollsTheResultsToIt() async throws {
        _ = NSApplication.shared
        let window = DocumentWindowing.makeWindow(for: Fixture.url("nist-tn-2255.pdf"))
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        let viewModel = try #require((window.contentViewController as? NSHostingController<PDFViewerMainView>)?.rootView.viewModel)
        for _ in 0..<50 where viewModel.document == nil { try await Task.sleep(for: .milliseconds(100)) }
        viewModel.isTransientWindow = true
        viewModel.moveSearch(toRight: true)
        viewModel.searchQuery = "the"
        viewModel.performSearch()
        for _ in 0..<100 where viewModel.isSearching || viewModel.searchResults.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        try await Task.sleep(for: .milliseconds(800))
        let content = try #require(window.contentView)
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
        }
        let results = try #require(scrollViews(content).first {
            !$0.isHiddenOrHasHiddenAncestor && $0.convert($0.bounds, to: nil).minX > content.bounds.midX
        })
        let startY = results.contentView.bounds.minY

        let groups = viewModel.searchSectionGroups
        let lastSection = try #require(groups.last?.section)
        let doc = try #require(viewModel.document)
        func find(_ nodes: [PDFOutlineNode]) -> PDFOutlineNode? {
            for node in nodes { if node.id == lastSection.nodeId { return node }; if let n = find(node.children) { return n } }
            return nil
        }
        let entry = try #require(find(doc.outline))
        let active = viewModel.activeSearchMatchIndex
        viewModel.revealSearchResults(in: entry)
        try await Task.sleep(for: .milliseconds(800))
        #expect(results.contentView.bounds.minY > startY + 100)
        #expect(viewModel.activeSearchMatchIndex == active)
    }
}
