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

/// The recently opened files listed in File > Open Recent, the Dock icon's Open Recent submenu
/// and the Start screen, most recent first.
///
/// Kept here rather than in NSDocumentController's list: the Dock draws that list itself, flat at
/// the top of the app's menu, where it can't be moved into a submenu. Each file is kept as a
/// bookmark, so the list follows it when it's moved or renamed.
///
/// macOS adds to that list from outside the app, too: a file opened from Finder lands there
/// without AppKit's `noteNewRecentDocumentURL` being called, and the app can't see it while it
/// runs. So the app sets its own NSRecentDocumentsLimit to 0, which macOS respects, and the list
/// stays empty; this list's size follows the system-wide setting instead.
@MainActor
public final class RecentDocuments {
    public static let shared = RecentDocuments(defaults: .standard)

    private let defaults: UserDefaults
    private let key: String
    private let maximumCount: () -> Int

    /// `maximumCount` defaults to the "Recent documents, apps and servers" setting in System
    /// Settings > Desktop & Dock (0 when it's off). The first time, the files in `systemList` are
    /// taken over; then the system's list is limited to none, so the Dock stops showing it.
    init(
        defaults: UserDefaults,
        key: String = "RecentDocuments",
        importingFrom systemList: NSDocumentController? = .shared,
        maximumCount: @escaping () -> Int = RecentDocuments.systemLimit
    ) {
        self.defaults = defaults
        self.key = key
        self.maximumCount = maximumCount
        if let systemList {
            importList(of: systemList)
            defaults.set(0, forKey: Self.limitKey)
        }
    }

    /// The key for how many recent documents macOS keeps: set system-wide by System Settings,
    /// and for this app to 0 (see above).
    nonisolated static let limitKey = "NSRecentDocumentsLimit"

    /// The system-wide limit, read past the app's own 0. 10 when it's never been changed.
    nonisolated static func systemLimit() -> Int {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return (global?[limitKey] as? NSNumber)?.intValue ?? 10
    }

    /// The files that still exist, most recent first, at most the system's limit.
    public var urls: [URL] {
        let limit = maximumCount()
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        var urls: [URL] = []
        for entry in entries {
            guard let url = resolve(entry), FileManager.default.fileExists(atPath: url.path) else { continue }
            guard seen.insert(Self.key(for: url)).inserted else { continue }
            urls.append(url)
            if urls.count == limit { break }
        }
        return urls
    }

    /// Moves `url` to the top of the list.
    public func note(_ url: URL) {
        guard url.isFileURL else { return }
        let key = Self.key(for: url)
        var entries = entries.filter { entry in resolve(entry).map(Self.key(for:)) != key }
        entries.insert(Self.entry(for: url), at: 0)
        // Keep a few more than are shown, so files that have gone missing don't shorten the list.
        save(Array(entries.prefix(max(maximumCount(), 10) * 2)))
    }

    public func clear() {
        save([])
    }

    // MARK: - Storage

    private typealias Entry = [String: Any]

    private var entries: [Entry] {
        defaults.array(forKey: key) as? [Entry] ?? []
    }

    private func save(_ entries: [Entry]) {
        defaults.set(entries, forKey: key)
    }

    private static func entry(for url: URL) -> Entry {
        var entry: Entry = ["path": url.path]
        if let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            entry["bookmark"] = bookmark
        }
        return entry
    }

    private func resolve(_ entry: Entry) -> URL? {
        if let bookmark = entry["bookmark"] as? Data {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                relativeTo: nil, bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        return (entry["path"] as? String).map { URL(fileURLWithPath: $0) }
    }

    private static func key(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Takes over the files in NSDocumentController's list, once, and empties it so the Dock
    /// stops showing them.
    private func importList(of controller: NSDocumentController) {
        guard defaults.object(forKey: key) == nil else { return }
        save(controller.recentDocumentURLs.filter(\.isFileURL).map(Self.entry(for:)))
        controller.clearRecentDocuments(nil)
    }
}
