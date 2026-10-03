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

import SwiftUI
import AppKit

/// NSWindow subclass used for every window DocumentWindowing creates (including the app's very
/// first window — see AppDelegate.applicationDidFinishLaunching), solely so it can respond to the
/// native tab-bar "+" button. AppKit sends `newWindowForTab:` up the responder chain when that
/// button is clicked; with no override anywhere in the chain, it's a silent no-op (or the button
/// doesn't even appear). `installTabBarPlusButtonHandler` below covers plain `NSWindow` instances
/// created elsewhere (e.g. SnapshotWindowManager) that don't go through this subclass. Clicking
/// "+" opens a new *empty* tab (the Start screen), not a duplicate of whatever document happens
/// to be open.
final class PDFViewerWindow: NSWindow {
    override func newWindowForTab(_ sender: Any?) {
        DocumentWindowing.addEmptyTab(to: self)
    }

    override func sendEvent(_ event: NSEvent) {
        let wasKey = isKeyWindow
        if event.type == .leftMouseDown {
            let loc = event.locationInWindow
            let effectiveTitlebarHeight = max(frame.height - contentLayoutRect.height, 28.0)
            if loc.y >= frame.height - effectiveTitlebarHeight {
                // Inactive window: activate, then deliver the click with background-drag off so it can't start a window move.
                if !wasKey, attachedSheet == nil {
                    activateAndMakeKey()
                    let wasMovable = isMovableByWindowBackground
                    isMovableByWindowBackground = false
                    super.sendEvent(event)
                    isMovableByWindowBackground = wasMovable
                    if !isKeyWindow {
                        DispatchQueue.main.async { [weak self] in self?.activateAndMakeKey() }
                    }
                    return
                }
                // If an interactive control inside contentView was clicked (e.g. the sidebar mode picker in Row 2),
                // forward the click directly to that control rather than intercepting with window drag.
                if let contentHit = contentView?.hitTest(loc), isInteractiveControl(contentHit, stopAtContentView: true) {
                    if !isKeyWindow {
                        activateAndMakeKey()
                    }
                    var targetView: NSView = contentHit
                    var curr: NSView? = contentHit
                    while let v = curr {
                        if v is NSControl {
                            targetView = v
                            break
                        }
                        curr = v.superview
                    }
                    targetView.mouseDown(with: event)
                    return
                }

                let rootHit = (contentView?.superview ?? contentView)?.hitTest(loc)
                if let hitView = rootHit {
                    if isInteractiveControl(hitView) {
                        // When the window does not have focus, clicking a toolbar button in other macOS apps
                        // activates the window and triggers the control on first mouse click.
                        if !isKeyWindow {
                            activateAndMakeKey()
                            if !hitView.acceptsFirstMouse(for: event) {
                                hitView.mouseDown(with: event)
                                return
                            }
                        }
                    } else {
                        if event.clickCount == 2 {
                            handleTitleBarDoubleClick(event)
                            return
                        } else if event.clickCount == 1 {
                            if isKeyWindow {
                                performDrag(with: event)
                                return
                            }
                        }
                    }
                }
            }
        }
        // Backstop: ensure a first click anywhere activates the window.
        super.sendEvent(event)
        if event.type == .leftMouseDown, !wasKey, !isKeyWindow, attachedSheet == nil {
            activateAndMakeKey()
        }
    }

    /// Activates the app (makeKey is deferred while inactive), then makes this window key and main.
    private func activateAndMakeKey() {
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        makeKeyAndOrderFront(nil)
        makeMain()
    }

    private func handleTitleBarDoubleClick(_ event: NSEvent) {
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        switch action {
        case "Minimize":
            performMiniaturize(nil)
        case "None":
            break
        case "Maximize", "Fill":
            zoom(nil)
        default:
            zoom(nil)
        }
    }

    private func isInteractiveControl(_ view: NSView, stopAtContentView: Bool = false) -> Bool {
        var current: NSView? = view
        while let v = current {
            if stopAtContentView && v === contentView {
                return false
            }
            if v is NSControl {
                return true
            }
            let name = String(describing: type(of: v))
            if name.contains("Button") ||
               name.contains("Control") ||
               name.contains("TextField") ||
               name.contains("Scroller") ||
               name.contains("Slider") ||
               name.contains("ToolbarItem") ||
               name.contains("Tab") ||
               name.contains("Widget") ||
               name.contains("Segmented") {
                return true
            }
            if !stopAtContentView && name.contains("Hosting") {
                return true
            }
            current = v.superview
        }
        return false
    }
}

/// Shared low-level window/tab creation for opening a document — used by the app's top-level
/// Open/Favorite/drag-and-drop flows (see main.swift) and by TabGroupManager (opening a saved
/// group's tabs). Centralizing this here means the isReleasedWhenClosed / tabbingMode /
/// closure-wiring boilerplate is written once instead of separately for every caller.
@MainActor
public enum DocumentWindowing {
    /// Installs a handler on the base NSWindow class so that clicking the native tab-bar "+"
    /// button on any window not already covered by the PDFViewerWindow subclass's own override
    /// (e.g. a SnapshotWindowManager preview window) opens a new tab instead of a silent no-op.
    public static func installTabBarPlusButtonHandler() {
        let sel = #selector(NSWindow.newWindowForTab(_:))
        guard class_getInstanceMethod(NSWindow.self, sel) == nil else { return }
        let block: @convention(block) (NSWindow, Any?) -> Void = { window, _ in
            DocumentWindowing.addEmptyTab(to: window)
        }
        let imp = imp_implementationWithBlock(block)
        class_addMethod(NSWindow.self, sel, imp, "v@:@")
    }

    private static func defaultWindowRect() -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let defaultWidth: CGFloat = 1440
        let defaultHeight: CGFloat = 960
        // The 1000x700 floor keeps the window usable on mid-size displays, but it must never exceed
        // what the screen can actually show (small or scaled displays, e.g. 1024x665 visible).
        let margin: CGFloat = 60
        let maxWidth = max(640, screenFrame.width - margin)
        let maxHeight = max(480, screenFrame.height - margin)
        let targetWidth = min(defaultWidth, maxWidth, max(1000, screenFrame.width * 0.75))
        let targetHeight = min(defaultHeight, maxHeight, max(700, screenFrame.height * 0.80))
        return NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
    }

    /// The bare window shell shared by every variant below — same style mask, ARC-safety flag,
    /// and tab-bar identity handling, whether or not it ends up showing a document.
    static func makeBareWindow(tabbingIdentifier: String? = nil) -> NSWindow {
        let initialRect = defaultWindowRect()
        let window = PDFViewerWindow(
            contentRect: initialRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 640, height: 480)
        // Prevent ARC double-free on window close.
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.backgroundColor = .topWindowBarColor
        window.isMovableByWindowBackground = true
        window.tabbingMode = .preferred
        if let tabbingIdentifier {
            window.tabbingIdentifier = tabbingIdentifier
        }
        // Show the tab bar by default on single-tab windows.
        if window.tabGroup?.isTabBarVisible != true {
            window.toggleTabBar(nil)
        }
        return window
    }

    /// Creates (but does not show) a window for `url`. `tabbingIdentifier`, if given, groups this
    /// window's tab bar with others sharing the same identifier; `groupOrigin`, if given, marks
    /// this window as an instance of that saved Tab Group (enabling "Update Group" in its
    /// toolbar).
    public static func makeWindow(for url: URL, tabbingIdentifier: String? = nil, groupOrigin: UUID? = nil) -> NSWindow {
        let window = makeBareWindow(tabbingIdentifier: tabbingIdentifier)
        window.title = url.lastPathComponent
        window.representedURL = url

        let view = PDFViewerMainView(
            initialFilePath: url.path,
            initialURL: url,
            groupOrigin: groupOrigin,
            // Break retain cycle between view model and window.
            onOpenNewTab: { [weak window] nextUrl in
                guard let window else { return }
                DocumentWindowing.addTab(url: nextUrl, to: window)
            },
            onOpenNewWindow: { nextUrl in
                DocumentWindowing.openNewWindow(url: nextUrl)
            }
        )
        let targetRect = defaultWindowRect()
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(targetRect.size)
        window.title = url.lastPathComponent
        TabBarAppearanceHelper.refreshTabs(for: window)
        return window
    }

    /// Opens `url` in a genuinely new, standalone window — used by every explicit "open this
    /// document" action once the triggering window already has something open (see
    /// PDFViewerViewModel.openDocumentPreferringNewWindow).
    public static func openNewWindow(url: URL) {
        let window = makeWindow(for: url)
        window.center()
        window.makeKeyAndOrderFront(nil)
        TabBarAppearanceHelper.refreshTabs(for: window)
    }

    /// Opens a new, standalone empty window displaying the Start screen (Cmd+N).
    public static func openNewEmptyWindow() {
        let window = makeBareWindow(tabbingIdentifier: nil)
        window.title = "VectorPDF"

        let view = PDFViewerMainView(
            onOpenNewTab: { [weak window] nextUrl in
                guard let window else { return }
                DocumentWindowing.addTab(url: nextUrl, to: window)
            },
            onOpenNewWindow: { nextUrl in
                DocumentWindowing.openNewWindow(url: nextUrl)
            }
        )
        let targetRect = defaultWindowRect()
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(targetRect.size)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Adds `url` as a new tab attached to `sourceWindow`'s tab group — used by drag-and-drop
    /// onto a window that already has a document open ("add this here" reads as a tab, not a new
    /// window, matching direct-manipulation convention).
    public static func addTab(url: URL, to sourceWindow: NSWindow) {
        sourceWindow.tabbingMode = .preferred
        let window = makeWindow(for: url, tabbingIdentifier: sourceWindow.tabbingIdentifier)
        sourceWindow.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
        TabBarAppearanceHelper.refreshTabs(for: window)
    }

    /// Adds a blank tab (the Start screen, no document loaded) to `sourceWindow`'s tab group —
    /// what the native tab-bar "+" button now does; see PDFViewerWindow.newWindowForTab.
    public static func addEmptyTab(to sourceWindow: NSWindow) {
        sourceWindow.tabbingMode = .preferred
        let window = makeBareWindow(tabbingIdentifier: sourceWindow.tabbingIdentifier)
        window.title = "VectorPDF"

        let view = PDFViewerMainView(
            // See the identical [weak window] note in makeWindow above — same retain-cycle risk.
            onOpenNewTab: { [weak window] nextUrl in
                guard let window else { return }
                DocumentWindowing.addTab(url: nextUrl, to: window)
            },
            onOpenNewWindow: { nextUrl in
                DocumentWindowing.openNewWindow(url: nextUrl)
            }
        )
        window.contentViewController = NSHostingController(rootView: view)
        sourceWindow.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
        TabBarAppearanceHelper.refreshTabs(for: window)
    }

    /// Determines whether `window` is a standalone empty Start Screen window that can be cleanly
    /// replaced when opening a Tab Group, rather than leaving an orphaned empty window behind.
    public static func isStandaloneEmptyStartWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        // Must not be an auxiliary window, panel, sheet, or minimized
        if window is NSPanel || window.attachedSheet != nil || window.isMiniaturized { return false }
        // Must have only 1 tab (or no tabbed windows attached)
        let tabCount = window.tabbedWindows?.count ?? 1
        guard tabCount <= 1 else { return false }
        // Must have no represented document URL and no unsaved edits
        guard window.representedURL == nil, !window.isDocumentEdited else { return false }
        // If the active view model is associated with this window, verify it has no document loaded
        if let activeVM = PDFViewerAppCoordinator.shared.activeViewModel ?? PDFViewerViewModel.active,
           activeVM.currentWindow === window {
            guard activeVM.document == nil else { return false }
        }
        return true
    }

    /// Opens every document in `group` as tabs of a window, under a tab-bar identity unique
    /// to that group (so it never merges with unrelated tabs already open elsewhere).
    /// If `sourceWindow` (or the key window) is a standalone empty Start Screen window with
    /// no other tabs and no document loaded, this seamlessly replaces that window at its current
    /// frame instead of opening a redundant new window and leaving the blank one orphaned.
    @discardableResult
    public static func openGroup(_ group: TabGroup, replacing sourceWindow: NSWindow? = nil) -> NSWindow? {
        guard !group.documentPaths.isEmpty else { return nil }

        let candidateWindow = sourceWindow ?? NSApp.keyWindow ?? NSApp.mainWindow ?? PDFViewerViewModel.active?.currentWindow
        let windowToReplace = isStandaloneEmptyStartWindow(candidateWindow) ? candidateWindow : nil

        let tabbingIdentifier = "PDFViewerTabGroup-\(group.id.uuidString)"
        var firstWindow: NSWindow?
        for path in group.documentPaths {
            let window = makeWindow(for: URL(fileURLWithPath: path), tabbingIdentifier: tabbingIdentifier, groupOrigin: group.id)
            if let firstWindow {
                firstWindow.addTabbedWindow(window, ordered: .above)
            } else {
                if let replaceWin = windowToReplace, !replaceWin.styleMask.contains(.fullScreen) {
                    window.setFrame(replaceWin.frame, display: false)
                } else {
                    window.center()
                }
                firstWindow = window
            }
        }
        firstWindow?.makeKeyAndOrderFront(nil)
        windowToReplace?.close()
        return firstWindow
    }

    /// Closes any standalone empty Start Screen window currently open in NSApp.windows,
    /// optionally preserving `exceptWindow`. Useful when opening a document from an external
    /// trigger (such as double-clicking in Finder) to ensure no redundant blank windows remain.
    public static func closeStandaloneEmptyStartWindows(except exceptWindow: NSWindow? = nil) {
        for window in NSApp.windows {
            if window !== exceptWindow && isStandaloneEmptyStartWindow(window) {
                window.close()
            }
        }
    }

    /// Handles opening a document from an external system event (e.g. Finder double-click or CLI open).
    /// If `preferredWindow` (or the key/main window) is a standalone empty Start Screen window,
    /// this loads directly into it (or cleanly replaces it); otherwise it opens in a new window.
    @discardableResult
    public static func openDocumentHandlingEmptyStart(url: URL, preferredWindow: NSWindow? = nil) -> NSWindow {
        let candidateWindow = preferredWindow ?? NSApp.keyWindow ?? NSApp.mainWindow ?? PDFViewerViewModel.active?.currentWindow
        if let candidate = candidateWindow, isStandaloneEmptyStartWindow(candidate) {
            if let activeVM = PDFViewerAppCoordinator.shared.activeViewModel ?? PDFViewerViewModel.active,
               activeVM.currentWindow === candidate {
                Task { @MainActor in
                    await activeVM.loadDocument(from: url.path)
                }
                candidate.makeKeyAndOrderFront(nil)
                return candidate
            }

            let window = makeWindow(for: url)
            if !candidate.styleMask.contains(.fullScreen) {
                window.setFrame(candidate.frame, display: false)
            } else {
                window.center()
            }
            window.makeKeyAndOrderFront(nil)
            candidate.close()
            return window
        }

        let window = makeWindow(for: url)
        window.center()
        window.makeKeyAndOrderFront(nil)
        return window
    }
}

extension NSColor {
    /// Semantic color for the window top bar and secondary toolbars, providing a bright appearance matching Apple Preview and Finder.
    public static var topWindowBarColor: NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                return NSColor.windowBackgroundColor
            } else {
                return NSColor.white
            }
        }
    }
}

