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

@MainActor struct DockMenuTests {
    /// A three-tab window and a single-tab window, both on screen, plus their temp PDFs.
    private func makeWindows() -> (tabbed: NSWindow, single: NSWindow, cleanup: () -> Void) {
        _ = NSApplication.shared
        let urls = (0..<4).map { i in
            FileManager.default.temporaryDirectory.appendingPathComponent("dock_menu_\(i)_\(UUID().uuidString).pdf")
        }
        urls.forEach(createSamplePDF(at:))
        let tabbed = DocumentWindowing.makeWindow(for: urls[0], tabbingIdentifier: "DockMenuTests-\(UUID().uuidString)")
        tabbed.makeKeyAndOrderFront(nil)
        DocumentWindowing.addTab(url: urls[1], to: tabbed)
        DocumentWindowing.addTab(url: urls[2], to: tabbed)
        let single = DocumentWindowing.makeWindow(for: urls[3])
        single.orderFront(nil)
        return (tabbed, single, {
            for window in (tabbed.tabGroup?.windows ?? [tabbed]) + [single] {
                window.tabbingMode = .disallowed
                window.close()
            }
            urls.forEach { try? FileManager.default.removeItem(at: $0) }
        })
    }

    @Test(.showsWindows) func listsTabsUnderTheirWindow() {
        let (tabbed, single, cleanup) = makeWindows()
        defer { cleanup() }
        let tabs = tabbed.tabGroup?.windows ?? []
        #expect(tabs.count == 3)

        // What SwiftUI's empty navigationTitle does to a live document window.
        for window in tabs + [single] { window.title = "" }
        let fileNames = tabs.map { $0.representedURL?.lastPathComponent }
        let selected = tabbed.tabGroup?.selectedWindow

        // In the order they were opened, whatever is in front: the tabbed window — named after
        // its selected tab — and its three tabs, indented; a separator; the single window.
        let items = DockMenu.items(from: [single, tabbed])
        #expect(items.map(\.isSeparatorItem) == [false, false, false, false, true, false])
        #expect(items.map(\.indentationLevel) == [0, 2, 2, 2, 0, 0])
        #expect(items[0].title == selected?.representedURL?.lastPathComponent)
        #expect(items[1...3].map(\.title) == fileNames)
        #expect(items[5].title == single.representedURL?.lastPathComponent)
        // Marks are on windows, not tabs.
        #expect(items[1...3].allSatisfy { $0.state == .off })
    }

    @Test(.showsWindows) func marksWindowsAsAppKitDoes() async throws {
        let (tabbed, single, cleanup) = makeWindows()
        defer { cleanup() }
        let tabs = try #require(tabbed.tabGroup?.windows)

        // Unsaved changes in a background tab mark its window with a dot.
        tabs[0].isDocumentEdited = true
        single.makeKeyAndOrderFront(nil)
        var items = DockMenu.items(from: [single, tabbed])
        var tabbedRow = items[0]
        #expect(tabbedRow.state == .on)
        #expect(tabbedRow.onStateImage?.name() == "NSMenuItemBullet")
        tabs[0].isDocumentEdited = false

        // A minimized window gets a diamond.
        single.miniaturize(nil)
        for _ in 0..<50 where !single.isMiniaturized { try await Task.sleep(for: .milliseconds(50)) }
        try #require(single.isMiniaturized)
        items = DockMenu.items(from: [tabbed, single])
        let singleRow = try #require(items.last)
        #expect(singleRow.state == .on)
        #expect(singleRow.onStateImage?.name() == "NSMenuItemDiamond")
        tabbedRow = items[0]
        #expect(tabbedRow.onStateImage?.name() != "NSMenuItemBullet")
        #expect(tabbedRow.onStateImage?.name() != "NSMenuItemDiamond")
    }

    @Test(.showsWindows) func addsNewWindowAndOpenRecent() throws {
        let (tabbed, single, cleanup) = makeWindows()
        defer { cleanup() }
        let recents = [URL(fileURLWithPath: "/Users/example/a.pdf"), URL(fileURLWithPath: "/Users/example/b.pdf")]

        let menu = DockMenu.make(from: [single, tabbed], recents: recents)
        let openRecent = try #require(menu.items.last)
        #expect(openRecent.title == "Open Recent")
        #expect(menu.items[menu.items.count - 2].title == "New Window")
        let titles = openRecent.submenu?.items.map(\.title)
        #expect(titles == ["a.pdf", "b.pdf", "", "Clear Menu"])

        // Nothing recent: no submenu.
        let titles2 = DockMenu.make(from: [single, tabbed], recents: []).items.map(\.title)
        #expect(!titles2.contains("Open Recent"))
        #expect(titles2.last == "New Window")
    }

    @Test(.showsWindows) func showsAnOpenFileRatherThanOpeningItAgain() throws {
        let (tabbed, single, cleanup) = makeWindows()
        defer { cleanup() }
        let tabs = try #require(tabbed.tabGroup?.windows)
        let url = try #require(tabs[0].representedURL)
        let windowCount = NSApp.windows.count

        single.makeKeyAndOrderFront(nil)
        let shown = DocumentWindowing.showOrOpenDocument(url: url)
        #expect(shown === tabs[0])
        #expect(tabbed.tabGroup?.selectedWindow === tabs[0])
        #expect(NSApp.windows.count == windowCount)
    }

    @Test(.showsWindows) func leavesOutSnapshotWindowsAndBringsThemForward() throws {
        let (tabbed, single, cleanup) = makeWindows()
        defer { cleanup() }
        let tabs = try #require(tabbed.tabGroup?.windows)
        let pdfURL = try #require(tabs[1].representedURL)

        let target = SnapshotTarget(label: "Figure 1", targetPage: 0, sourcePage: 0)
        SnapshotWindowManager.shared.open(url: pdfURL, target: target, source: tabs[1])
        defer { SnapshotWindowManager.shared.close(target.id) }
        let snapshot = try #require(SnapshotWindowManager.shared.windows(openedFrom: [tabs[1]]).first)
        #expect(snapshot.isExcludedFromWindowsMenu)
        #expect(tabs.allSatisfy { $0.isExcludedFromWindowsMenu })

        // The two windows and the three tabs; nothing for the snapshot.
        let items = DockMenu.items(from: [snapshot, single, tabbed])
        #expect(items.filter { !$0.isSeparatorItem }.count == 5)
        #expect(!items.contains { $0.title.contains("Figure 1") })

        // Another tab of the same window leaves the snapshot behind `single`.
        single.makeKeyAndOrderFront(nil)
        DockMenu.activate(tabs[2])
        #expect(tabs[2].tabGroup?.selectedWindow === tabs[2])
        var order = NSApp.orderedWindows
        #expect(try #require(order.firstIndex(of: tabs[2])) < #require(order.firstIndex(of: single)))
        #expect(try #require(order.firstIndex(of: single)) < #require(order.firstIndex(of: snapshot)))

        // Its own tab brings it forward, just above the window.
        single.makeKeyAndOrderFront(nil)
        DockMenu.activate(tabs[1])
        order = NSApp.orderedWindows
        let snapshotIndex = try #require(order.firstIndex(of: snapshot))
        let tabIndex = try #require(order.firstIndex(of: tabs[1]))
        #expect(snapshotIndex < tabIndex)
        #expect(tabIndex < (try #require(order.firstIndex(of: single))))
    }

    @Test(.showsWindows) func listsWindowsAfterTheWindowMenuIsReplaced() {
        let (tabbed, single, cleanup) = makeWindows()
        defer { cleanup() }
        // What SwiftUI does when its menu commands rebuild: the old Window menu, and AppKit's
        // list of windows in it, are gone.
        let oldWindowsMenu = NSApp.windowsMenu
        NSApp.windowsMenu = NSMenu(title: "Window")
        defer { NSApp.windowsMenu = oldWindowsMenu }

        let titles = Set(DockMenu.make().items.map(\.title))
        #expect(titles.contains(single.title))
        #expect((tabbed.tabGroup?.windows ?? []).allSatisfy { titles.contains($0.title) })

        DockMenu.refreshWindowMenu()
        let windowMenuTitles = Set(NSApp.windowsMenu?.items.map(\.title) ?? [])
        #expect(windowMenuTitles.contains(single.title))
    }

    @Test(.showsWindows) func listsWindowOpenedFromFinder() {
        let (_, _, cleanup) = makeWindows()
        defer { cleanup() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dock_menu_finder_\(UUID().uuidString).pdf")
        createSamplePDF(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let opened = DocumentWindowing.openDocumentHandlingEmptyStart(url: url)
        defer { opened.tabbingMode = .disallowed; opened.close() }
        let titles = DockMenu.items().map(\.title)
        #expect(titles.contains(url.lastPathComponent))
    }

    @Test(.showsWindows) func restoresMinimizedSnapshotsWithTheirTab() async throws {
        let (tabbed, single, cleanup) = makeWindows()
        defer { cleanup() }
        let tabs = try #require(tabbed.tabGroup?.windows)
        let pdfURL = try #require(tabs[1].representedURL)

        let target = SnapshotTarget(label: "Figure 1", targetPage: 0, sourcePage: 0)
        SnapshotWindowManager.shared.open(url: pdfURL, target: target, source: tabs[1])
        defer { SnapshotWindowManager.shared.close(target.id) }
        let snapshot = try #require(SnapshotWindowManager.shared.windows(openedFrom: [tabs[1]]).first)

        snapshot.miniaturize(nil)
        for _ in 0..<50 where !snapshot.isMiniaturized { try await Task.sleep(for: .milliseconds(50)) }
        try #require(snapshot.isMiniaturized)

        // Not listed itself.
        let items = DockMenu.items(from: [single, tabbed])
        #expect(!items.contains { $0.title.contains("Figure 1") })
        let tabIndex = try #require(items.lastIndex { $0.title == DockMenu.displayTitle(for: tabs[1]) })

        // Choosing another tab of the same window leaves it minimized.
        let menu = NSMenu()
        items.forEach(menu.addItem)
        let otherTabIndex = try #require(items.lastIndex { $0.title == DockMenu.displayTitle(for: tabs[2]) })
        menu.performActionForItem(at: otherTabIndex)
        try await Task.sleep(for: .milliseconds(500))
        #expect(snapshot.isMiniaturized)

        // Choosing its own tab restores it.
        menu.performActionForItem(at: tabIndex)
        for _ in 0..<50 where snapshot.isMiniaturized { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!snapshot.isMiniaturized)
        #expect(tabs[1].tabGroup?.selectedWindow === tabs[1])
    }
}
