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

    override var contentViewController: NSViewController? {
        didSet { TitlebarDragStrip.install(in: self) }
    }

    private var tabGroupObservation: NSKeyValueObservation?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        // A tab dragged into or out of a saved group's window joins or leaves that group. AppKit
        // reports a move more than once, so read the group once it's done.
        tabGroupObservation = observe(\.tabGroup) { window, _ in
            DispatchQueue.main.async { [weak window] in
                guard let window, let viewModel = PDFViewerAppCoordinator.shared.viewModel(for: window) else { return }
                viewModel.groupOrigin = DocumentWindowing.savedGroupID(for: window)
            }
        }
    }

    /// The document's, for Edit > Undo. Asking the delegate isn't enough: the window makes its
    /// own undo manager before the document's delegate is attached, and keeps using it.
    override var undoManager: UndoManager? {
        (delegate as? PDFViewerWindowDelegate)?.viewModel?.undoManager ?? super.undoManager
    }

    // NSWindow's own undo: and redo: use the undo manager it made, not the one above.
    @objc func undo(_ sender: Any?) {
        undoManager?.undo()
    }

    @objc func redo(_ sender: Any?) {
        undoManager?.redo()
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
                    } else if event.clickCount == 2 {
                        handleTitleBarDoubleClick(event)
                        return
                    }
                    // A single click on blank title bar lands on TitlebarDragStrip and falls through
                    // to AppKit, which moves the window, or to its mouseDown while a toolbar is open.
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

    func isInteractiveControl(_ view: NSView, stopAtContentView: Bool = false) -> Bool {
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
    /// Every document window's tab-bar identity, so a tab can be dragged between any two of them,
    /// saved groups included.
    static let documentTabbingIdentifier = "VectorPDFDocument"

    /// The saved Tab Group each open group's tabs belong to. It belongs to the tab group, not
    /// the tab: one dragged out leaves the group, one dragged in joins it.
    private static let savedGroupIDs = NSMapTable<NSWindowTabGroup, NSUUID>.weakToStrongObjects()

    /// The saved Tab Group `window`'s tabs were opened from, if it's still among them.
    static func savedGroupID(for window: NSWindow) -> UUID? {
        window.tabGroup.flatMap { savedGroupIDs.object(forKey: $0) as UUID? }
    }

    public static func installTabBarPlusButtonHandler() {
        let sel = #selector(NSWindow.newWindowForTab(_:))
        guard class_getInstanceMethod(NSWindow.self, sel) == nil else { return }
        let block: @convention(block) (NSWindow, Any?) -> Void = { window, _ in
            DocumentWindowing.addEmptyTab(to: window)
        }
        let imp = imp_implementationWithBlock(block)
        class_addMethod(NSWindow.self, sel, imp, "v@:@")
    }

    /// The screen new windows open on: the active window's, else the one with the menu bar focus.
    private static func targetScreen() -> NSScreen? {
        NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Most of the screen, capped so very large displays don't get a wall-sized window, and
    /// never more than the screen can show (small or scaled displays, e.g. 1024x665 visible).
    static func defaultWindowSize(for screen: NSScreen?) -> NSSize {
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let margin: CGFloat = 40
        let width = min(1800, max(640, screenFrame.width - margin), max(1000, screenFrame.width * 0.85))
        let height = min(1200, max(480, screenFrame.height - margin), max(700, screenFrame.height * 0.90))
        return NSSize(width: width.rounded(), height: height.rounded())
    }

    /// The default size, centred on `screen`, so a later `center()` keeps the window there
    /// (it centres on whichever screen the window is already on).
    private static func defaultWindowRect(on screen: NSScreen?) -> NSRect {
        let size = defaultWindowSize(for: screen)
        guard let visible = screen?.visibleFrame else { return NSRect(origin: .zero, size: size) }
        return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// Gives `window` the default size for `screen`. Only when a window opens: one the user moves
    /// to another display keeps its size, as in other Mac apps.
    private static func applyDefaultSize(to window: NSWindow, on screen: NSScreen?) {
        window.setContentSize(defaultWindowSize(for: screen))
    }

    /// The bare window shell shared by every variant below — same style mask, ARC-safety flag,
    /// and tab-bar identity handling, whether or not it ends up showing a document.
    static func makeBareWindow(tabbingIdentifier: String? = nil) -> NSWindow {
        let screen = targetScreen()
        let initialRect = defaultWindowRect(on: screen)
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
        // Listed by DockMenu instead of AppKit, whose list SwiftUI's menu rebuilds lose.
        window.isExcludedFromWindowsMenu = true
        window.tabbingIdentifier = tabbingIdentifier ?? documentTabbingIdentifier
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
        window.contentViewController = NSHostingController(rootView: view)
        applyDefaultSize(to: window, on: window.screen ?? targetScreen())
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
        window.contentViewController = NSHostingController(rootView: view)
        applyDefaultSize(to: window, on: window.screen ?? targetScreen())
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
        // Only document windows: not Settings, panels, sheets or anchor windows
        guard let window = window as? PDFViewerWindow else { return false }
        if window.attachedSheet != nil || window.isMiniaturized { return false }
        // Must have only 1 tab (or no tabbed windows attached)
        let tabCount = window.tabbedWindows?.count ?? 1
        guard tabCount <= 1 else { return false }
        // Must have no represented document URL and no unsaved edits
        guard window.representedURL == nil, !window.isDocumentEdited else { return false }
        // Must have no document, and none on its way: each window that opens a document closes
        // the empty ones, and a window still loading its own must not be among them
        if let viewModel = (window.contentViewController as? NSHostingController<PDFViewerMainView>)?.rootView.viewModel {
            guard viewModel.document == nil, !viewModel.isLoadingDocument else { return false }
        }
        return true
    }

    /// Opens every document in `group` as tabs of a window. They open under a tab-bar identity of
    /// their own, so macOS doesn't merge them into a window already open, and take the usual one
    /// once they're on screen, so tabs can be dragged in and out.
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
        var lastWindow: NSWindow?
        for path in group.documentPaths {
            let window = makeWindow(for: URL(fileURLWithPath: path), tabbingIdentifier: tabbingIdentifier, groupOrigin: group.id)
            defer { lastWindow = window }
            if let lastWindow {
                // Attach after the previous tab (not the first), or tabs come out in reverse.
                lastWindow.addTabbedWindow(window, ordered: .above)
            } else {
                if let replaceWin = windowToReplace, !replaceWin.styleMask.contains(.fullScreen) {
                    window.setFrame(replaceWin.frame, display: false)
                } else {
                    window.center()
                }
                firstWindow = window
            }
        }
        if let tabGroup = firstWindow?.tabGroup {
            savedGroupIDs.setObject(group.id as NSUUID, forKey: tabGroup)
        }
        firstWindow?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak firstWindow] in
            for window in firstWindow.map({ $0.tabbedWindows ?? [$0] }) ?? [] {
                window.tabbingIdentifier = documentTabbingIdentifier
            }
        }
        closeAfterCurrentEvent(windowToReplace)
        return firstWindow
    }

    /// Closes a Start window once the event in progress is over: the click that opened a document
    /// may be one on that window's own Start screen, and is still being handled.
    private static func closeAfterCurrentEvent(_ window: NSWindow?) {
        DispatchQueue.main.async { [weak window] in
            window?.close()
        }
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
            closeAfterCurrentEvent(candidate)
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

/// An invisible strip over the title-bar area, above the SwiftUI content that extends under the
/// transparent title bar and below the toolbar items. Blank title bar then drags the window the
/// way AppKit's own title bar does, as the document title does: the click doesn't reach SwiftUI,
/// whose views would otherwise get it while the window server moves the window without AppKit
/// knowing, so AppKit warned "Window move completed without beginning" and snapped the window
/// to its remembered place when it changed display mid-drag. Where the content has a control in
/// the title-bar area (the sidebar mode picker), clicks go through to it.
final class TitlebarDragStrip: NSView {
    static func install(in window: PDFViewerWindow) {
        guard let content = window.contentView, let frameView = content.superview,
              !frameView.subviews.contains(where: { $0 is TitlebarDragStrip }) else { return }
        let strip = TitlebarDragStrip(frame: frameView.bounds)
        strip.autoresizingMask = [.width, .height]
        frameView.addSubview(strip, positioned: .above, relativeTo: content)
    }

    override var mouseDownCanMoveWindow: Bool {
        !startsOwnWindowMove(at: window?.mouseLocationOutsideOfEventStream ?? .zero)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window = window as? PDFViewerWindow, let superview else { return nil }
        let inWindow = superview.convert(point, to: nil)
        // Only the title-bar band, above the content layout area.
        guard inWindow.y >= window.contentLayoutRect.maxY, inWindow.y <= window.frame.height else { return nil }
        if let content = window.contentView,
           let hit = content.hitTest(content.superview?.convert(inWindow, from: nil) ?? inWindow),
           window.isInteractiveControl(hit, stopAtContentView: true) {
            return nil
        }
        return self
    }

    /// AppKit moves the window from here, except above the document area while a toolbar is open
    /// under the title bar, when it doesn't start a move (the view hit is the same; the reason
    /// isn't known). performDrag(with:) covers that case only: anywhere else it would be a second
    /// move competing with AppKit's, and the window falls behind the pointer.
    private func startsOwnWindowMove(at locationInWindow: NSPoint) -> Bool {
        guard let window, PDFViewerAppCoordinator.shared.viewModel(for: window)?.isDocumentToolbarVisible == true else {
            return false
        }
        return !isOverSidebar(locationInWindow)
    }

    private func isOverSidebar(_ locationInWindow: NSPoint) -> Bool {
        func splitView(in view: NSView) -> NSSplitView? {
            (view as? NSSplitView) ?? view.subviews.lazy.compactMap(splitView).first
        }
        guard let content = window?.contentView, let split = splitView(in: content),
              let sidebar = split.arrangedSubviews.first, !split.isSubviewCollapsed(sidebar) else { return false }
        return locationInWindow.x <= sidebar.convert(sidebar.bounds, to: nil).maxX
    }

    // PDFViewerWindow.sendEvent handles activation and double-click. Nothing for SwiftUI underneath.
    override func mouseDown(with event: NSEvent) {
        if startsOwnWindowMove(at: event.locationInWindow) { window?.performDrag(with: event) }
    }
}
