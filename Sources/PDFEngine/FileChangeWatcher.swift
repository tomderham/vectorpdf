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

import Foundation

/// Watches a single file path for external changes (edits from another app, cloud sync updates, or
/// file moves/renames). Combines `NSFilePresenter` (for native macOS file coordination, iCloud Drive
/// sync, and Finder rename/move tracking) with a low-level BSD `DispatchSource` kernel watcher
/// (guaranteeing that uncoordinated writes from arbitrary external tools, CLI scripts, or editors
/// continue to be detected reliably).
///
/// `@unchecked Sendable`: internal state changes are dispatched to `DispatchQueue.main` or serialized
/// on `presenterQueue`.
public final class FileChangeWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    private var path: String
    private let onChange: () -> Void
    private let onMove: ((URL) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private var isCancelled: Bool = false

    private let presenterQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "com.thomasderham.vectorpdf.filepresenter"
        return q
    }()

    // MARK: - NSFilePresenter Properties

    public var presentedItemURL: URL? {
        URL(fileURLWithPath: path)
    }

    public var presentedItemOperationQueue: OperationQueue {
        presenterQueue
    }

    // MARK: - Initialization

    public init(
        path: String,
        onChange: @escaping () -> Void,
        onMove: ((URL) -> Void)? = nil
    ) {
        self.path = path
        self.onChange = onChange
        self.onMove = onMove
        super.init()

        NSFileCoordinator.addFilePresenter(self)
        startWatching()
    }

    deinit {
        cancel()
    }

    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        NSFileCoordinator.removeFilePresenter(self)
        source?.cancel()
        source = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }

    // MARK: - NSFilePresenter Callbacks

    public func presentedItemDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isCancelled else { return }
            self.scheduleDebouncedNotify()
        }
    }

    public func presentedItemDidGain(_ version: NSFileVersion) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isCancelled else { return }
            self.scheduleDebouncedNotify()
        }
    }

    public func presentedItemDidMove(to newURL: URL) {
        self.path = newURL.path
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isCancelled else { return }
            self.source?.cancel()
            self.source = nil
            self.startWatching()
            self.onMove?(newURL)
        }
    }

    // MARK: - DispatchSource Low-Level Kernel Watching

    private func startWatching(allowRetry: Bool = true) {
        guard !isCancelled else { return }
        let currentPath = self.path
        let fd = open(currentPath, O_EVTONLY)
        guard fd >= 0 else {
            // Retry in case file was temporarily absent during atomic rename.
            if allowRetry {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self, !self.isCancelled, self.path == currentPath else { return }
                    self.startWatching(allowRetry: false)
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
            guard let self, !self.isCancelled else { return }
            let flags = newSource.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.source?.cancel()
                self.source = nil
                self.startWatching()
                self.scheduleDebouncedNotify()
                return
            }
            // Ignore metadata-only attribute events.
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
        guard !isCancelled else { return }
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isCancelled else { return }
            self.onChange()
        }
        debounceWorkItem = workItem
        // Debounce interval to coalesce write bursts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }
}
