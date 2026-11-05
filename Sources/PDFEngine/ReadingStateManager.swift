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
import CoreGraphics
import CryptoKit

/// A document's remembered reading position, zoom, and saved snapshots.
public struct DocumentReadingState: Codable, Equatable, Sendable {
    public var lastPageIndex: Int
    public var zoomScale: CGFloat
    public var snapshots: [SnapshotTarget]
    /// The portable document key this state belongs to. Needed because the iCloud key-value store
    /// key is a fixed-length hash of it (see ReadingStateManager.kvsKey) and so can't be turned
    /// back into a path on another Mac.
    public var canonicalKey: String?
    /// When this state was last written — used to prune the least recently read documents.
    public var updatedAt: Date?
    /// Queries the user went to a match for in the Search sidebar, most recent first (see
    /// ReadingStateManager.addingRecentSearch). Optional so state saved before it existed decodes.
    public var recentSearches: [String]?

    public init(lastPageIndex: Int, zoomScale: CGFloat, snapshots: [SnapshotTarget], canonicalKey: String? = nil, updatedAt: Date? = nil, recentSearches: [String]? = nil) {
        self.lastPageIndex = lastPageIndex
        self.zoomScale = zoomScale
        self.snapshots = snapshots
        self.canonicalKey = canonicalKey
        self.updatedAt = updatedAt
        self.recentSearches = recentSearches
    }
}

/// Persists each document's last page, zoom, and snapshots across launches.
/// Supports both local path keys and canonical cloud provider keys for multi-device sync.
@MainActor
public final class ReadingStateManager: ObservableObject {
    public static let shared = ReadingStateManager()
    public static let didSyncExternallyNotification = Notification.Name("com.thomasderham.vectorpdf.readingstate.didSyncExternally")
    /// Posted when a document's recent searches change on this Mac. The object is the view model
    /// that changed them; userInfo["canonicalKey"] names the document.
    public static let recentSearchesDidChangeNotification = Notification.Name("com.thomasderham.vectorpdf.readingstate.recentSearchesDidChange")
    public static let maxRecentSearches = 10

    /// `list` with `query` moved (or added) to the front. A query differing only in case replaces
    /// the earlier one; blank queries are ignored.
    public static func addingRecentSearch(_ query: String, to list: [String]) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return list }
        let rest = list.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        return Array(([trimmed] + rest).prefix(maxRecentSearches))
    }
    private let userDefaultsKey = "com.thomasderham.vectorpdf.readingstate"
    private let kvsPrefix = "readingstate_"

    private var states: [String: DocumentReadingState] = [:]

    private static let cloudSyncDefaultsKey = "com.thomasderham.vectorpdf.syncReadingStateWithICloud"

    /// Whether reading state is also kept in iCloud key-value storage (on by default). It only
    /// takes effect in builds signed with the iCloud key-value storage entitlement.
    @Published public private(set) var isCloudSyncEnabled: Bool =
        UserDefaults.standard.object(forKey: cloudSyncDefaultsKey) as? Bool ?? true

    /// Turning sync off also deletes this app's entries from iCloud; turning it on uploads the
    /// state stored on this Mac and picks up other Macs'.
    public func setCloudSyncEnabled(_ enabled: Bool) {
        guard enabled != isCloudSyncEnabled else { return }
        isCloudSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.cloudSyncDefaultsKey)
        let store = NSUbiquitousKeyValueStore.default
        if enabled {
            for state in states.values {
                if let canonical = state.canonicalKey, let data = try? JSONEncoder().encode(state) {
                    store.set(data, forKey: kvsKey(for: canonical))
                }
            }
            store.synchronize()
            syncFromCloudKVS()
        } else {
            for key in store.dictionaryRepresentation.keys where key.hasPrefix(kvsPrefix) {
                store.removeObject(forKey: key)
            }
            store.synchronize()
        }
    }

    /// Past this many entries, the least recently updated ones are dropped (see pruneIfNeeded).
    private static let maxStoredStates = 500
    private static let prunedStateCount = 300

    /// NSUbiquitousKeyValueStore rejects keys longer than 64 bytes, which a prefixed filesystem path
    /// routinely exceeds — so the key is a fixed-length digest of the canonical document key.
    private func kvsKey(for canonical: String) -> String {
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return kvsPrefix + digest.prefix(20).map { String(format: "%02x", $0) }.joined()
    }

    private init() {
        load()
        setupCloudSync()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: DocumentReadingState].self, from: data) {
            self.states = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func setupCloudSync() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncFromCloudKVS()
            }
        }
        NSUbiquitousKeyValueStore.default.synchronize()
        syncFromCloudKVS()
    }

    private func syncFromCloudKVS() {
        guard isCloudSyncEnabled else { return }
        let dict = NSUbiquitousKeyValueStore.default.dictionaryRepresentation
        var hasChanges = false
        for (key, val) in dict where key.hasPrefix(kvsPrefix) {
            if let data = val as? Data,
               let decoded = try? JSONDecoder().decode(DocumentReadingState.self, from: data) {
                // Fallback for unhashed canonical keys.
                let canonicalKey = decoded.canonicalKey ?? String(key.dropFirst(kvsPrefix.count))
                if states[canonicalKey] != decoded {
                    states[canonicalKey] = decoded
                    hasChanges = true
                }
            }
        }
        if hasChanges {
            save()
            NotificationCenter.default.post(name: Self.didSyncExternallyNotification, object: self)
        }
    }

    /// Retrieves remembered reading state for a given document path.
    /// Checks the canonical cloud key first, then falls back to the exact local path,
    /// and checks cloud KVS if not cached locally.
    public func state(for path: String) -> DocumentReadingState? {
        let canonical = CloudStorageHelper.canonicalKey(for: path)

        if let state = states[canonical] {
            return state
        }
        if let state = states[path] {
            // Backfill canonical key for future cross-machine lookups
            if canonical != path {
                states[canonical] = state
                save()
            }
            return state
        }

        // Check if available directly in iCloud KVS
        let store = NSUbiquitousKeyValueStore.default
        if isCloudSyncEnabled,
           let kvsData = store.data(forKey: kvsKey(for: canonical)) ?? store.data(forKey: "\(kvsPrefix)\(canonical)"),
           let decoded = try? JSONDecoder().decode(DocumentReadingState.self, from: kvsData) {
            states[canonical] = decoded
            states[path] = decoded
            save()
            return decoded
        }

        return nil
    }

    /// Updates reading state for a document path, persisting to local storage and synchronizing
    /// to iCloud Key-Value Storage when available. `recentSearches` nil keeps the stored ones.
    public func updateState(for path: String, lastPageIndex: Int, zoomScale: CGFloat, snapshots: [SnapshotTarget], recentSearches: [String]? = nil) {
        let canonical = CloudStorageHelper.canonicalKey(for: path)
        let searches = recentSearches ?? (states[canonical] ?? states[path])?.recentSearches
        let newState = DocumentReadingState(lastPageIndex: lastPageIndex, zoomScale: zoomScale, snapshots: snapshots, canonicalKey: canonical, updatedAt: Date(), recentSearches: searches?.isEmpty == true ? nil : searches)

        // Store local path
        states[path] = newState

        // Store canonical cloud key (cross-machine continuity)
        if canonical != path {
            states[canonical] = newState
        }
        pruneIfNeeded()
        save()

        // Sync to NSUbiquitousKeyValueStore
        if isCloudSyncEnabled, let data = try? JSONEncoder().encode(newState) {
            NSUbiquitousKeyValueStore.default.set(data, forKey: kvsKey(for: canonical))
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    /// Keeps the stored state from growing without bound: once there are too many entries, drops the
    /// least recently updated ones (and their iCloud copies, which share a small total quota).
    private func pruneIfNeeded() {
        guard states.count > Self.maxStoredStates else { return }
        let oldestFirst = states.sorted { ($0.value.updatedAt ?? .distantPast) < ($1.value.updatedAt ?? .distantPast) }
        let removeCount = states.count - Self.prunedStateCount
        let store = NSUbiquitousKeyValueStore.default
        for (key, value) in oldestFirst.prefix(removeCount) {
            states.removeValue(forKey: key)
            if let canonical = value.canonicalKey, states[canonical] == nil {
                store.removeObject(forKey: kvsKey(for: canonical))
            }
        }
    }
}
