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
/// Only a change to the file itself counts: its modification date, size or identity (a file put in
/// its place). Changes to its attributes alone, which cloud file providers make all the time and
/// opening a file can make, don't: reloading on them reloads again and again.
///
/// The file coordinator keeps a presenter alive, so a watcher lasts until `cancel()`, which its
/// owner calls when it's done with it.
///
/// `@unchecked Sendable`: internal state changes are dispatched to `DispatchQueue.main` or serialized
/// on `presenterQueue`.
public final class FileChangeWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    /// What a change to the file changes.
    struct Stamp: Equatable {
        let modified: Date?
        let size: Int64?
        let fileNumber: Int?

        init?(path: String) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
            modified = attributes[.modificationDate] as? Date
            size = (attributes[.size] as? NSNumber)?.int64Value
            fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.intValue
        }
    }

    /// Where the file is: set on the presenter queue when it moves, read on the main thread and
    /// by the file coordinator, so behind a lock.
    private let pathLock = NSLock()
    private var _path: String
    private var path: String {
        get { pathLock.withLock { _path } }
        set { pathLock.withLock { _path = newValue } }
    }
    /// The file as it was last reported (or as it was when watching began).
    private var stamp: Stamp?
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
        self._path = path
        self.onChange = onChange
        self.onMove = onMove
        self.stamp = Stamp(path: path)
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
        newSource.setEventHandler { [weak self, unowned newSource] in
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
            // Missing (mid-replace, or deleted): the move or the next change says what happened.
            guard let now = Stamp(path: self.path), now != self.stamp else { return }
            self.stamp = now
            self.onChange()
        }
        debounceWorkItem = workItem
        // Debounce interval to coalesce write bursts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }
}
