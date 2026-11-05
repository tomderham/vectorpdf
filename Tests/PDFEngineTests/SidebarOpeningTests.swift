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

/// Whether the sidebar shows when a document opens: as the user last left it for that document,
/// or, the first time, unless the document is short and has nothing for the sidebar.
@Suite(.serialized)
struct SidebarOpeningTests {

    @MainActor
    @Test func theRuleForADocumentOpenedTheFirstTime() {
        func opening(_ pages: Int, outline: Bool = false, layers: Bool = false, annotations: Bool = false, attachments: Bool = false, saved: Bool? = nil) -> (Bool, SidebarOpeningTab) {
            let result = PDFViewerViewModel.sidebarOpening(pageCount: pages, hasOutline: outline, hasLayers: layers, hasAnnotations: annotations, hasAttachments: attachments, savedChoice: saved)
            return (result.isVisible, result.tab)
        }
        // Short and plain: hidden. Longer: shown.
        #expect(opening(1) == (false, .contents))
        #expect(opening(2) == (false, .contents))
        #expect(opening(3) == (true, .contents))
        // Short, with something for the sidebar: shown, on the tab that has it.
        #expect(opening(1, outline: true) == (true, .contents))
        #expect(opening(1, layers: true) == (true, .layers))
        #expect(opening(1, outline: true, layers: true) == (true, .contents))
        #expect(opening(2, annotations: true) == (true, .comments))
        #expect(opening(1, annotations: true, attachments: true) == (true, .attachments))
        // A long document opens on its contents, whatever it has.
        #expect(opening(40, annotations: true, attachments: true) == (true, .contents))
        // The user's own choice wins either way.
        #expect(opening(40, saved: false).0 == false)
        #expect(opening(1, saved: true).0 == true)
    }

    @MainActor
    private func open(_ url: URL) async -> PDFViewerViewModel {
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        return vm
    }

    private func labelledPDF(pages: Int) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_sidebar_\(UUID().uuidString).pdf")
        makeLabelledPDF(at: url, labels: (1...pages).map { "Page\($0)" })
        return url
    }

    @MainActor
    @Test func shortPlainDocumentsOpenWithoutTheSidebarAndLongerOnesWithIt() async {
        let short = labelledPDF(pages: 2), long = labelledPDF(pages: 3)
        defer { [short, long].forEach { try? FileManager.default.removeItem(at: $0) } }
        #expect(await open(short).isSidebarVisible == false)
        #expect(await open(long).isSidebarVisible == true)
    }

    @MainActor
    @Test func aShortDocumentWithAnnotationsOpensOnTheCommentsTab() async throws {
        let url = labelledPDF(pages: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let vm = await open(url)
            _ = try #require(vm.addNoteAnnotation(pageIndex: 0, at: CGPoint(x: 100, y: 100)))
            vm.saveDocument()
        }
        let vm = await open(url)
        #expect(vm.isSidebarVisible)
        #expect(vm.sidebarOpeningTab == .comments)
    }

    @MainActor
    @Test func aDocumentWithAttachmentsOpensOnTheAttachmentsTab() async {
        let vm = await open(Fixture.attachmentSample)
        #expect(vm.isSidebarVisible)
        #expect(vm.sidebarOpeningTab == .attachments)
    }

    @MainActor
    @Test func theSidebarOpensAsTheUserLastLeftItForThatDocument() async {
        let long = labelledPDF(pages: 5), short = labelledPDF(pages: 1)
        defer { [long, short].forEach { try? FileManager.default.removeItem(at: $0) } }

        let vm = await open(long)
        vm.isSidebarVisible = false
        vm.rememberSidebarChoice(false)
        // Saving the reading position keeps the choice.
        vm.saveReadingStateIfNeeded()
        #expect(await open(long).isSidebarVisible == false)

        let other = await open(short)
        other.isSidebarVisible = true
        other.rememberSidebarChoice(true)
        #expect(await open(short).isSidebarVisible == true)
        // Only for those documents: another long one still opens with it.
        let third = labelledPDF(pages: 4)
        defer { try? FileManager.default.removeItem(at: third) }
        #expect(await open(third).isSidebarVisible == true)
    }

    @MainActor
    @Test func twoPageModeHidesTheSidebarAndBringsItBackAsItWas() async {
        let url = labelledPDF(pages: 5)
        defer { try? FileManager.default.removeItem(at: url) }
        let vm = await open(url)
        vm.isTransientWindow = true   // keeps the toggles below out of the stored state
        #expect(vm.isSidebarVisible)
        vm.toggleTwoPageMode()
        #expect(!vm.isSidebarVisible)
        vm.toggleTwoPageMode()
        #expect(vm.isSidebarVisible)

        // Hidden before, it stays hidden after; rotating ends Two-Page Mode the same way.
        vm.isSidebarVisible = false
        vm.toggleTwoPageMode()
        vm.rotateClockwise()
        #expect(!vm.isTwoPageMode && !vm.isSidebarVisible)

        vm.isSidebarVisible = true
        vm.toggleTwoPageMode()
        vm.rotateClockwise()
        #expect(vm.isSidebarVisible)
    }

    /// The sidebar button (and View menu) send toggleSidebar: through the window, which SwiftUI
    /// sees as a change it didn't make: that's the choice kept for the document.
    @MainActor
    @Test(.showsWindows) func hidingTheSidebarInAWindowIsRememberedForTheDocument() async throws {
        _ = NSApplication.shared
        let url = labelledPDF(pages: 5)
        defer { try? FileManager.default.removeItem(at: url) }

        func openWindow() async throws -> (NSWindow, PDFViewerViewModel) {
            let window = DocumentWindowing.makeWindow(for: url)
            window.makeKeyAndOrderFront(nil)
            let viewModel = try #require((window.contentViewController as? NSHostingController<PDFViewerMainView>)?.rootView.viewModel)
            for _ in 0..<50 where viewModel.document == nil { try await Task.sleep(for: .milliseconds(100)) }
            try await Task.sleep(for: .milliseconds(500))
            return (window, viewModel)
        }

        let (window, viewModel) = try await openWindow()
        #expect(viewModel.isSidebarVisible)
        // As the sidebar button does: its split view controller toggles the sidebar.
        func splitViews(in view: NSView) -> [NSSplitView] {
            (view as? NSSplitView).map { [$0] } ?? [] + view.subviews.flatMap(splitViews)
        }
        let content = try #require(window.contentView)
        let controller = try #require(splitViews(in: content).lazy.compactMap { $0.delegate as? NSSplitViewController }.first)
        controller.toggleSidebar(nil)
        for _ in 0..<20 where viewModel.isSidebarVisible { try await Task.sleep(for: .milliseconds(100)) }
        #expect(!viewModel.isSidebarVisible)
        #expect(ReadingStateManager.shared.state(for: url.path)?.sidebarVisible == false)
        window.close()

        let (again, reopened) = try await openWindow()
        defer { again.close() }
        #expect(!reopened.isSidebarVisible)
    }
}
