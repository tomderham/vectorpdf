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
import Testing
@testable import PDFEngine

/// What's open in the outline stays open when the sidebar shows another tab and comes back,
/// and when the outline's own search is cleared.
@MainActor
struct OutlineExpansionTests {

    /// Part A ▸ Chapter 1 ▸ Section 1.1, Chapter 2 ▸ Section 2.2; Part B ▸ Chapter 3 ▸ Section 3.3.
    let outline = [
        PDFOutlineNode(title: "Part A", targetPage: 0, children: [
            PDFOutlineNode(title: "Chapter 1", targetPage: 0, children: [
                PDFOutlineNode(title: "Section 1.1", targetPage: 1),
            ]),
            PDFOutlineNode(title: "Chapter 2", targetPage: 2, children: [
                PDFOutlineNode(title: "Section 2.2", targetPage: 3),
            ]),
        ]),
        PDFOutlineNode(title: "Part B", targetPage: 4, children: [
            PDFOutlineNode(title: "Chapter 3", targetPage: 4, children: [
                PDFOutlineNode(title: "Section 3.3", targetPage: 5),
            ]),
        ]),
    ]
    let identity = "/Users/example/Book.pdf#0#0"

    /// An outline in the sidebar, as `PDFOutlineNSView.makeNSView` sets it up.
    @MainActor final class Sidebar {
        let coordinator: PDFOutlineNSView.Coordinator
        let outlineView = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))

        init(viewModel: PDFViewerViewModel) {
            coordinator = PDFOutlineNSView.Coordinator(viewModel: viewModel, onSelect: { _ in })
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OutlineColumn"))
            outlineView.addTableColumn(column)
            outlineView.outlineTableColumn = column
            outlineView.dataSource = coordinator
            outlineView.delegate = coordinator
            coordinator.outlineView = outlineView
        }

        /// The titles of the entries open in it.
        var openTitles: Set<String> {
            Set((0..<outlineView.numberOfRows).compactMap { row in
                let item = outlineView.item(atRow: row)
                guard let wrapper = item as? OutlineItemWrapper, outlineView.isItemExpanded(wrapper) else { return nil }
                return wrapper.node.title
            })
        }

        func open(_ title: String) {
            for row in 0..<outlineView.numberOfRows {
                if let wrapper = outlineView.item(atRow: row) as? OutlineItemWrapper, wrapper.node.title == title {
                    outlineView.expandItem(wrapper)
                }
            }
        }
    }

    /// Lets the outline view show what was last built, which it does on the next turn of the main queue.
    private func settle() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func show(_ sidebar: Sidebar, query: String = "", page: Int = 0) async {
        sidebar.coordinator.updateState(outline: outline, documentIdentity: identity, searchQuery: query, currentPage: page)
        await settle()
    }

    @Test func outlineKeepsWhatWasOpenAfterAnotherTab() async {
        let viewModel = PDFViewerViewModel()
        let first = Sidebar(viewModel: viewModel)
        await show(first)
        #expect(first.openTitles == ["Part A", "Part B"])
        first.open("Chapter 2")

        // The Search tab replaces the outline; a result in Section 3.3, on page 5, is shown.
        first.coordinator.saveOpenEntries()
        let second = Sidebar(viewModel: viewModel)
        await show(second, page: 5)

        // Chapter 2 is still open, and so is Chapter 3, to show where the result was.
        #expect(second.openTitles == ["Part A", "Chapter 2", "Part B", "Chapter 3"])
    }

    @Test func anotherFileStartsWithItsOwnOutline() async {
        let viewModel = PDFViewerViewModel()
        let first = Sidebar(viewModel: viewModel)
        await show(first)
        first.open("Chapter 1")
        first.coordinator.saveOpenEntries()

        let second = Sidebar(viewModel: viewModel)
        second.coordinator.updateState(outline: outline, documentIdentity: "/Users/example/Other.pdf#0#0", searchQuery: "", currentPage: 0)
        await settle()
        #expect(second.openTitles == ["Part A", "Part B"])
    }

    @Test func clearingTheOutlineSearchOpensWhatWasOpenBefore() async {
        let viewModel = PDFViewerViewModel()
        let sidebar = Sidebar(viewModel: viewModel)
        await show(sidebar)
        sidebar.open("Chapter 2")

        sidebar.coordinator.updateState(outline: outline, documentIdentity: identity, searchQuery: "Section 3", currentPage: 0)
        try? await Task.sleep(nanoseconds: 200_000_000)
        await settle()
        #expect(sidebar.openTitles == ["Part B", "Chapter 3"])

        await show(sidebar)
        #expect(sidebar.openTitles == ["Part A", "Chapter 2", "Part B"])
    }

    @Test func leavingDuringAnOutlineSearchKeepsWhatWasOpenBeforeIt() async {
        let viewModel = PDFViewerViewModel()
        let first = Sidebar(viewModel: viewModel)
        await show(first)
        first.open("Chapter 1")

        first.coordinator.updateState(outline: outline, documentIdentity: identity, searchQuery: "Section", currentPage: 0)
        try? await Task.sleep(nanoseconds: 200_000_000)
        await settle()
        first.coordinator.saveOpenEntries()

        // Back with the search still in the box, then cleared.
        let second = Sidebar(viewModel: viewModel)
        await show(second, query: "Section")
        await show(second)
        #expect(second.openTitles == ["Part A", "Chapter 1", "Part B"])
    }
}
