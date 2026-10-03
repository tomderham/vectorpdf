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

/// Recognized storage categories on macOS:
/// - `iCloudDrive`: Apple's native iCloud Drive (special system integration, ubiquity containers, KVS).
/// - `cloudStorage`: Third-party file providers (Google Drive, Dropbox, OneDrive, Box) under `~/Library/CloudStorage`.
/// - `local`: Standard local volume or disk storage.
public enum StorageProvider: String, Sendable, CaseIterable {
    case iCloudDrive = "iCloud Drive"
    case cloudStorage = "Cloud Storage"
    case local = "Local Disk"
}

/// Detailed information about a document's storage provider, sync status, and cloud integration.
public struct StorageInfo: Sendable, Equatable {
    public let provider: StorageProvider
    public let providerName: String
    public let systemImage: String
    public let statusDescription: String
    public let isCloudManaged: Bool
    public let isDownloaded: Bool
    public let isDownloading: Bool

    public init(
        provider: StorageProvider,
        providerName: String,
        systemImage: String,
        statusDescription: String,
        isCloudManaged: Bool,
        isDownloaded: Bool,
        isDownloading: Bool
    ) {
        self.provider = provider
        self.providerName = providerName
        self.systemImage = systemImage
        self.statusDescription = statusDescription
        self.isCloudManaged = isCloudManaged
        self.isDownloaded = isDownloaded
        self.isDownloading = isDownloading
    }
}

/// Helpers for detecting cloud providers (iCloud Drive vs Cloud Storage),
/// resolving canonical keys across machines, handling evicted/dataless files, and coordinating downloads.
public enum CloudStorageHelper: Sendable {

    // MARK: - Path Normalization & Canonical Keys

    private static var homeDirectoryPath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Computes a portable, machine-independent canonical key for a document path.
    /// This allows reading position, snapshots, and tab groups to sync across multiple Macs
    /// with different usernames and home directories.
    public static func canonicalKey(for path: String) -> String {
        let normalized = (path as NSString).standardizingPath
        let home = homeDirectoryPath

        // 1. iCloud Drive paths (under ~/Library/Mobile Documents)
        let iCloudDocsPrefix = (home as NSString).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if normalized.hasPrefix(iCloudDocsPrefix) {
            let relative = String(normalized.dropFirst(iCloudDocsPrefix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "icloud:com~apple~CloudDocs/\(relative)"
        }

        let mobileDocsPrefix = (home as NSString).appendingPathComponent("Library/Mobile Documents")
        if normalized.hasPrefix(mobileDocsPrefix) {
            let relative = String(normalized.dropFirst(mobileDocsPrefix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "icloud:\(relative)"
        }

        // 2. CloudStorage provider paths (under ~/Library/CloudStorage, e.g. Google Drive, OneDrive, Dropbox)
        // MUST be checked before Desktop/Documents ubiquity checks.
        let cloudStoragePrefix = (home as NSString).appendingPathComponent("Library/CloudStorage")
        if normalized.hasPrefix(cloudStoragePrefix) {
            let relative = String(normalized.dropFirst(cloudStoragePrefix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "cloudstorage:\(relative)"
        }

        // Custom volume mount points
        if normalized.hasPrefix("/Volumes/GoogleDrive/") {
            let relative = String(normalized.dropFirst("/Volumes/GoogleDrive/".count))
            return "cloudstorage:GoogleDrive/\(relative)"
        }

        // 3. Check if Desktop or Documents are synced via iCloud Drive
        let documentsPrefix = (home as NSString).appendingPathComponent("Documents")
        let desktopPrefix = (home as NSString).appendingPathComponent("Desktop")
        if normalized.hasPrefix(documentsPrefix) {
            let fileURL = URL(fileURLWithPath: normalized)
            if isUbiquitous(url: fileURL) {
                let relative = String(normalized.dropFirst(documentsPrefix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return "icloud:Documents/\(relative)"
            }
        }

        if normalized.hasPrefix(desktopPrefix) {
            let fileURL = URL(fileURLWithPath: normalized)
            if isUbiquitous(url: fileURL) {
                let relative = String(normalized.dropFirst(desktopPrefix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return "icloud:Desktop/\(relative)"
            }
        }

        // 4. Fallback to local path key
        return normalized
    }

    /// Resolves a canonical key back to a local filesystem path on the current machine, if it exists.
    public static func resolveLocalPath(for canonicalKey: String) -> String? {
        let home = homeDirectoryPath

        if canonicalKey.hasPrefix("icloud:com~apple~CloudDocs/") {
            let rel = String(canonicalKey.dropFirst("icloud:com~apple~CloudDocs/".count))
            let path = (home as NSString).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/\(rel)")
            if FileManager.default.fileExists(atPath: path) { return path }
        } else if canonicalKey.hasPrefix("icloud:Documents/") {
            let rel = String(canonicalKey.dropFirst("icloud:Documents/".count))
            let path = (home as NSString).appendingPathComponent("Documents/\(rel)")
            if FileManager.default.fileExists(atPath: path) { return path }
        } else if canonicalKey.hasPrefix("icloud:Desktop/") {
            let rel = String(canonicalKey.dropFirst("icloud:Desktop/".count))
            let path = (home as NSString).appendingPathComponent("Desktop/\(rel)")
            if FileManager.default.fileExists(atPath: path) { return path }
        } else if canonicalKey.hasPrefix("icloud:") {
            let rel = String(canonicalKey.dropFirst("icloud:".count))
            let path = (home as NSString).appendingPathComponent("Library/Mobile Documents/\(rel)")
            if FileManager.default.fileExists(atPath: path) { return path }
        } else if canonicalKey.hasPrefix("cloudstorage:") {
            let rest = String(canonicalKey.dropFirst("cloudstorage:".count))
            let cloudStorageDir = (home as NSString).appendingPathComponent("Library/CloudStorage")
            let direct = (cloudStorageDir as NSString).appendingPathComponent(rest)
            if FileManager.default.fileExists(atPath: direct) { return direct }

            // If account differs, try matching any folder in Library/CloudStorage with the subpath
            if let slashIdx = rest.firstIndex(of: "/") {
                let subPath = String(rest[rest.index(after: slashIdx)...])
                if let entries = try? FileManager.default.contentsOfDirectory(atPath: cloudStorageDir) {
                    for entry in entries {
                        let candidate = ((cloudStorageDir as NSString).appendingPathComponent(entry) as NSString).appendingPathComponent(subPath)
                        if FileManager.default.fileExists(atPath: candidate) { return candidate }
                    }
                }
            }
        } else if canonicalKey.hasPrefix("googledrive:") {
            // Match provider prefix fallback
            let rest = String(canonicalKey.dropFirst("googledrive:".count))
            let cloudStorageDir = (home as NSString).appendingPathComponent("Library/CloudStorage")
            let direct = (cloudStorageDir as NSString).appendingPathComponent(rest)
            if FileManager.default.fileExists(atPath: direct) { return direct }
            if let slashIdx = rest.firstIndex(of: "/") {
                let subPath = String(rest[rest.index(after: slashIdx)...])
                if let entries = try? FileManager.default.contentsOfDirectory(atPath: cloudStorageDir) {
                    for entry in entries where entry.hasPrefix("GoogleDrive-") {
                        let candidate = ((cloudStorageDir as NSString).appendingPathComponent(entry) as NSString).appendingPathComponent(subPath)
                        if FileManager.default.fileExists(atPath: candidate) { return candidate }
                    }
                }
            }
        }

        // Return path if it's already an existing local path
        if FileManager.default.fileExists(atPath: canonicalKey) {
            return canonicalKey
        }
        return nil
    }

    // MARK: - Provider Detection & Status

    /// Determines the storage provider for a given local file path.
    public static func detectProvider(for path: String) -> StorageProvider {
        let normalized = (path as NSString).standardizingPath
        let home = homeDirectoryPath

        // 1. iCloud Drive paths (under ~/Library/Mobile Documents)
        let mobileDocsPrefix = (home as NSString).appendingPathComponent("Library/Mobile Documents")
        if normalized.hasPrefix(mobileDocsPrefix) || normalized.contains("/Library/Mobile Documents/") {
            return .iCloudDrive
        }

        // 2. CloudStorage provider paths (under ~/Library/CloudStorage, e.g. Google Drive, OneDrive, Dropbox, Box)
        // Must be checked BEFORE any general isUbiquitous checks, because macOS FileProvider marks all
        // CloudStorage files as ubiquitous items.
        let cloudStoragePrefix = (home as NSString).appendingPathComponent("Library/CloudStorage")
        if normalized.hasPrefix(cloudStoragePrefix) || normalized.contains("/Library/CloudStorage/") {
            return .cloudStorage
        }

        if normalized.hasPrefix("/Volumes/GoogleDrive") || normalized.contains("/Google Drive/") || normalized.contains("/Dropbox/") || normalized.contains("/OneDrive/") || normalized.contains("/GoogleDrive-") {
            return .cloudStorage
        }

        // 3. Check if Desktop or Documents are synced via iCloud Drive
        let documentsPrefix = (home as NSString).appendingPathComponent("Documents")
        let desktopPrefix = (home as NSString).appendingPathComponent("Desktop")
        if normalized.hasPrefix(documentsPrefix) || normalized.hasPrefix(desktopPrefix) {
            let fileURL = URL(fileURLWithPath: normalized)
            if isUbiquitous(url: fileURL) {
                return .iCloudDrive
            }
        }

        return .local
    }

    /// Checks if a URL represents a ubiquitous item (iCloud Drive or FileProvider).
    public static func isUbiquitous(url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]),
           values.isUbiquitousItem == true {
            return true
        }
        return false
    }

    /// Resolves an actual URL, unwrapping `.filename.pdf.icloud` placeholders if present.
    public static func resolveActualURL(for url: URL) -> URL {
        let filename = url.lastPathComponent
        if filename.hasPrefix(".") && filename.hasSuffix(".icloud") {
            let trimmed = String(filename.dropFirst().dropLast(".icloud".count))
            let resolved = url.deletingLastPathComponent().appendingPathComponent(trimmed)
            return resolved
        }
        return url
    }

    /// Checks whether the file is an evicted/dataless cloud placeholder or currently downloading.
    public static func checkDownloadStatus(for url: URL) -> (isEvicted: Bool, isDownloading: Bool) {
        let resolved = resolveActualURL(for: url)

        // Check if it was an .icloud placeholder
        if url.lastPathComponent.hasPrefix(".") && url.lastPathComponent.hasSuffix(".icloud") {
            return (isEvicted: true, isDownloading: false)
        }

        let provider = detectProvider(for: resolved.path)
        guard provider == .iCloudDrive || provider == .cloudStorage else {
            return (isEvicted: false, isDownloading: false)
        }

        if let values = try? resolved.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey
        ]) {
            if values.isUbiquitousItem == true {
                let status = values.ubiquitousItemDownloadingStatus
                let isDownloading = values.ubiquitousItemIsDownloading ?? false
                let isNotDownloaded = (status == .notDownloaded)
                return (isEvicted: isNotDownloaded, isDownloading: isDownloading)
            }
        }

        return (isEvicted: false, isDownloading: false)
    }

    /// Triggers download of an ubiquitous item if not already downloaded.
    public static func startDownloadIfNeeded(for url: URL) throws {
        let targetURL = resolveActualURL(for: url)
        try FileManager.default.startDownloadingUbiquitousItem(at: targetURL)
    }

    /// Inspects a file path and returns a comprehensive `StorageInfo` struct.
    public static func storageInfo(for path: String) -> StorageInfo {
        let provider = detectProvider(for: path)
        let fileURL = URL(fileURLWithPath: (path as NSString).standardizingPath)

        switch provider {
        case .iCloudDrive:
            let (isEvicted, isDownloading) = checkDownloadStatus(for: fileURL)
            let status: String
            if isDownloading {
                status = "Downloading from iCloud…"
            } else if isEvicted {
                status = "Stored in iCloud Drive (Not Downloaded)"
            } else {
                status = "Synced with iCloud Drive"
            }
            return StorageInfo(
                provider: .iCloudDrive,
                providerName: "iCloud Drive",
                systemImage: "icloud",
                statusDescription: status,
                isCloudManaged: true,
                isDownloaded: !isEvicted,
                isDownloading: isDownloading
            )

        case .cloudStorage:
            let (isEvicted, isDownloading) = checkDownloadStatus(for: fileURL)
            // Detect service name if obvious from directory structure
            let normalized = (path as NSString).standardizingPath
            var serviceName = "Cloud Storage"
            if normalized.contains("GoogleDrive") || normalized.contains("Google Drive") {
                serviceName = "Google Drive"
            } else if normalized.contains("OneDrive") {
                serviceName = "OneDrive"
            } else if normalized.contains("Dropbox") {
                serviceName = "Dropbox"
            } else if normalized.contains("Box") {
                serviceName = "Box"
            }

            let status: String
            if isDownloading {
                status = "Downloading from \(serviceName)…"
            } else if isEvicted {
                status = "Stored in \(serviceName) (Not Downloaded)"
            } else {
                status = "Managed by \(serviceName)"
            }
            return StorageInfo(
                provider: .cloudStorage,
                providerName: "Cloud Storage",
                systemImage: "arrow.triangle.2.circlepath",
                statusDescription: status,
                isCloudManaged: true,
                isDownloaded: !isEvicted,
                isDownloading: isDownloading
            )

        case .local:
            return StorageInfo(
                provider: .local,
                providerName: "Local Disk",
                systemImage: "internaldrive",
                statusDescription: "Stored locally on disk",
                isCloudManaged: false,
                isDownloaded: true,
                isDownloading: false
            )
        }
    }
}
