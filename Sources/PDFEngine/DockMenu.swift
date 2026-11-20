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
/// Window menu: a row per window, its tabs indented under it. The Dock's menu adds New Window
/// and an Open Recent submenu.
///
/// A window's row has the standard marks, as AppKit's own list does: a checkmark on the front
/// window, a diamond on a minimized one, a dot on one with unsaved changes in any of its tabs.
/// A window with tabs is named after the Tab Group it was opened from, or else by how many tabs
/// it has; a checkmark marks its selected tab.
/// Anchor (snapshot) windows aren't listed; they come forward with the tab they were opened from.
///
/// AppKit's own list can't be used: it's kept in the Window menu, which SwiftUI replaces whenever
/// the menu commands rebuild, leaving windows already open out of the new one (and so out of the
/// Dock) until they're next ordered front. It also lists every tab as its own window and includes
/// snapshot windows. Document and snapshot windows are therefore excluded from AppKit's list
/// (`isExcludedFromWindowsMenu`) and this list, built fresh each time, stands in for it.
@MainActor
public enum DockMenu {
    /// The Dock icon's menu (see AppDelegate.applicationDockMenu).
    public static func make(from windows: [NSWindow]? = nil, recents: [URL]? = nil) -> NSMenu {
        let menu = NSMenu()
        for item in items(from: windows) {
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let newWindow = NSMenuItem(title: "New Window", action: #selector(Handler.newWindow(_:)), keyEquivalent: "")
        newWindow.target = Handler.shared
        menu.addItem(newWindow)
        let recents = recents ?? RecentDocuments.shared.urls
        if !recents.isEmpty {
            menu.addItem(openRecentItem(for: recents))
        }
        return menu
    }

    /// A row per document window, in the order they were opened, each marked as AppKit marks
    /// windows. A window with more than one tab has its tabs listed under it, indented, the
    /// selected one checked, and is set off from the windows around it by separators.
    static func items(from windows: [NSWindow]? = nil) -> [NSMenuItem] {
        let groups = windowGroups(from: windows ?? allWindows())
            .sorted { openingOrder(of: $0) < openingOrder(of: $1) }
        let front = frontGroupIndex(in: groups)
        var items: [NSMenuItem] = []
        var previousHadTabs = false
        for (index, group) in groups.enumerated() {
            let hasTabs = group.count > 1
            if !items.isEmpty && (hasTabs || previousHadTabs) { items.append(.separator()) }
            previousHadTabs = hasTabs
            let selected = group.first { $0.tabGroup?.selectedWindow === $0 } ?? group[0]
            let row = item(title: windowTitle(for: group, selected: selected), window: selected, indentation: 0)
            setMark(on: row, for: group, isFront: index == front)
            items.append(row)
            guard hasTabs else { continue }
            for tab in group {
                let tabRow = item(title: displayTitle(for: tab), window: tab, indentation: 2)
                if tab === selected { tabRow.state = .on }
                items.append(tabRow)
            }
        }
        return items
    }

    /// When the window was opened: the lowest window number among its tabs. The list keeps this
    /// order, as AppKit's does, rather than moving the front window to the top.
    private static func openingOrder(of tabs: [NSWindow]) -> Int {
        tabs.map(\.windowNumber).filter { $0 > 0 }.min() ?? .max
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

    /// The open document window or tab showing `url`, if any.
    public static func window(showing url: URL) -> NSWindow? {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return windowGroups(from: NSApp.windows).joined().first { window in
            window.representedURL?.standardizedFileURL.resolvingSymlinksInPath().path == path
        }
    }

    /// Brings `tab`'s window forward with `tab` selected, along with the snapshot windows opened
    /// from `tab`, restored if minimized and placed just above it as they were when opened.
    /// Other tabs' snapshot windows are left where they are.
    public static func activate(_ tab: NSWindow) {
        NSApp.activate()
        // A minimized window is its selected tab: another tab of it isn't itself minimized.
        if let minimized = tab.isMiniaturized ? tab : tab.tabGroup?.windows.first(where: \.isMiniaturized) {
            minimized.deminiaturize(nil)
        }
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

    /// The window's row: for a single tab, its name; for several, the name of the Tab Group they
    /// were opened from, or else how many there are — not the selected tab's name, which is
    /// listed under it.
    private static func windowTitle(for tabs: [NSWindow], selected: NSWindow) -> String {
        guard tabs.count > 1 else { return displayTitle(for: selected) }
        let coordinator = PDFViewerAppCoordinator.shared
        let groupName = tabs.lazy
            .compactMap { coordinator.viewModel(for: $0)?.groupOrigin }
            .compactMap { TabGroupManager.shared.group(withId: $0)?.name }
            .first
        return groupName ?? "\(tabs.count) Tabs"
    }

    /// The group holding the main window — or, when a snapshot window or none is main, the
    /// frontmost group on screen.
    private static func frontGroupIndex(in groups: [[NSWindow]]) -> Int? {
        if let main = NSApp.mainWindow, let index = groups.firstIndex(where: { $0.contains(main) }) {
            return index
        }
        for window in NSApp.orderedWindows where !window.isMiniaturized {
            if let index = groups.firstIndex(where: { $0.contains(window) }) { return index }
        }
        return nil
    }

    /// AppKit's marks: a diamond when minimized, else a checkmark on the front window, else a dot
    /// when any tab has unsaved changes.
    private static func setMark(on item: NSMenuItem, for tabs: [NSWindow], isFront: Bool) {
        if tabs.contains(where: \.isMiniaturized) {
            item.state = .on
            item.onStateImage = markImage(named: "NSMenuItemDiamond", fallbackSymbol: "diamond.fill")
        } else if isFront {
            item.state = .on
        } else if tabs.contains(where: \.isDocumentEdited) {
            item.state = .on
            item.onStateImage = markImage(named: "NSMenuItemBullet", fallbackSymbol: "circle.fill")
        }
    }

    private static func markImage(named name: String, fallbackSymbol: String) -> NSImage? {
        if let image = NSImage(named: name) { return image }
        let config = NSImage.SymbolConfiguration(pointSize: 6, weight: .regular)
        return NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    private static func openRecentItem(for urls: [URL]) -> NSMenuItem {
        let submenu = NSMenu(title: "Open Recent")
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(Handler.openRecent(_:)), keyEquivalent: "")
            item.target = Handler.shared
            item.representedObject = url
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            item.image?.size = NSSize(width: 16, height: 16)
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(Handler.clearRecents(_:)), keyEquivalent: "")
        clear.target = Handler.shared
        submenu.addItem(clear)
        let item = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// The name shown on the window's tab. SwiftUI's empty `.navigationTitle` often leaves
    /// `window.title` blank, so the tab's own title (set by TabBarAppearanceHelper) comes first.
    static func displayTitle(for window: NSWindow) -> String {
        let candidates: [String?] = [window.tab.title, window.title, window.representedURL?.lastPathComponent]
        return candidates.compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "VectorPDF"
    }

    private static func item(title: String, window: NSWindow, indentation: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(Handler.activateWindow(_:)), keyEquivalent: "")
        item.target = Handler.shared
        item.representedObject = WeakWindow(window)
        item.indentationLevel = indentation
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

        @objc func openRecent(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            NSApp.activate()
            DocumentWindowing.showOrOpenDocument(url: url)
        }

        @objc func newWindow(_ sender: NSMenuItem) {
            NSApp.activate()
            DocumentWindowing.openNewEmptyWindow()
        }

        @objc func clearRecents(_ sender: NSMenuItem) {
            PDFViewerAppCoordinator.shared.clearRecentDocuments()
        }
    }
}
