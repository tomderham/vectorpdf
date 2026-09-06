import SwiftUI
import AppKit

/// NSWindow subclass used for every window DocumentWindowing creates, solely so it can respond
/// to the native tab-bar "+" button. AppKit sends `newWindowForTab:` up the responder chain when
/// that button is clicked; with no override anywhere in the chain, it's a silent no-op (or the
/// button doesn't even appear). SwiftUI's own `WindowGroup` scene (the app's initial launch
/// window) gets a working "+" for free from its own window machinery, but every window created
/// directly via `DocumentWindowing` needs this override instead. Clicking "+" opens a new *empty*
/// tab (the Start screen), not a duplicate of whatever document happens to be open.
final class PDFViewerWindow: NSWindow {
    override func newWindowForTab(_ sender: Any?) {
        DocumentWindowing.addEmptyTab(to: self)
    }
}

/// Shared low-level window/tab creation for opening a document — used by the app's top-level
/// Open/Favorite/drag-and-drop flows (see main.swift) and by TabGroupManager (opening a saved
/// group's tabs). Centralizing this here means the isReleasedWhenClosed / tabbingMode /
/// closure-wiring boilerplate is written once instead of separately for every caller.
@MainActor
public enum DocumentWindowing {
    /// The bare window shell shared by every variant below — same style mask, ARC-safety flag,
    /// and tab-bar identity handling, whether or not it ends up showing a document.
    private static func makeBareWindow(tabbingIdentifier: String?) -> NSWindow {
        let window = PDFViewerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // NSWindow defaults isReleasedWhenClosed to true, a pre-ARC behavior that double-frees a
        // manually constructed window under ARC — required for any NSWindow(...) created
        // directly like this, or closing it can crash later.
        window.isReleasedWhenClosed = false
        window.tabbingMode = .preferred
        if let tabbingIdentifier {
            window.tabbingIdentifier = tabbingIdentifier
        }
        // AppKit's own default hides the tab bar until a window has 2+ tabs — visible by default
        // here instead, so the "+" button and tab affordance are obvious from the first window
        // rather than only appearing once a second tab exists. Still just the standard tab bar:
        // the user can hide it themselves via View > Show Tab Bar (Cmd+Shift+\) same as any app.
        // isTabBarVisible itself is get-only; toggleTabBar(_:) is the actual way to change it, so
        // this only calls it when the bar isn't already showing (never fights a state where it's
        // already visible for some other reason).
        if window.tabGroup?.isTabBarVisible == false {
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
            // [weak window]: this closure is stored on the view model, which window.contentView
            // owns transitively — capturing window strongly here would be a window -> contentView
            // -> view graph -> view model -> this closure -> window retain cycle, keeping every
            // window (and the MuPDF document/context its view model owns) alive forever, even
            // after the window is closed.
            onOpenNewTab: { [weak window] nextUrl in
                guard let window else { return }
                DocumentWindowing.addTab(url: nextUrl, to: window)
            },
            onOpenNewWindow: { nextUrl in
                DocumentWindowing.openNewWindow(url: nextUrl)
            }
        )
        window.contentView = NSHostingView(rootView: view)
        return window
    }

    /// Opens `url` in a genuinely new, standalone window — used by every explicit "open this
    /// document" action once the triggering window already has something open (see
    /// PDFViewerViewModel.openDocumentPreferringNewWindow).
    public static func openNewWindow(url: URL) {
        let window = makeWindow(for: url)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Adds `url` as a new tab attached to `sourceWindow`'s tab group — used by drag-and-drop
    /// onto a window that already has a document open ("add this here" reads as a tab, not a new
    /// window, matching direct-manipulation convention).
    public static func addTab(url: URL, to sourceWindow: NSWindow) {
        let window = makeWindow(for: url, tabbingIdentifier: sourceWindow.tabbingIdentifier)
        sourceWindow.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    }

    /// Adds a blank tab (the Start screen, no document loaded) to `sourceWindow`'s tab group —
    /// what the native tab-bar "+" button now does; see PDFViewerWindow.newWindowForTab.
    public static func addEmptyTab(to sourceWindow: NSWindow) {
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
        window.contentView = NSHostingView(rootView: view)
        sourceWindow.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    }

    /// Opens every document in `group` as tabs of one new window, under a tab-bar identity unique
    /// to that group (so it never merges with unrelated tabs already open elsewhere).
    public static func openGroup(_ group: TabGroup) {
        guard !group.documentPaths.isEmpty else { return }
        let tabbingIdentifier = "PDFViewerTabGroup-\(group.id.uuidString)"
        var firstWindow: NSWindow?
        for path in group.documentPaths {
            let window = makeWindow(for: URL(fileURLWithPath: path), tabbingIdentifier: tabbingIdentifier, groupOrigin: group.id)
            if let firstWindow {
                firstWindow.addTabbedWindow(window, ordered: .above)
            } else {
                window.center()
                firstWindow = window
            }
        }
        firstWindow?.makeKeyAndOrderFront(nil)
    }
}
