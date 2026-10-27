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

@MainActor
@Suite(.serialized)
struct AnchorTests {

    /// Opens `url` in a fresh view model, as a new window would, restoring its stored anchors.
    private func open(_ url: URL) async -> PDFViewerViewModel {
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        return vm
    }

    private func forgetStoredState(for url: URL) {
        ReadingStateManager.shared.updateState(for: url.path, lastPageIndex: 0, zoomScale: 1, snapshots: [])
    }

    @Test func anchorsAreRestoredWhenTheDocumentIsOpenedAgain() async throws {
        let dir = try makeScratchDirectory()
        let url = dir.appendingPathComponent("anchors.pdf")
        defer {
            forgetStoredState(for: url)
            try? FileManager.default.removeItem(at: dir)
        }
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo", "Charlie"])

        let first = await open(url)
        first.addSnapshotTarget(SnapshotTarget(label: "Intro", snippet: "Alpha", targetPage: 0, targetPoint: CGPoint(x: 72, y: 100)))
        first.addSnapshotTarget(SnapshotTarget(label: "Details", snippet: "Charlie", targetPage: 2, targetPoint: CGPoint(x: 72, y: 100)))

        let second = await open(url)
        #expect(second.activeSnapshots.map(\.label) == ["Intro", "Details"])
        #expect(second.activeSnapshots.map(\.targetPage) == [0, 2])
        #expect(second.activeSnapshots.map(\.id) == first.activeSnapshots.map(\.id))

        // Removing one, then clearing the rest, is remembered the same way.
        let details = try #require(second.activeSnapshots.last)
        second.removeSnapshotTarget(details)
        #expect(await open(url).activeSnapshots.map(\.label) == ["Intro"])
        second.clearAllSnapshots()
        #expect(await open(url).activeSnapshots.isEmpty)
    }

    /// Snapshot and reference windows show one spot of a document; anchors made there must not
    /// overwrite the document's own list.
    @Test func transientWindowsNeitherLoadNorStoreAnchors() async throws {
        let dir = try makeScratchDirectory()
        let url = dir.appendingPathComponent("transient.pdf")
        defer {
            forgetStoredState(for: url)
            try? FileManager.default.removeItem(at: dir)
        }
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo"])

        let main = await open(url)
        main.addSnapshotTarget(SnapshotTarget(label: "Kept", targetPage: 1))

        let transient = PDFViewerViewModel()
        transient.isTransientWindow = true
        await transient.loadDocument(from: url.path)
        #expect(transient.activeSnapshots.isEmpty)
        transient.addSnapshotTarget(SnapshotTarget(label: "Scratch", targetPage: 0))

        #expect(await open(url).activeSnapshots.map(\.label) == ["Kept"])
    }

    @Test func duplicateAnchorsAreIgnored() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("dupes.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo"])

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        let anchor = SnapshotTarget(label: "Spec clause", snippet: "Alpha", targetPage: 0)
        vm.addSnapshotTarget(anchor)
        vm.addSnapshotTarget(anchor)                                                        // same anchor
        vm.addSnapshotTarget(SnapshotTarget(label: "Again", snippet: "Alpha", targetPage: 0))  // same text, same page
        vm.addSnapshotTarget(SnapshotTarget(label: "Elsewhere", snippet: "Alpha", targetPage: 1))
        // Without text, the label stands in for it: different labels on one page are kept.
        vm.addSnapshotTarget(SnapshotTarget(label: "Point 1", targetPage: 1))
        vm.addSnapshotTarget(SnapshotTarget(label: "Point 2", targetPage: 1))
        #expect(vm.activeSnapshots.map(\.label) == ["Spec clause", "Elsewhere", "Point 1", "Point 2"])
        #expect(vm.selectedSnapshotId == vm.activeSnapshots.last?.id)
    }

    /// Cmd-D with text selected anchors that text, labelled with its first words and pointing at
    /// its first line; without a selection it anchors the current page.
    @Test func quickAnchorUsesTheSelectionWhenThereIsOne() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("quick.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha section heading", "Bravo"])

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        let page = try #require(vm.document?.loadStructuredPage(for: 0))
        let selection = SpatialTextSelector().selectText(on: page, from: CGPoint(x: 60, y: 90), to: CGPoint(x: 560, y: 125))
        vm.activeSelection = (pageIndex: 0, result: selection)

        vm.addAnchorForCurrentPage()
        let fromSelection = try #require(vm.activeSnapshots.first)
        #expect(fromSelection.label == "Alpha section heading")
        #expect(fromSelection.snippet.contains("Alpha section heading"))
        #expect(fromSelection.targetPage == 0)
        let rect = try #require(fromSelection.targetRect)
        #expect(rect.minY > 80 && rect.maxY < 130)   // the selected line, not the whole page

        vm.activeSelection = nil
        vm.currentPageIndex = 1
        vm.addAnchorForCurrentPage()
        #expect(vm.activeSnapshots.count == 2)
        #expect(vm.activeSnapshots.last?.targetPage == 1)
    }

    @Test func jumpingToAnAnchorGoesToItsPageAndSelectsIt() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("jump.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo", "Charlie"])

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        let anchor = SnapshotTarget(label: "Charlie", targetPage: 2, targetPoint: CGPoint(x: 72, y: 100))
        vm.addSnapshotTarget(anchor)
        vm.currentPageIndex = 0

        vm.jumpToSnapshot(anchor)
        #expect(vm.currentPageIndex == 2)
        #expect(vm.selectedSnapshotId == anchor.id)
        #expect(vm.activeSnapshotTarget?.id == anchor.id)
        // Removing the selected anchor clears the selection rather than leaving it dangling.
        vm.removeSnapshotTarget(anchor)
        #expect(vm.selectedSnapshotId == nil)
    }
}

/// Snapshot (child) windows: one per target, closed along with the document window they came
/// from — including windows opened from another child — and never another document's. The
/// manager is shared with other suites running at the same time, so each test closes only the
/// windows it opened.
@MainActor
@Suite(.serialized)
struct ChildWindowTests {

    private func makeDocumentWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test(.showsWindows) func openingATargetTwiceReusesItsWindow() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("child.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo"])
        let manager = SnapshotWindowManager.shared
        let parent = makeDocumentWindow()
        let target = SnapshotTarget(label: "Figure 3", targetPage: 1)
        defer { manager.close(target.id); parent.close() }

        let countBefore = manager.openWindowCount
        manager.open(url: url, target: target, source: parent)
        manager.open(url: url, target: target, source: parent)
        #expect(manager.openWindowCount == countBefore + 1)

        let child = try #require(manager.windows(openedFrom: [parent]).first)
        #expect(child.representedURL?.lastPathComponent == "child.pdf")
        #expect(child.miniwindowTitle == "Figure 3")
        // The hosted view settles the title once it loads; it must keep the snapshot's label.
        for _ in 0..<50 {
            try await Task.sleep(nanoseconds: 20_000_000)
            if manager.isOpen(target.id) && child.contentViewController != nil && !child.title.isEmpty { break }
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(child.title == "child.pdf — Figure 3")
        #expect(child.tabbingMode == .disallowed)
        #expect(child.isExcludedFromWindowsMenu)

        manager.close(target.id)
        #expect(!manager.isOpen(target.id))
        #expect(manager.windows(openedFrom: [parent]).isEmpty)
    }

    @Test(.showsWindows) func windowsOpenedFromAChildCloseWithTheDocumentWindow() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("grandchild.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo"])
        let manager = SnapshotWindowManager.shared
        let parent = makeDocumentWindow()
        let child = SnapshotTarget(label: "Table 1", targetPage: 0)
        let grandchild = SnapshotTarget(label: "Ref [4]", targetPage: 1)
        defer { manager.close(child.id); manager.close(grandchild.id); parent.close() }
        manager.open(url: url, target: child, source: parent)
        let childWindow = try #require(manager.windows(openedFrom: [parent]).first)
        manager.open(url: url, target: grandchild, source: childWindow)

        // Both count as the document window's, so the Dock menu and close sweep find them.
        #expect(manager.windows(openedFrom: [parent]).count == 2)

        parent.close()
        #expect(!manager.isOpen(child.id))
        #expect(!manager.isOpen(grandchild.id))
    }

    @Test(.showsWindows) func closingOneDocumentsChildrenLeavesAnothersOpen() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("two_docs.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo"])
        let manager = SnapshotWindowManager.shared
        let firstDoc = makeDocumentWindow()
        let secondDoc = makeDocumentWindow()
        let first = SnapshotTarget(label: "From first", targetPage: 0)
        let sibling = SnapshotTarget(label: "Also from first", targetPage: 1)
        let second = SnapshotTarget(label: "From second", targetPage: 0)
        defer {
            for target in [first, sibling, second] { manager.close(target.id) }
            firstDoc.close()
            secondDoc.close()
        }
        manager.open(url: url, target: first, source: firstDoc)
        manager.open(url: url, target: sibling, source: firstDoc)
        manager.open(url: url, target: second, source: secondDoc)

        // "Close snapshot windows" invoked from one child closes it and its siblings only.
        let firstChild = try #require(manager.windows(openedFrom: [firstDoc]).first)
        manager.closeChildrenOfCurrentParent(for: firstChild)
        #expect(!manager.isOpen(first.id))
        #expect(!manager.isOpen(sibling.id))
        #expect(manager.isOpen(second.id))
        #expect(manager.windows(openedFrom: [secondDoc]).count == 1)
    }
}
