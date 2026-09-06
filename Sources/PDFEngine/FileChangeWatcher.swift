import Foundation

/// Watches a single file path for external changes (edits from another app) and calls `onChange`
/// once things settle. Not an actor/MainActor type itself — `onChange` fires on the main queue, but
/// callers that touch `@MainActor` state should still hop explicitly (Swift's isolation checking
/// can't see through a plain `DispatchQueue.main` callback).
///
/// Two things make watching a single path harder than "open it and wait for a write event":
/// - A single save in another app can produce several write events in quick succession, so a
///   change is only reported after a short debounce once they stop, rather than once per event.
/// - Most apps don't write in place — they write a temp file and rename it over the original,
///   which unlinks the inode this watches out from under it. Seeing `.delete`/`.rename` on the
///   watched descriptor, this closes it and re-opens the same path fresh, which is what actually
///   picks up the replacement file. Without this, only apps that write in place would ever be
///   noticed.
/// `@unchecked Sendable`: every access to this class's state happens inside a closure dispatched
/// onto `DispatchQueue.main` (the DispatchSource's event handler, the delete/rename re-watch retry,
/// and the debounce timer all target `.main` explicitly) — genuinely single-queue-confined, just not
/// something the compiler can verify without either full @MainActor isolation (which would force an
/// actor hop inside plain DispatchSource callbacks that aren't themselves isolated) or this.
public final class FileChangeWatcher: @unchecked Sendable {
    private let path: String
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?

    public init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
        startWatching()
    }

    deinit {
        source?.cancel()
        debounceWorkItem?.cancel()
    }

    private func startWatching(allowRetry: Bool = true) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            // Most likely raced a rename-based save (briefly missing while the replacement is put
            // in place) — one short retry covers that without retrying forever if the file is
            // genuinely gone.
            if allowRetry {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.startWatching(allowRetry: false)
                }
            }
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: .main
        )
        newSource.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = newSource.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.source?.cancel()
                self.startWatching()
                self.scheduleDebouncedNotify()
                return
            }
            // A bare .attrib event (no .write/.extend) is typically just a metadata touch (e.g.
            // Spotlight re-indexing), not a real content change — ignore it.
            guard flags.contains(.write) || flags.contains(.extend) else { return }
            self.scheduleDebouncedNotify()
        }
        newSource.setCancelHandler {
            close(fd)
        }
        newSource.resume()
        source = newSource
    }

    private func scheduleDebouncedNotify() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWorkItem = workItem
        // Long enough to coalesce a burst of writes from one save; short enough that the reload
        // still feels prompt rather than delayed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }
}
