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
    /// card, a cross-reference link, a selection, or a plain page location). Offered from the
    /// Snapshots panel so they don't have to be closed one at a time once several have piled up.
    public func closeAll() {
        for window in openWindows.values {
            window.close()
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

        let window = NSWindow(
            // Smaller than a regular reading window/tab — visually signals "this is a quick
            // snapshot, not another full reading session", and takes less screen space as
            // these accumulate side by side.
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
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
        window.contentView = NSHostingView(rootView: view)

        if let source {
            let sourceFrame = source.frame
            window.setFrameOrigin(NSPoint(x: sourceFrame.origin.x + 40, y: sourceFrame.origin.y - 40))
        } else {
            window.center()
        }

        openWindows[target.id] = window
        targetIdByWindow[ObjectIdentifier(window)] = target.id
        NotificationCenter.default.addObserver(
            self, selector: #selector(snapshotWindowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: window
        )

        if let source {
            childrenByParent[ObjectIdentifier(source), default: []].append(target.id)
            // Only install one observer per source window no matter how many snapshot windows
            // get opened from it — `watchedParents` guards against duplicates.
            if watchedParents.insert(ObjectIdentifier(source)).inserted {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(sourceWindowWillClose(_:)),
                    name: NSWindow.willCloseNotification, object: source
                )
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
        guard let window = notification.object as? NSWindow,
              let id = targetIdByWindow.removeValue(forKey: ObjectIdentifier(window)) else { return }
        openWindows.removeValue(forKey: id)
        // NotificationCenter does not retain the filter object, so registrations referencing
        // an already-closed window are inert without requiring complex observer deregistration
        // between parent and child snapshot windows.
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
