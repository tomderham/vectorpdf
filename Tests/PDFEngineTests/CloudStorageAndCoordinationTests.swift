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
import Testing
@testable import PDFEngine

@Suite("Cloud Storage & Coordinated Saving Tests")
struct CloudStorageAndCoordinationTests {

    @Test("CloudStorageHelper correctly detects cloud providers and local storage")
    func testProviderDetection() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let icloudPath = (home as NSString).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Research/paper.pdf")
        #expect(CloudStorageHelper.detectProvider(for: icloudPath) == .iCloudDrive)

        let gdrivePath = (home as NSString).appendingPathComponent("Library/CloudStorage/GoogleDrive-user@domain.com/My Drive/spec.pdf")
        #expect(CloudStorageHelper.detectProvider(for: gdrivePath) == .cloudStorage)

        let onedrivePath = (home as NSString).appendingPathComponent("Library/CloudStorage/OneDrive-Company/doc.pdf")
        #expect(CloudStorageHelper.detectProvider(for: onedrivePath) == .cloudStorage)

        let dropboxPath = (home as NSString).appendingPathComponent("Library/CloudStorage/Dropbox/notes.pdf")
        #expect(CloudStorageHelper.detectProvider(for: dropboxPath) == .cloudStorage)

        // Sample path from Google Drive
        let userGdrivePath = "/Users/example/Library/CloudStorage/GoogleDrive-user@example.com/My Drive/Documents/sample_report.pdf"
        #expect(CloudStorageHelper.detectProvider(for: userGdrivePath) == .cloudStorage)

        let localPath = "/tmp/local_test.pdf"
        #expect(CloudStorageHelper.detectProvider(for: localPath) == .local)
    }

    @Test("CloudStorageHelper generates portable canonical keys across machines")
    func testCanonicalKeys() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // iCloud Drive
        let icloudPath = (home as NSString).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Books/deep_learning.pdf")
        let icloudKey = CloudStorageHelper.canonicalKey(for: icloudPath)
        #expect(icloudKey == "icloud:com~apple~CloudDocs/Books/deep_learning.pdf")

        // Google Drive / CloudStorage
        let gdrivePath = (home as NSString).appendingPathComponent("Library/CloudStorage/GoogleDrive-user@example.com/My Drive/specs/v1.pdf")
        let gdriveKey = CloudStorageHelper.canonicalKey(for: gdrivePath)
        #expect(gdriveKey.hasPrefix("cloudstorage:GoogleDrive-user@example.com/My Drive/specs/v1.pdf"))

        // Unwrapping .icloud placeholder
        let placeholderURL = URL(fileURLWithPath: "/Users/example/Library/Mobile Documents/com~apple~CloudDocs/.important.pdf.icloud")
        let resolvedURL = CloudStorageHelper.resolveActualURL(for: placeholderURL)
        #expect(resolvedURL.lastPathComponent == "important.pdf")
    }

    @Test("StorageInfo metadata reporting")
    func testStorageInfoReporting() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let icloudPath = (home as NSString).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/doc.pdf")
        let info = CloudStorageHelper.storageInfo(for: icloudPath)

        #expect(info.provider == .iCloudDrive)
        #expect(info.providerName == "iCloud Drive")
        #expect(info.systemImage == "icloud")
        #expect(info.isCloudManaged == true)

        let userGdrivePath = "/Users/example/Library/CloudStorage/GoogleDrive-user@example.com/My Drive/Documents/sample_report.pdf"
        let gdriveInfo = CloudStorageHelper.storageInfo(for: userGdrivePath)
        #expect(gdriveInfo.provider == .cloudStorage)
        #expect(gdriveInfo.providerName == "Cloud Storage")
        #expect(gdriveInfo.systemImage == "arrow.triangle.2.circlepath")
        #expect(gdriveInfo.statusDescription.contains("Google Drive"))
        #expect(gdriveInfo.isCloudManaged == true)

        let localInfo = CloudStorageHelper.storageInfo(for: "/tmp/local.pdf")
        #expect(localInfo.provider == .local)
        #expect(localInfo.isCloudManaged == false)
    }

    @Test("ReadingStateManager resolves and persists canonical and local keys")
    @MainActor
    func testReadingStateCanonicalKeys() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let icloudPath = (home as NSString).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Papers/attention.pdf")

        let manager = ReadingStateManager.shared
        manager.updateState(for: icloudPath, lastPageIndex: 42, zoomScale: 1.75, snapshots: [])

        // Can look up by local path
        let stateByPath = manager.state(for: icloudPath)
        #expect(stateByPath != nil)
        #expect(stateByPath?.lastPageIndex == 42)
        #expect(stateByPath?.zoomScale == 1.75)

        // Lookup by canonical key directly
        let canonicalKey = CloudStorageHelper.canonicalKey(for: icloudPath)
        let stateByCanonical = manager.state(for: canonicalKey)
        #expect(stateByCanonical != nil)
        #expect(stateByCanonical?.lastPageIndex == 42)
    }

    @Test("Coordinated save writes safely without leaving temporary .~ files in the document directory")
    func testCoordinatedSaveCleanliness() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pdfURL = tempDir.appendingPathComponent("sample_coordinated.pdf")
        createSamplePDF(at: pdfURL)

        let doc = try PDFDocumentCore(filePath: pdfURL.path)
        #expect(doc.pageCount == 2)

        // Perform save
        try doc.save(to: pdfURL.path)

        // Ensure target exists and is readable
        #expect(FileManager.default.fileExists(atPath: pdfURL.path))

        // Ensure NO .~*.tmp or hidden temp files were left in the document directory
        let dirContents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let tempFiles = dirContents.filter { $0.hasPrefix(".~") || $0.hasSuffix(".tmp") }
        #expect(tempFiles.isEmpty)

        // Update file path
        let renamedPath = tempDir.appendingPathComponent("sample_renamed.pdf").path
        doc.updateFilePath(renamedPath)
        #expect(doc.filePath == renamedPath)
    }

    @Test("FileChangeWatcher conforms to NSFilePresenter and tracks move")
    func testFileChangeWatcherPresenter() {
        let tempPath = "/tmp/test_watcher_\(UUID().uuidString).pdf"
        let watcher = FileChangeWatcher(
            path: tempPath,
            onChange: {},
            onMove: { _ in }
        )

        #expect(watcher.presentedItemURL?.path == tempPath)
        #expect(watcher.presentedItemOperationQueue.maxConcurrentOperationCount == 1)

        let newURL = URL(fileURLWithPath: "/tmp/test_watcher_moved.pdf")
        watcher.presentedItemDidMove(to: newURL)
        #expect(watcher.presentedItemURL?.path == newURL.path)

        watcher.cancel()
    }

    @Test("SnapshotTarget thumbnail cache helper and recreation readiness")
    func testSnapshotTargetThumbnailCacheHelper() {
        let id = UUID()
        let fakeData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG magic bytes
        SnapshotTarget.writeThumbnailFile(id: id, data: fakeData)

        let fileName = "\(id.uuidString).png"
        #expect(SnapshotTarget.hasCachedThumbnail(fileName: fileName) == true)
        #expect(SnapshotTarget.hasCachedThumbnail(fileName: "nonexistent_\(UUID().uuidString).png") == false)

        let target = SnapshotTarget(id: id, label: "Test", targetPage: 0, thumbnailData: fakeData)
        target.deleteThumbnailFile()
        #expect(SnapshotTarget.hasCachedThumbnail(fileName: fileName) == false)
    }
}
