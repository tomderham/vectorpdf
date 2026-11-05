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

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import ObjectiveC

extension PDFViewerViewModel {
    /// Arms fileChangeWatcher for `path`, calling back into handleExternalFileChange on a real
    /// external change, or handleExternalFileMove on a Finder / iCloud rename or move.
    func armFileChangeWatcher(path: String) {
        fileChangeWatcher = FileChangeWatcher(path: path, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleExternalFileChange(path: path)
            }
        }, onMove: { [weak self] newURL in
            Task { @MainActor [weak self] in
                self?.handleExternalFileMove(to: newURL)
            }
        })
    }

    public func handleExternalFileMove(to newURL: URL) {
        guard let doc = document else { return }
        let oldPath = doc.filePath
        let newPath = newURL.path
        guard oldPath != newPath else { return }

        doc.updateFilePath(newPath)
        let fileName = newURL.lastPathComponent
        self.documentTitle = fileName
        if let window = currentWindow ?? NSApplication.shared.keyWindow {
            window.title = fileName
            window.representedURL = newURL
        }
        updateReadingUserActivity()
    }

    func waitForCloudDownload(url: URL, timeoutSeconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled || isCloudDownloadCancelled { return false }
            let (isEvicted, isDownloading) = CloudStorageHelper.checkDownloadStatus(for: url)
            if !isEvicted && !isDownloading && FileManager.default.fileExists(atPath: url.path) {
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return false
    }

    public func cancelCloudDownload() {
        isCloudDownloadCancelled = true
        isDownloadingFromCloud = false
        cloudDownloadStatusMessage = nil
    }

    public func updateReadingUserActivity() {
        guard let doc = document else {
            readingUserActivity?.invalidate()
            readingUserActivity = nil
            return
        }
        let path = doc.filePath
        let canonical = CloudStorageHelper.canonicalKey(for: path)

        if readingUserActivity == nil {
            let activity = NSUserActivity(activityType: "com.thomasderham.vectorpdf.document-reading")
            activity.title = documentTitle
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.isEligibleForPublicIndexing = false
            readingUserActivity = activity
        }

        guard let activity = readingUserActivity else { return }
        activity.title = documentTitle
        activity.userInfo = [
            "filePath": path,
            "canonicalKey": canonical,
            "pageIndex": currentPageIndex,
            "zoomScale": Double(zoomScale),
            "documentTitle": documentTitle
        ]
        activity.needsSave = true
        activity.becomeCurrent()
    }

    public func saveDocument() {
        guard let doc = document, !isReadOnlyDocument else { return }
        flushPendingFormEdits()
        // Suspend for our own write (an atomic replace, indistinguishable from an external change)
        // to avoid a pointless self-triggered reload; re-arm right after.
        fileChangeWatcher = nil
        defer { armFileChangeWatcher(path: doc.filePath) }
        let actorsOnWorkingCopy = workingCopyPath != nil
        do {
            try doc.save(to: doc.filePath)
            self.isDocumentEdited = false
            self.currentWindow?.isDocumentEdited = false
            cleanupWorkingCopy()
            // The file on disk changed, so a cached index for it is stale; and if the in-memory
            // index came from the working copy, it's now indexing a deleted file.
            invalidateAgentIndex(deleteCache: true)
            if actorsOnWorkingCopy {
                // The render/search actors had the working copy open; it no longer exists.
                let savedPath = doc.filePath
                Task { @MainActor [weak self] in
                    await self?.reopenActors(at: savedPath)
                }
            }
        } catch {
            print("Failed to save document: \(error)")
            // showErrorAlert is a no-op under the test runner — a bare runModal() here hangs a
            // headless test run forever.
            showErrorAlert(title: "Failed to Save Document", message: error.localizedDescription)
        }
    }
    
    public func saveDocumentAs() {
        guard let doc = document, !isReadOnlyDocument else { return }
        flushPendingFormEdits()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (doc.filePath as NSString).lastPathComponent
        panel.prompt = "Save As"
        
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self = self, let doc = self.document else { return }
                do {
                    try doc.save(to: url.path)
                    self.isDocumentEdited = false
                    self.currentWindow?.isDocumentEdited = false
                    self.cleanupWorkingCopy()
                    await self.loadDocument(from: url.path)
                } catch {
                    print("Failed to save document as: \(error)")
                    self.showErrorAlert(title: "Failed to Save Document", message: error.localizedDescription)
                }
            }
        }
        
        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            if window.attachedSheet == nil {
                panel.beginSheetModal(for: window, completionHandler: completion)
                return
            }
        }
        panel.begin(completionHandler: completion)
    }

    /// Throws away the unsaved changes and opens the file as last saved, on the same page, after
    /// asking. The changes can't be undone afterwards.
    public func revertToSaved() async {
        guard let doc = document, isDocumentEdited else { return }
        if !Self.isRunningTests {
            let alert = NSAlert()
            alert.messageText = "Revert “\(documentTitle)” to the last saved version?"
            alert.informativeText = "Your unsaved changes will be lost. This can’t be undone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Revert")
            alert.addButton(withTitle: "Cancel")
            let response: NSApplication.ModalResponse
            if let window = currentWindow ?? NSApplication.shared.keyWindow, window.attachedSheet == nil {
                response = await withCheckedContinuation { continuation in
                    alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
                }
            } else {
                response = alert.runModal()
            }
            guard response == .alertFirstButtonReturn else { return }
        }
        // A field being typed in would otherwise commit its text into the reloaded document.
        currentWindow?.makeFirstResponder(nil)
        // loadDocument saves the reading position first and restores it, so the page stays put.
        // The same path means it doesn't ask to save, and it drops the working copy and undo.
        await loadDocument(from: doc.filePath, password: currentDocumentPassword)
    }

    /// Prompts for where to save a smaller copy of the PDF, with the options in
    /// PDFDocumentCore.OptimizeOptions. Unsaved edits are included; the open document is unchanged.
    public func saveDocumentOptimizedAs() {
        guard let doc = document, !isReadOnlyDocument else { return }
        flushPendingFormEdits()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canCreateDirectories = true
        let baseName = ((doc.filePath as NSString).lastPathComponent as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName) (Optimized).pdf"
        panel.prompt = "Save"
        panel.title = "Save as Optimized PDF"
        panel.message = "Unused data is removed and everything is compressed."

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 96))
        let fontsCheckbox = NSButton(checkboxWithTitle: "Keep only the characters each font uses", target: nil, action: nil)
        fontsCheckbox.frame = NSRect(x: 10, y: 70, width: 380, height: 18)
        fontsCheckbox.state = .on
        let imagesLabel = NSTextField(labelWithString: "Images:")
        imagesLabel.frame = NSRect(x: 10, y: 43, width: 60, height: 18)
        let imagesPopup = NSPopUpButton(frame: NSRect(x: 70, y: 38, width: 240, height: 26), pullsDown: false)
        imagesPopup.addItems(withTitles: ["Keep as they are", "Reduce to 300 dpi (print)", "Reduce to 150 dpi (screen)"])
        let outlineCheckbox = NSButton(checkboxWithTitle: "Convert text to outlines (text can’t be selected or searched)", target: nil, action: nil)
        outlineCheckbox.frame = NSRect(x: 10, y: 10, width: 390, height: 18)
        outlineCheckbox.state = .off
        for view in [fontsCheckbox, imagesLabel, imagesPopup, outlineCheckbox] { accessory.addSubview(view) }
        panel.accessoryView = accessory

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let options = PDFDocumentCore.OptimizeOptions(
                subsetFonts: fontsCheckbox.state == .on,
                imageDPI: [nil, 300, 150][max(0, imagesPopup.indexOfSelectedItem)],
                outlineText: outlineCheckbox.state == .on
            )
            Task { @MainActor in
                guard let self else { return }
                let overwritesOpenFile = url.path == doc.filePath
                if overwritesOpenFile { self.fileChangeWatcher = nil }
                // Rewriting every image and font takes a while on a large document.
                let failure: String? = await Task.detached(priority: .userInitiated) {
                    do {
                        try doc.saveOptimized(to: url.path, options: options)
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }.value
                if let failure {
                    if overwritesOpenFile { self.armFileChangeWatcher(path: doc.filePath) }
                    self.showErrorAlert(title: "Failed to Save Optimized PDF", message: failure)
                    return
                }
                PDFViewerAppCoordinator.shared.noteRecentDocument(url)
                if overwritesOpenFile, self.document === doc {
                    // The file now holds the edits too, so nothing is left unsaved.
                    self.isDocumentEdited = false
                    self.currentWindow?.isDocumentEdited = false
                    await self.loadDocument(from: url.path, password: self.currentDocumentPassword)
                }
            }
        }

        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    /// Prompts the user with a save panel to save the open PDF as a flattened document (baking annotations and form widgets into static content).
    public func saveDocumentFlattenedAs() {
        guard let doc = document, !isReadOnlyDocument else { return }
        flushPendingFormEdits()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canCreateDirectories = true
        let originalName = (doc.filePath as NSString).lastPathComponent
        let baseName = (originalName as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName) (Flattened).pdf"
        panel.prompt = "Save Flattened"
        panel.title = "Save as Flattened PDF"

        // Accessory view providing fine-grained flattening options
        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 52))
        let annotCheckbox = NSButton(checkboxWithTitle: "Flatten annotations and markups", target: nil, action: nil)
        annotCheckbox.frame = NSRect(x: 10, y: 28, width: 320, height: 18)
        annotCheckbox.state = .on

        let widgetCheckbox = NSButton(checkboxWithTitle: "Flatten form fields (make static)", target: nil, action: nil)
        widgetCheckbox.frame = NSRect(x: 10, y: 6, width: 320, height: 18)
        widgetCheckbox.state = .on

        accessoryView.addSubview(annotCheckbox)
        accessoryView.addSubview(widgetCheckbox)
        panel.accessoryView = accessoryView

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let bakeAnnots = annotCheckbox.state == .on
            let bakeWidgets = widgetCheckbox.state == .on
            Task { @MainActor in
                guard let self = self, let doc = self.document else { return }
                do {
                    try doc.saveFlattened(to: url.path, bakeAnnotations: bakeAnnots, bakeWidgets: bakeWidgets)
                    PDFViewerAppCoordinator.shared.noteRecentDocument(url)
                    if url.path == doc.filePath {
                        // User chose to overwrite the active document with the flattened version
                        self.isDocumentEdited = false
                        self.currentWindow?.isDocumentEdited = false
                        self.cleanupWorkingCopy()
                        await self.loadDocument(from: url.path)
                    }
                } catch {
                    print("Failed to save flattened document: \(error)")
                    self.showErrorAlert(title: "Failed to Save Flattened Document", message: error.localizedDescription)
                }
            }
        }

        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            if window.attachedSheet == nil {
                panel.beginSheetModal(for: window, completionHandler: completion)
                return
            }
        }
        panel.begin(completionHandler: completion)
    }

    /// Prompts the user for a destination and password, then saves the current PDF encrypted with AES-256.
    public func saveDocumentEncryptedAs() {
        guard let doc = document, !isReadOnlyDocument else { return }
        flushPendingFormEdits()
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canCreateDirectories = true
        let originalName = (doc.filePath as NSString).lastPathComponent
        let baseName = (originalName as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName) (Encrypted).pdf"
        panel.prompt = "Save Encrypted"
        
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let targetURL = panel.url else { return }
            Task { @MainActor in
                guard let self = self, let doc = self.document, !Self.isRunningTests else { return }
                
                let alert = NSAlert()
                alert.messageText = "Set Document Password"
                alert.informativeText = "Enter a password to encrypt “\(targetURL.lastPathComponent)”. A password will be required to open this document."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Encrypt & Save")
                alert.addButton(withTitle: "Cancel")
                
                let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 75))
                let passwordLabel = NSTextField(labelWithString: "Password:")
                passwordLabel.frame = NSRect(x: 0, y: 48, width: 80, height: 18)
                let passwordField = NSSecureTextField(frame: NSRect(x: 85, y: 46, width: 215, height: 22))
                
                let verifyLabel = NSTextField(labelWithString: "Verify:")
                verifyLabel.frame = NSRect(x: 0, y: 16, width: 80, height: 18)
                let verifyField = NSSecureTextField(frame: NSRect(x: 85, y: 14, width: 215, height: 22))
                
                container.addSubview(passwordLabel)
                container.addSubview(passwordField)
                container.addSubview(verifyLabel)
                container.addSubview(verifyField)
                alert.accessoryView = container
                
                let modalResponse: NSApplication.ModalResponse
                if let window = self.currentWindow ?? NSApplication.shared.keyWindow, window.attachedSheet == nil {
                    modalResponse = await withCheckedContinuation { continuation in
                        alert.beginSheetModal(for: window) { resp in
                            continuation.resume(returning: resp)
                        }
                    }
                } else {
                    modalResponse = alert.runModal()
                }
                
                guard modalResponse == .alertFirstButtonReturn else { return }
                let password = passwordField.stringValue
                let verify = verifyField.stringValue
                
                guard !password.isEmpty else {
                    self.showErrorAlert(title: "Password Cannot Be Empty", message: "Please provide a non-empty password to encrypt the document.")
                    return
                }
                
                guard password == verify else {
                    self.showErrorAlert(title: "Passwords Do Not Match", message: "The entered passwords do not match. Please try again.")
                    return
                }
                
                do {
                    try doc.saveEncrypted(to: targetURL.path, password: password)
                    PDFViewerAppCoordinator.shared.noteRecentDocument(targetURL)
                } catch {
                    print("Failed to save encrypted document: \(error)")
                    self.showErrorAlert(title: "Failed to Encrypt Document", message: error.localizedDescription)
                }
            }
        }
        
        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            if window.attachedSheet == nil {
                panel.beginSheetModal(for: window, completionHandler: completion)
                return
            }
        }
        panel.begin(completionHandler: completion)
    }

    /// Displays the native macOS sharing pane (AirDrop, Mail, Messages, etc.) for the current document.
    public func shareDocument(from positioningView: NSView? = nil) {
        guard let doc = document, !doc.filePath.isEmpty else { return }
        let fileURL = URL(fileURLWithPath: doc.filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        
        let picker = NSSharingServicePicker(items: [fileURL])
        if let targetView = positioningView ?? currentWindow?.contentView {
            let rect = NSRect(x: targetView.bounds.midX, y: targetView.bounds.maxY - 10, width: 1, height: 1)
            picker.show(relativeTo: rect, of: targetView, preferredEdge: .minY)
        }
    }

    /// Reveals the current PDF document file in Finder.
    public func showInFinder() {
        guard let doc = document, !doc.filePath.isEmpty else { return }
        let fileURL = URL(fileURLWithPath: doc.filePath)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// True under `swift test` / XCTest, where a modal alert would hang the headless run forever.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains { $0.contains("swiftpm-testing-helper") || $0.contains("xctest") }
    }

    func showErrorAlert(title: String, message: String) {
        if Self.isRunningTests {
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        if let window = currentWindow ?? NSApplication.shared.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    /// Prompts the user to Save, Don't Save, or Cancel when closing a document with unsaved edits.
    /// Returns true if closing should proceed (changes saved or discarded), or false if closing should abort.
    @MainActor
    public func promptSaveBeforeClosingIfNeeded() -> Bool {
        // Commit any pending active text field input before checking or saving
        currentWindow?.makeFirstResponder(nil)
        
        guard isDocumentEdited, let _ = document else { return true }
        // No one can answer a modal under the test runner; behave as "Don't Save".
        guard !Self.isRunningTests else { return true }
        
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to the document “\(documentTitle)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")          // .alertFirstButtonReturn (1000)
        alert.addButton(withTitle: "Cancel")        // .alertSecondButtonReturn (1001)
        alert.addButton(withTitle: "Don’t Save")     // .alertThirdButtonReturn (1002)
        
        if alert.buttons.count >= 3 {
            alert.buttons[0].keyEquivalent = "\r"
            alert.buttons[1].keyEquivalent = "\u{1b}" // Escape
            alert.buttons[2].keyEquivalent = "d"
            alert.buttons[2].keyEquivalentModifierMask = [.command]
        }
        
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // Save
            saveDocument()
            return !isDocumentEdited
        case .alertThirdButtonReturn: // Don't Save
            isDocumentEdited = false
            currentWindow?.isDocumentEdited = false
            cleanupWorkingCopy()
            return true
        default: // Cancel (.alertSecondButtonReturn)
            return false
        }
    }

    /// Persists this document's current page, zoom, and snapshots so they can be restored next
    /// time it's opened. Called on every document switch (see loadDocument), snapshot change, and
    /// externally on window close / app quit (see PDFViewerAppCoordinator.flushAllReadingStates).
    /// No-op for transient (snapshot/reference) windows or when no document is open.
    public func saveReadingStateIfNeeded() {
        guard !isTransientWindow, let doc = document else { return }
        ReadingStateManager.shared.updateState(
            for: doc.filePath,
            lastPageIndex: currentPageIndex,
            zoomScale: zoomScale,
            snapshots: activeSnapshots
        )
    }

    // MARK: - Document Properties & Font Inspection

    public func showDocumentProperties() {
        guard let doc = document else { return }
        self.documentInspectionReport = doc.generateInspectionReport(pageIndex: currentPageIndex)
        self.isShowingDocumentProperties = true
    }

    public func refreshInspectionReport() {
        guard let doc = document else { return }
        self.documentInspectionReport = doc.generateInspectionReport(pageIndex: currentPageIndex)
    }

    public func showSplitPDF() {
        guard document != nil, !isReadOnlyDocument else { return }
        self.isShowingSplitPDF = true
    }
}
