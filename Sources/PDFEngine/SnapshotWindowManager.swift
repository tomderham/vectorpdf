import SwiftUI
import AppKit

/// Tracks every snapshot window opened via Option-click, a right-click "Open in New Window" (on
/// a link, a selection, or a plain page location), or a saved snapshot card's window button.
///
/// Centralizing window creation here — instead of threading `onOpenSnapshotWindow` closures
/// through every view that might spawn one — gives two things for free:
///   1. Asking "is a window already open for this snapshot?" from anywhere (e.g. to show a
///      Close button instead of an Open one on a snapshot card).
///   2. Closing a reading window's snapshot windows automatically when that window closes,
///      so they don't linger once the document they refer to is gone.
///
/// Uses the classic selector-based NotificationCenter API (rather than the block-based one)
/// deliberately: `addObserver(forName:object:queue:using:)` with `queue: .main` dispatches its
/// block *asynchronously* onto the main run loop, and its `@escaping @Sendable` closure type
/// can't be proven main-actor-isolated at compile time, which is why that version produced
/// concurrency warnings. Selector-based observers instead call `self` directly and synchronously
/// on whatever thread posts the notification — always the main thread for NSWindow — with no
/// closure/capture-list involved, sidestepping both problems at once.
@MainActor
public final class SnapshotWindowManager: NSObject, ObservableObject {
    public static let shared = SnapshotWindowManager()
    private override init() {
        super.init()
    }

    /// Windows currently open, keyed by the SnapshotTarget they were opened for. Entries are
    /// removed the moment the window closes (see `snapshotWindowWillClose`), so this never
    /// reports a closed window as open.
    @Published private var openWindows: [UUID: NSWindow] = [:]
    private var targetIdByWindow: [ObjectIdentifier: UUID] = [:]

    // Which snapshot-window ids were opened from which source window, so closing the source
    // can sweep them up. Keyed by the source NSWindow's identity, not the window itself.
    private var childrenByParent: [ObjectIdentifier: [UUID]] = [:]
    private var watchedParents: Set<ObjectIdentifier> = []

    // Maps a child window's identity to its root parent window's identity, so closing from any
    // child window can locate and close all siblings (and itself) belonging to that document.
    private var parentKeyByChild: [ObjectIdentifier: ObjectIdentifier] = [:]

    public func isOpen(_ id: UUID) -> Bool {
        openWindows[id] != nil
    }

    public var hasOpenWindows: Bool {
        !openWindows.isEmpty
    }

    public var openWindowCount: Int {
        openWindows.count
    }

    /// Closes every currently open snapshot window — however it was opened (a saved snapshot
    /// card, a cross-reference link, a selection, or a plain page location).
    public func closeAll() {
        for window in openWindows.values {
            window.close()
        }
    }

    /// Closes all snapshot and reference windows that share the same root parent as `window`
    /// (or are children of `window` if `window` is the parent). If `window` is nil or untracked,
    /// falls back to closing all open snapshot windows.
    public func closeChildrenOfCurrentParent(for window: NSWindow?) {
        guard let window else {
            closeAll()
            return
        }
        let winKey = ObjectIdentifier(window)
        if let parentKey = parentKeyByChild[winKey] {
            // window is a child window: close all children belonging to this child's root parent
            if let ids = childrenByParent[parentKey] {
                for id in ids {
                    openWindows[id]?.close()
                }
            } else {
                window.close()
            }
            return
        }
        if let ids = childrenByParent[winKey] {
            // window is the parent window
            for id in ids {
                openWindows[id]?.close()
            }
            return
        }
        if targetIdByWindow[winKey] != nil {
            window.close()
        } else {
            closeAll()
        }
    }

    /// Opens `target` in a new window, or brings the existing one forward if it's already open
    /// for this target — never creates a duplicate. `source` (typically the window the action
    /// was triggered from) is used both to cascade the new window's position and, if given, to
    /// close this window automatically when `source` itself closes.
    public func open(url: URL, target: SnapshotTarget, source: NSWindow?) {
        if let existing = openWindows[target.id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let resolvedSource = source ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
        let defaultWidth: CGFloat = 960
        let defaultHeight: CGFloat = 720
        let windowWidth: CGFloat
        let windowHeight: CGFloat
        if let resolvedSource {
            let sf = resolvedSource.frame
            windowWidth = max(defaultWidth, min(sf.width * 0.9, 1100))
            windowHeight = max(defaultHeight, min(sf.height * 0.9, 850))
        } else {
            windowWidth = defaultWidth
            windowHeight = defaultHeight
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // NSWindow defaults isReleasedWhenClosed to true, a pre-ARC behavior that double-frees
        // a manually constructed window under ARC. See the identical note in
        // DocumentWindowing.makeWindow — required for any NSWindow(...) created directly like this.
        window.isReleasedWhenClosed = false
        // Includes the snapshot's own label (e.g. "Figure 3"), not just the filename — every
        // snapshot window for the same document would otherwise show an identical title, making
        // them indistinguishable in the Window menu / Mission Control / Cmd-` cycling.
        window.title = "\(url.lastPathComponent) — \(target.label)"
        window.miniwindowTitle = target.label
        window.representedURL = url
        window.tabbingMode = .disallowed

        let view = PDFViewerMainView(
            initialFilePath: url.path,
            initialURL: url,
            initialTarget: target,
            isSnapshotWindow: true,
            onOpenNewTab: { _ in
                // Snapshot windows are for looking at one spot, not for browsing into other
                // documents — dropping a file here just isn't a supported action.
            }
        )
        let hostingController = NSHostingController(rootView: view)
        hostingController.view.setFrameSize(NSSize(width: windowWidth, height: windowHeight))
        window.contentViewController = hostingController

        window.setContentSize(NSSize(width: windowWidth, height: windowHeight))
        window.minSize = NSSize(width: 500, height: 400)

        if let resolvedSource {
            let sourceFrame = resolvedSource.frame
            let x = sourceFrame.minX + 40
            let y = max(50, sourceFrame.maxY - windowHeight - 40)
            window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        } else {
            window.center()
        }

        openWindows[target.id] = window
        let childKey = ObjectIdentifier(window)
        targetIdByWindow[childKey] = target.id
        NotificationCenter.default.addObserver(
            self, selector: #selector(snapshotWindowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: window
        )

        if let resolvedSource {
            let sourceKey = ObjectIdentifier(resolvedSource)
            let rootParentKey = parentKeyByChild[sourceKey] ?? sourceKey
            parentKeyByChild[childKey] = rootParentKey
            childrenByParent[rootParentKey, default: []].append(target.id)

            // If source is not already a child window, it's the root parent window.
            // Observe it if not already observed.
            if parentKeyByChild[sourceKey] == nil {
                if watchedParents.insert(sourceKey).inserted {
                    NotificationCenter.default.addObserver(
                        self, selector: #selector(sourceWindowWillClose(_:)),
                        name: NSWindow.willCloseNotification, object: resolvedSource
                    )
                }
            }
        }

        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the snapshot window for `id`, if one is open. Used to turn a snapshot card's
    /// "open" button into a "close" button once its window is already open.
    public func close(_ id: UUID) {
        openWindows[id]?.close()
    }

    @objc private func snapshotWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let winKey = ObjectIdentifier(window)
        if let parentKey = parentKeyByChild.removeValue(forKey: winKey),
           let id = targetIdByWindow[winKey] {
            childrenByParent[parentKey]?.removeAll(where: { $0 == id })
            if childrenByParent[parentKey]?.isEmpty == true {
                childrenByParent.removeValue(forKey: parentKey)
            }
        }
        guard let id = targetIdByWindow.removeValue(forKey: winKey) else { return }
        openWindows.removeValue(forKey: id)
    }

    @objc private func sourceWindowWillClose(_ notification: Notification) {
        guard let source = notification.object as? NSWindow else { return }
        let key = ObjectIdentifier(source)
        watchedParents.remove(key)
        guard let ids = childrenByParent.removeValue(forKey: key) else { return }
        for id in ids {
            openWindows[id]?.close()
        }
    }
}
