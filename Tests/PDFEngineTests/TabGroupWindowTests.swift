import AppKit
import Foundation
import SwiftUI
import Testing
@testable import PDFEngine

@Suite(.serialized)
@MainActor
struct TabGroupWindowTests {
    private func testFile(_ name: String) -> String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/test-files/\(name)").path
    }

    /// Whether `window` closes, unlike `isVisible`, which is also false for a tab in the background.
    private final class CloseWatcher {
        private(set) var closed = false
        private var token: NSObjectProtocol?

        init(_ window: NSWindow) {
            token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) { [weak self] _ in
                self?.closed = true
            }
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }

    /// A Favorite clicked on the Start screen loads into that window, and a Tab Group clicked
    /// just after it must not close the window while it loads.
    @Test(.showsWindows) func openingAGroupWhileTheStartWindowLoadsAFavorite() async throws {
        _ = NSApplication.shared
        let group = TabGroup(name: "Group", documentPaths: [testFile("rfc9457.pdf"), testFile("nist-tn-2255.pdf")])

        for _ in 0..<6 {
            let before = Set(NSApp.windows.map(ObjectIdentifier.init))
            DocumentWindowing.openNewEmptyWindow()
            let start = try #require(NSApp.windows.first { !before.contains(ObjectIdentifier($0)) && $0.contentViewController != nil })
            try await Task.sleep(for: .milliseconds(200))
            let viewModel = try #require((start.contentViewController as? NSHostingController<PDFViewerMainView>)?.rootView.viewModel)

            let watcher = CloseWatcher(start)
            viewModel.openDocumentPreferringNewWindow(atPath: testFile("hr1968-ih.pdf"))
            while !viewModel.isLoadingDocument && viewModel.document == nil {
                await Task.yield()
            }
            let opened = try #require(DocumentWindowing.openGroup(group, replacing: start))
            try await Task.sleep(for: .milliseconds(900))

            #expect(viewModel.document?.filePath.hasSuffix("hr1968-ih.pdf") == true)
            #expect(!watcher.closed)
            for window in (opened.tabbedWindows ?? [opened]) + [start] {
                window.close()
            }
            try await Task.sleep(for: .milliseconds(400))
        }
    }

    /// The Start screen opens a group from a click on the window the group replaces, so that
    /// window has to outlast the click, and closures queued for tab styling mustn't free it.
    @Test(.showsWindows) func openingAGroupOverTheStartWindowFreesItSafely() async throws {
        _ = NSApplication.shared
        let group = TabGroup(name: "Group", documentPaths: [testFile("rfc9457.pdf"), testFile("lcms2-tutorial.pdf"), testFile("nist-tn-2255.pdf")])

        for _ in 0..<3 {
            let before = Set(NSApp.windows.map(ObjectIdentifier.init))
            DocumentWindowing.openNewEmptyWindow()
            let start = try #require(NSApp.windows.first { !before.contains(ObjectIdentifier($0)) && $0.contentViewController != nil })
            try await Task.sleep(for: .milliseconds(200))

            // Window tests run side by side, and macOS can tab this one into another test's window.
            let isStartWindow = DocumentWindowing.isStandaloneEmptyStartWindow(start)
            let watcher = CloseWatcher(start)
            let opened = try #require(DocumentWindowing.openGroup(group, replacing: start))
            #expect(!watcher.closed)
            try await Task.sleep(for: .milliseconds(600))
            #expect(watcher.closed == isStartWindow)

            for window in opened.tabbedWindows ?? [opened] {
                window.close()
            }
            try await Task.sleep(for: .milliseconds(400))
        }
    }

    /// A saved group's tabs share other windows' tab-bar identity once open, so tabs can be
    /// dragged in and out, and a tab joins or leaves the group as it moves.
    @Test(.showsWindows) func tabsMoveIntoAndOutOfASavedGroup() async throws {
        _ = NSApplication.shared
        let group = TabGroup(name: "Group", documentPaths: [testFile("rfc9457.pdf"), testFile("nist-tn-2255.pdf")])
        func viewModel(_ window: NSWindow) -> PDFViewerViewModel? {
            (window.contentViewController as? NSHostingController<PDFViewerMainView>)?.rootView.viewModel
        }

        let opened = try #require(DocumentWindowing.openGroup(group))
        try await Task.sleep(for: .milliseconds(600))
        let groupTabs = opened.tabbedWindows ?? [opened]
        #expect(groupTabs.count == 2)
        #expect(groupTabs.allSatisfy { $0.tabbingIdentifier == DocumentWindowing.documentTabbingIdentifier })
        #expect(groupTabs.allSatisfy { viewModel($0)?.groupOrigin == group.id })

        let plain = DocumentWindowing.makeWindow(for: URL(fileURLWithPath: testFile("hr1968-ih.pdf")))
        plain.setFrameOrigin(NSPoint(x: opened.frame.minX + 60, y: opened.frame.minY - 60))
        plain.orderFront(nil)
        try await Task.sleep(for: .milliseconds(400))
        #expect(plain.tabbingIdentifier == opened.tabbingIdentifier)

        // Out: the group's second tab moves to the plain window and leaves the group.
        let leaving = groupTabs[1]
        plain.addTabbedWindow(leaving, ordered: .above)
        try await Task.sleep(for: .milliseconds(300))
        #expect(viewModel(leaving)?.groupOrigin == nil)
        #expect(viewModel(groupTabs[0])?.groupOrigin == group.id)

        // In: the plain window's own tab moves to the group's window and joins it.
        opened.addTabbedWindow(plain, ordered: .above)
        try await Task.sleep(for: .milliseconds(300))
        #expect(viewModel(plain)?.groupOrigin == group.id)

        for window in Set((opened.tabbedWindows ?? [opened]) + (leaving.tabbedWindows ?? [leaving])) {
            window.close()
        }
        try await Task.sleep(for: .milliseconds(400))
    }
}
