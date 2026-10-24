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

/// The list of open document windows shown in the Dock icon's menu and at the bottom of the
/// Window menu — one section per window, its tabs listed under it.
///
/// AppKit's own list can't be used: it's kept in the Window menu, which SwiftUI replaces whenever
/// the menu commands rebuild, leaving windows already open out of the new one (and so out of the
/// Dock) until they're next ordered front. It also lists every tab as its own window and includes
/// snapshot windows. Document and snapshot windows are therefore excluded from AppKit's list
/// (`isExcludedFromWindowsMenu`) and this list, built fresh each time, stands in for it.
@MainActor
public enum DockMenu {
    /// The Dock icon's menu (see AppDelegate.applicationDockMenu).
    public static func make(from windows: [NSWindow]? = nil) -> NSMenu {
        let menu = NSMenu()
        for item in items(from: windows) {
            menu.addItem(item)
        }
        return menu
    }

    /// One section per document window, front to back, separated by separator items. A
    /// single-tab window is one row; a multi-tab window gets a disabled header row followed by
    /// its tabs, indented, the selected one checked. Snapshot windows aren't listed; a row
    /// notes how many were opened from that tab, and choosing it brings them forward too.
    static func items(from windows: [NSWindow]? = nil) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for group in windowGroups(from: windows ?? allWindows()) {
            if !items.isEmpty { items.append(.separator()) }
            guard group.count > 1 else {
                items.append(row(for: group[0], indentation: 0, isSelected: false))
                continue
            }
            let header = NSMenuItem(title: headerTitle(for: group), action: nil, keyEquivalent: "")
            header.isEnabled = false
            items.append(header)
            let selected = group[0].tabGroup?.selectedWindow
            for tab in group {
                items.append(row(for: tab, indentation: 1, isSelected: tab === selected))
            }
        }
        return items
    }

    /// Document windows grouped by tab group, frontmost group first, tabs in tab order.
    static func windowGroups(from windows: [NSWindow]) -> [[NSWindow]] {
        var seen = Set<ObjectIdentifier>()
        var groups: [[NSWindow]] = []
        for window in windows where window is PDFViewerWindow && !seen.contains(ObjectIdentifier(window)) {
            let tabs = window.tabGroup?.windows ?? window.tabbedWindows ?? [window]
            tabs.forEach { seen.insert(ObjectIdentifier($0)) }
            // A closed tab can linger in NSApp.windows; only list groups still on screen or in the Dock.
            guard tabs.contains(where: { $0.isVisible || $0.isMiniaturized }) else { continue }
            groups.append(tabs)
        }
        return groups
    }

    /// Brings `tab`'s window forward with `tab` selected, along with the snapshot windows opened
    /// from `tab` (the ones its menu row counts), restored if minimized and placed just above it
    /// as they were when opened. Other tabs' snapshot windows are left where they are.
    public static func activate(_ tab: NSWindow) {
        NSApp.activate()
        if tab.isMiniaturized { tab.deminiaturize(nil) }
        tab.tabGroup?.selectedWindow = tab
        tab.makeKeyAndOrderFront(nil)
        for child in SnapshotWindowManager.shared.windows(openedFrom: [tab]) {
            if child.isMiniaturized { child.deminiaturize(nil) }
            child.order(.above, relativeTo: tab.windowNumber)
        }
    }

    // MARK: - Window menu

    private static var windowMenuObserver: NSObjectProtocol?
    private static let windowMenuItemID = NSUserInterfaceItemIdentifier("VectorPDF.DocumentWindowList")

    /// Keeps the document-window list at the bottom of the Window menu, refreshed each time the
    /// menu bar is opened — so it survives SwiftUI replacing the menu.
    public static func installInWindowMenu() {
        guard windowMenuObserver == nil else { return }
        windowMenuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            let menuID = ObjectIdentifier(menu)
            MainActor.assumeIsolated {
                guard let mainMenu = NSApp.mainMenu, menuID == ObjectIdentifier(mainMenu) else { return }
                refreshWindowMenu()
            }
        }
    }

    static func refreshWindowMenu() {
        guard let windowsMenu = NSApp.windowsMenu else { return }
        for item in windowsMenu.items where item.identifier == windowMenuItemID {
            windowsMenu.removeItem(item)
        }
        let items = items()
        guard !items.isEmpty else { return }
        for item in [.separator()] + items {
            item.identifier = windowMenuItemID
            windowsMenu.addItem(item)
        }
    }

    // MARK: - Helpers

    private static func allWindows() -> [NSWindow] {
        // orderedWindows leaves out minimized windows; append them after the on-screen ones.
        let ordered = NSApp.orderedWindows
        let ids = Set(ordered.map(ObjectIdentifier.init))
        return ordered + NSApp.windows.filter { !ids.contains(ObjectIdentifier($0)) }
    }

    private static func headerTitle(for tabs: [NSWindow]) -> String {
        let coordinator = PDFViewerAppCoordinator.shared
        let groupName = tabs.lazy
            .compactMap { coordinator.viewModel(for: $0)?.groupOrigin }
            .compactMap { TabGroupManager.shared.group(withId: $0)?.name }
            .first
        return groupName.map { "\($0) (\(tabs.count) Tabs)" } ?? "\(tabs.count) Tabs"
    }

    /// The name shown on the window's tab. SwiftUI's empty `.navigationTitle` often leaves
    /// `window.title` blank, so the tab's own title (set by TabBarAppearanceHelper) comes first.
    static func displayTitle(for window: NSWindow) -> String {
        let candidates: [String?] = [window.tab.title, window.title, window.representedURL?.lastPathComponent]
        return candidates.compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "VectorPDF"
    }

    private static func row(for window: NSWindow, indentation: Int, isSelected: Bool) -> NSMenuItem {
        var title = displayTitle(for: window)
        if window.isDocumentEdited { title += " — Edited" }
        let snapshots = SnapshotWindowManager.shared.windows(openedFrom: [window]).count
        if snapshots > 0 { title += " (+\(snapshots) \(snapshots == 1 ? "window" : "windows"))" }
        let item = NSMenuItem(title: title, action: #selector(Handler.activateWindow(_:)), keyEquivalent: "")
        item.target = Handler.shared
        item.representedObject = WeakWindow(window)
        item.indentationLevel = indentation
        item.state = isSelected ? .on : .off
        return item
    }

    private final class WeakWindow {
        weak var window: NSWindow?
        init(_ window: NSWindow) { self.window = window }
    }

    @MainActor private final class Handler: NSObject {
        static let shared = Handler()

        @objc func activateWindow(_ sender: NSMenuItem) {
            guard let window = (sender.representedObject as? WeakWindow)?.window else { return }
            DockMenu.activate(window)
        }
    }
}
