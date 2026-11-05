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
import Foundation

/// Everything VectorPDF keeps on disk besides preferences, and the ways to tidy or remove it.
/// PRIVACY.md lists the same locations; keep the two in step.
@MainActor
public enum StoredData {
    /// What Settings shows under Storage.
    public struct Usage: Equatable, Sendable {
        public var agentIndexBytes: Int64 = 0
        public var thumbnailBytes: Int64 = 0
        public var temporaryBytes: Int64 = 0
        public var documentCount: Int = 0
    }

    /// Files left over from earlier sessions are at least this old. A day is far longer than any
    /// save, print or export takes.
    nonisolated static let staleAge: TimeInterval = 24 * 60 * 60

    nonisolated static var temporaryDirectory: URL { FileManager.default.temporaryDirectory }

    /// Application Support/VectorPDF: the Agent's indexes and the tour's copy.
    static var supportDirectory: URL {
        SemanticIndexStore.defaultDirectory.deletingLastPathComponent()
    }

    /// VectorPDF's temporary files and folders: working copies, save/print/flatten/export copies
    /// and downloaded updates. Every name starts with "VectorPDF".
    nonisolated static func temporaryItems(in directory: URL = temporaryDirectory) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("VectorPDF") }
    }

    /// Working copies of documents open now, which must never be deleted.
    static var workingCopiesInUse: Set<String> {
        Set(PDFViewerAppCoordinator.shared.openViewModels.compactMap(\.workingCopyPath).map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })
    }

    /// Deletes temporary items older than `staleAge` (all of them when `olderThan` is nil),
    /// except those in `keep`.
    nonisolated static func removeTemporaryItems(in directory: URL = temporaryDirectory, olderThan age: TimeInterval?, keeping keep: Set<String>, now: Date = Date()) {
        for url in temporaryItems(in: directory) where !keep.contains(url.standardizedFileURL.path) {
            if let age {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
                guard now.timeIntervalSince(modified) > age else { continue }
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Deletes anchor thumbnails no stored or open anchor uses, once they're `staleAge` old (an
    /// anchor's thumbnail can be written just before its document's state is saved).
    nonisolated static func removeUnusedThumbnails(in directory: URL = SnapshotTarget.cacheDirectory, keeping ids: Set<UUID>, olderThan age: TimeInterval = staleAge, now: Date = Date()) {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in urls {
            if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), ids.contains(id) { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
            guard now.timeIntervalSince(modified) > age else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// IDs of every anchor in stored reading state or in an open document.
    static var anchorIDsInUse: Set<UUID> {
        ReadingStateManager.shared.storedSnapshotIDs.union(
            PDFViewerAppCoordinator.shared.openViewModels.flatMap { $0.activeSnapshots.map(\.id) })
    }

    /// Run at launch: removes what earlier sessions left behind (a crash leaves working copies;
    /// an installed update leaves its disk image) and trims the Agent's index cache.
    public static func cleanUpAtLaunch() {
        guard !PDFViewerViewModel.isRunningTests else { return }
        let keep = workingCopiesInUse
        let anchorIDs = anchorIDsInUse
        Task.detached(priority: .background) {
            removeTemporaryItems(olderThan: staleAge, keeping: keep)
            removeUnusedThumbnails(keeping: anchorIDs)
            await SemanticIndexStore.shared.prune()
        }
    }

    public static func usage() async -> Usage {
        let agentBytes = await SemanticIndexStore.shared.totalBytes()
        let documentCount = ReadingStateManager.shared.documentCount
        return await Task.detached(priority: .utility) {
            var usage = Usage()
            usage.agentIndexBytes = agentBytes
            usage.thumbnailBytes = directorySize(SnapshotTarget.cacheDirectory)
            usage.temporaryBytes = temporaryItems().reduce(0) { $0 + directorySize($1) }
            usage.documentCount = documentCount
            return usage
        }.value
    }

    nonisolated static func directorySize(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let item = enumerator?.nextObject() as? URL {
            total += Int64((try? item.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Deletes every Agent index. Open documents build theirs again when the Agent tab next needs it.
    public static func clearAgentIndexes() async {
        for viewModel in PDFViewerAppCoordinator.shared.openViewModels {
            viewModel.invalidateAgentIndex(deleteCache: false)
        }
        await SemanticIndexStore.shared.removeAll()
    }

    /// Forgets every document's reading position, anchors and recent searches, on this Mac and in
    /// iCloud, including those of open documents.
    public static func clearReadingHistory() {
        for viewModel in PDFViewerAppCoordinator.shared.openViewModels {
            viewModel.activeSnapshots = []
            viewModel.recentSearches = []
        }
        ReadingStateManager.shared.removeAll()
        try? FileManager.default.removeItem(at: SnapshotTarget.cacheDirectory)
    }

    /// Why everything can't be removed now, or nil if it can.
    public static var removeAllBlocker: String? {
        let edited = PDFViewerAppCoordinator.shared.openViewModels.contains { $0.isDocumentEdited }
        return edited ? "Save or close the documents with unsaved changes first." : nil
    }

    /// Removes everything VectorPDF has stored (reading history here and in iCloud, Agent
    /// indexes, thumbnails, temporary files, the tour's copy, API keys and preferences) and quits.
    /// Does nothing while a document has unsaved changes (see removeAllBlocker).
    public static func removeAllAndQuit() async {
        guard removeAllBlocker == nil else { return }
        clearReadingHistory()
        ReadingStateManager.shared.suspendPersistence()
        await clearAgentIndexes()
        try? FileManager.default.removeItem(at: supportDirectory)
        removeTemporaryItems(olderThan: nil, keeping: [])
        for service in OnlineModelService.allCases {
            APIKeyStore.setKey(nil, for: service)
        }
        guard !PDFViewerViewModel.isRunningTests, let domain = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        NSApp.terminate(nil)
    }
}
