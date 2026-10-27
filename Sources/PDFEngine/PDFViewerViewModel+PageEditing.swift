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
    // MARK: - Working-copy plumbing

    /// Reopens the render and search actors at `path` using the document's password. Edits queue
    /// this to run later, by when a save may have deleted that working copy or another document
    /// may be open — so only the file now backing the document is opened. Returns whether it was.
    @discardableResult
    func reopenActors(at path: String) async -> Bool {
        guard path == workingCopyPath ?? document?.filePath else { return false }
        searchTask?.cancel()
        let password = currentDocumentPassword
        do {
            try await renderActor.openDocument(filePath: path, password: password)
        } catch {
            print("Failed to reopen render actor on \(path): \(error)")
        }
        do {
            try await searchActor.openDocument(filePath: path, password: password)
        } catch {
            print("Failed to reopen search actor on \(path): \(error)")
        }
        // Refresh active search on updated content.
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isSearching = false
        } else {
            performSearch()
        }
        return true
    }

    /// Drops everything cached per page *index* after pages were inserted, deleted, reordered or
    /// duplicated — those caches now describe different pages. Form widgets, OCR results and
    /// scale calibrations are re-derived on demand from the (already updated) document.
    private func invalidateStructuralState() {
        ocrGeneration += 1
        invalidateAgentIndex(deleteCache: false)
        pageFormWidgets.removeAll()
        ocrResults.removeAll()
        detectedScannedPages.removeAll()
        pageScaleConfigs.removeAll()
        // Back/Forward entries are page indices too, and now name different pages.
        navigationHistory.removeAll()
        navigationHistoryIndex = -1
        updateNavigationHistoryState()
        startScannedPageDetection()
    }

    // MARK: - Anchor protection for page edits

    /// Anchors that a page edit touching pages `firstPage...lastPage` would leave pointing at the
    /// wrong page, or at one that no longer exists — an anchor stores a plain page index, and is
    /// not remapped when pages are inserted, deleted or moved.
    func anchorsAffected(byPageEditFrom firstPage: Int, through lastPage: Int = .max) -> [SnapshotTarget] {
        activeSnapshots.filter { $0.targetPage >= firstPage && $0.targetPage <= lastPage }
    }

    /// Runs `edit` — a change that shifts or removes the pages in `firstPage...lastPage` — after
    /// warning about any anchors it would break. The user can make the change in a copy saved
    /// under a new name (which starts without anchors, leaving this document's intact), go ahead
    /// regardless, or cancel.
    private func performPageEdit(
        affectingPagesFrom firstPage: Int,
        through lastPage: Int = .max,
        _ edit: @escaping @MainActor @Sendable () -> Void
    ) {
        let affected = anchorsAffected(byPageEditFrom: firstPage, through: lastPage)
        guard !affected.isEmpty, !Self.isRunningTests, let doc = document else {
            edit()
            return
        }

        let alert = NSAlert()
        alert.messageText = affected.count == 1
            ? "This Change Affects an Anchor"
            : "This Change Affects \(affected.count) Anchors"
        alert.informativeText = "Anchors remember a page number, so adding, deleting or moving pages would leave "
            + (affected.count == 1 ? "it" : "them")
            + " pointing at the wrong place. You can make the change in a copy saved under a new name instead — the copy starts without anchors, and “\(documentTitle)” keeps its anchors as they are."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save as Copy…")   // .alertFirstButtonReturn
        alert.addButton(withTitle: "Cancel")          // .alertSecondButtonReturn
        alert.addButton(withTitle: "Edit Anyway")     // .alertThirdButtonReturn

        let handle: @MainActor @Sendable (NSApplication.ModalResponse) -> Void = { [weak self] response in
            // The document may have been closed or replaced while the alert was up.
            guard let self, self.document === doc else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.promptSaveCopyForPageEdit(edit)
            case .alertThirdButtonReturn:
                edit()
            default:
                break
            }
        }

        if let window = currentWindow ?? NSApplication.shared.keyWindow, window.attachedSheet == nil {
            alert.beginSheetModal(for: window) { response in
                // Hop off the sheet's dismissal so the save panel can attach to the same window.
                Task { @MainActor in handle(response) }
            }
        } else {
            handle(alert.runModal())
        }
    }

    private func promptSaveCopyForPageEdit(_ edit: @escaping @MainActor @Sendable () -> Void) {
        guard let doc = document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canCreateDirectories = true
        let baseName = ((doc.filePath as NSString).lastPathComponent as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName) copy.pdf"
        panel.directoryURL = URL(fileURLWithPath: doc.filePath).deletingLastPathComponent()
        panel.prompt = "Save Copy"
        panel.message = "The page change will be made in this copy."

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.continuePageEdit(onCopyAt: url, edit)
            }
        }

        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow,
           window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: completion)
            return
        }
        panel.begin(completionHandler: completion)
    }

    /// Saves the document as it stands to `url`, switches this window to that copy, and applies
    /// `edit` there. Returns whether the edit was applied.
    @discardableResult
    func continuePageEdit(onCopyAt url: URL, _ edit: @MainActor @Sendable () -> Void) async -> Bool {
        guard let doc = document else { return false }
        let original = URL(fileURLWithPath: doc.filePath).standardizedFileURL.resolvingSymlinksInPath()
        guard url.standardizedFileURL.resolvingSymlinksInPath() != original else {
            showErrorAlert(
                title: "Choose a Different Name",
                message: "The copy has to be saved under a new name — saving over “\(documentTitle)” would keep its anchors."
            )
            return false
        }
        flushPendingFormEdits()
        do {
            try doc.save(to: url.path)
        } catch {
            print("Failed to save copy for page edit: \(error)")
            showErrorAlert(title: "Failed to Save Copy", message: error.localizedDescription)
            return false
        }
        // The copy starts without anchors (also clearing any left by a file it just replaced),
        // but opens at the same page and zoom.
        ReadingStateManager.shared.updateState(
            for: url.path,
            lastPageIndex: currentPageIndex,
            zoomScale: zoomScale,
            snapshots: []
        )
        // The unsaved edits went into the copy; the original on disk is left as it was.
        isDocumentEdited = false
        currentWindow?.isDocumentEdited = false
        cleanupWorkingCopy()
        await loadDocument(from: url.path, password: currentDocumentPassword)
        guard let copy = document, copy !== doc else { return false }
        edit()
        return true
    }

    /// Finds scanned (text-less) pages among the first 50 off the main thread, then OCRs them.
    func startScannedPageDetection() {
        guard let doc = document else { return }
        let generation = ocrGeneration
        Task { [weak self] in
            let limit = min(doc.pageCount, 50)
            let scanned = await Task.detached(priority: .utility) {
                (0..<limit).filter { doc.isScannedPage(pageIndex: $0) }
            }.value
            guard let self, self.document === doc, self.ocrGeneration == generation, !scanned.isEmpty else { return }
            self.detectedScannedPages.formUnion(scanned)
            // Only the pages just found — OCRing the rest of a long scanned document is left to
            // "Run OCR" (or a search), rather than starting it for every page on open.
            for pageIndex in scanned {
                guard self.document === doc, self.ocrGeneration == generation else { return }
                await self.runOCR(onPageIndex: pageIndex)
            }
        }
    }

    // MARK: - Page Manipulation
    public func rotatePage(_ pageIndex: Int, by degrees: Int = 90) {
        guard let doc = document else { return }
        do {
            try doc.rotatePage(pageIndex, by: degrees)
            if workingCopyPath == nil {
                workingCopyPath = Self.newWorkingCopyPath()
            }
            guard let workingPath = workingCopyPath else {
                return
            }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                self.renderedPages.removeValue(forKey: pageIndex)
                self.thumbnailImages.removeValue(forKey: pageIndex)
                self.pageAnnotations.removeValue(forKey: pageIndex)
                self.pageStructuredData.removeValue(forKey: pageIndex)
                self.pageLinks.removeValue(forKey: pageIndex)
                self.pageFormWidgets.removeValue(forKey: pageIndex)
                self.objectWillChange.send()
                self.requestThumbnail(for: pageIndex)
                await self.renderPage(pageIndex)
            }
        } catch {
            print("Failed to rotate page \(pageIndex): \(error)")
        }
    }

    public func deletePage(_ pageIndex: Int) {
        guard let doc = document, doc.pageCount > 1 else { return }
        performPageEdit(affectingPagesFrom: pageIndex) { [weak self] in
            self?.applyDeletePage(pageIndex)
        }
    }

    private func applyDeletePage(_ pageIndex: Int) {
        guard let doc = document, doc.pageCount > 1 else { return }
        do {
            try doc.deletePage(pageIndex)
            if workingCopyPath == nil {
                workingCopyPath = Self.newWorkingCopyPath()
            }
            guard let workingPath = workingCopyPath else {
                return
            }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()
                if self.currentPageIndex >= doc.pageCount {
                    self.currentPageIndex = max(0, doc.pageCount - 1)
                }
                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, self.currentPageIndex - 8)
                let end = min(doc.pageCount, self.currentPageIndex + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to delete page \(pageIndex): \(error)")
        }
    }

    public func reorderPage(from fromIndex: Int, to toIndex: Int) {
        self.endThumbnailDrag()
        guard let doc = document else { return }
        guard fromIndex != toIndex, fromIndex >= 0, fromIndex < doc.pageCount, toIndex >= 0, toIndex < doc.pageCount else { return }
        performPageEdit(affectingPagesFrom: min(fromIndex, toIndex), through: max(fromIndex, toIndex)) { [weak self] in
            self?.applyReorderPage(from: fromIndex, to: toIndex)
        }
    }

    private func applyReorderPage(from fromIndex: Int, to toIndex: Int) {
        guard let doc = document else { return }
        guard fromIndex != toIndex, fromIndex >= 0, fromIndex < doc.pageCount, toIndex >= 0, toIndex < doc.pageCount else { return }
        do {
            try doc.reorderPage(from: fromIndex, to: toIndex)
            if workingCopyPath == nil {
                workingCopyPath = Self.newWorkingCopyPath()
            }
            guard let workingPath = workingCopyPath else {
                return
            }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.endThumbnailDrag()
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()
                self.currentPageIndex = toIndex
                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, toIndex - 8)
                let end = min(doc.pageCount, toIndex + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to reorder page from \(fromIndex) to \(toIndex): \(error)")
        }
    }

    public func reorderPages(from fromIndices: [Int], toSlot destSlot: Int) {
        self.endThumbnailDrag()
        guard let doc = document else { return }
        guard !fromIndices.isEmpty,
              ThumbnailDropLogic.isValidSlot(slot: destSlot, fromIndices: Set(fromIndices), pageCount: doc.pageCount) else {
            return
        }
        let sortedFrom = fromIndices.sorted()
        performPageEdit(
            affectingPagesFrom: min(sortedFrom[0], destSlot),
            through: max(sortedFrom[sortedFrom.count - 1], destSlot - 1)
        ) { [weak self] in
            self?.applyReorderPages(from: sortedFrom, toSlot: destSlot)
        }
    }

    private func applyReorderPages(from sortedFrom: [Int], toSlot destSlot: Int) {
        guard let doc = document else { return }
        guard !sortedFrom.isEmpty,
              ThumbnailDropLogic.isValidSlot(slot: destSlot, fromIndices: Set(sortedFrom), pageCount: doc.pageCount) else {
            return
        }
        let beforeCount = sortedFrom.filter { $0 < destSlot }.count
        let targetStartingIndex = destSlot - beforeCount

        do {
            try doc.reorderPages(from: sortedFrom, toSlot: destSlot)
            if workingCopyPath == nil {
                workingCopyPath = Self.newWorkingCopyPath()
            }
            guard let workingPath = workingCopyPath else { return }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.endThumbnailDrag()
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()

                let newSelectedRange = Set(targetStartingIndex..<(targetStartingIndex + sortedFrom.count))
                self.selectedThumbnailPageIndices = newSelectedRange
                self.selectionAnchorPageIndex = targetStartingIndex
                self.currentPageIndex = targetStartingIndex

                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, targetStartingIndex - 8)
                let end = min(doc.pageCount, targetStartingIndex + sortedFrom.count + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to reorder pages from \(sortedFrom) to slot \(destSlot): \(error)")
        }
    }

    public func deleteSelectedThumbnails() {
        guard let doc = document else { return }
        let toDelete = selectedThumbnailPageIndices.sorted()
        guard !toDelete.isEmpty, toDelete.count < doc.pageCount else { return }
        performPageEdit(affectingPagesFrom: toDelete[0]) { [weak self] in
            self?.applyDeletePages(toDelete)
        }
    }

    private func applyDeletePages(_ toDelete: [Int]) {
        guard let doc = document else { return }
        guard !toDelete.isEmpty, toDelete.count < doc.pageCount else { return }
        do {
            try doc.deletePages(toDelete)
            if workingCopyPath == nil {
                workingCopyPath = Self.newWorkingCopyPath()
            }
            guard let workingPath = workingCopyPath else { return }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()

                let targetPage = min(toDelete[0], doc.pageCount - 1)
                self.currentPageIndex = targetPage
                self.selectedThumbnailPageIndices = [targetPage]
                self.selectionAnchorPageIndex = targetPage

                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, targetPage - 8)
                let end = min(doc.pageCount, targetPage + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to delete pages \(toDelete): \(error)")
        }
    }

    public func rotateSelectedThumbnails(by degrees: Int = 90) {
        guard let doc = document else { return }
        let toRotate = selectedThumbnailPageIndices.sorted()
        guard !toRotate.isEmpty else { return }
        do {
            try doc.rotatePages(toRotate, by: degrees)
            if workingCopyPath == nil {
                workingCopyPath = Self.newWorkingCopyPath()
            }
            guard let workingPath = workingCopyPath else { return }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                for p in toRotate {
                    self.renderedPages.removeValue(forKey: p)
                    self.thumbnailImages.removeValue(forKey: p)
                    self.pageAnnotations.removeValue(forKey: p)
                    self.pageStructuredData.removeValue(forKey: p)
                    self.pageLinks.removeValue(forKey: p)
                    self.pageFormWidgets.removeValue(forKey: p)
                }
                self.objectWillChange.send()
                for p in toRotate {
                    self.requestThumbnail(for: p)
                }
                await self.renderPage(self.currentPageIndex)
            }
        } catch {
            print("Failed to rotate pages \(toRotate): \(error)")
        }
    }

    public func extractSelectedThumbnails() {
        let pages = selectedThumbnailPageIndices.sorted()
        guard !pages.isEmpty else { return }
        extractPages(pages)
    }

    public func extractPage(_ pageIndex: Int) {
        extractPages([pageIndex])
    }

    public func extractPages(_ pageIndices: [Int]) {
        guard let doc = document, !pageIndices.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        let baseName = ((doc.filePath as NSString).lastPathComponent as NSString).deletingPathExtension
        if pageIndices.count == 1 {
            panel.nameFieldStringValue = "\(baseName)_Page_\(pageIndices[0] + 1).pdf"
        } else {
            panel.nameFieldStringValue = "\(baseName)_Selected_Pages.pdf"
        }
        panel.prompt = "Save"

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try self?.document?.extractPages(pageIndices, to: url)
            } catch {
                print("Failed to extract pages: \(error)")
                Task { @MainActor [weak self] in
                    self?.showErrorAlert(title: "Failed to Extract Pages", message: error.localizedDescription)
                }
            }
        }

        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    public func duplicateSelectedThumbnails() {
        guard let doc = document else { return }
        let toDuplicate = selectedThumbnailPageIndices.sorted()
        guard doc.pageCount > 0, !toDuplicate.isEmpty else { return }
        // The copies are inserted right after the last selected page.
        performPageEdit(affectingPagesFrom: toDuplicate[toDuplicate.count - 1] + 1) { [weak self] in
            self?.applyDuplicatePages(toDuplicate)
        }
    }

    private func applyDuplicatePages(_ toDuplicate: [Int]) {
        guard let doc = document, !toDuplicate.isEmpty else { return }

        do {
            let (insertedSlot, count) = try doc.duplicatePages(toDuplicate)
            if workingCopyPath == nil {
                workingCopyPath = Self.newWorkingCopyPath()
            }
            guard let workingPath = workingCopyPath else { return }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()

                let newSelectedRange = Set(insertedSlot..<(insertedSlot + count))
                self.selectedThumbnailPageIndices = newSelectedRange
                self.selectionAnchorPageIndex = insertedSlot
                self.currentPageIndex = insertedSlot

                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, insertedSlot - 8)
                let end = min(doc.pageCount, insertedSlot + count + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to duplicate pages \(toDuplicate): \(error)")
        }
    }

    public func duplicatePage(_ pageIndex: Int) {
        selectedThumbnailPageIndices = [pageIndex]
        selectionAnchorPageIndex = pageIndex
        duplicateSelectedThumbnails()
    }

    public func insertBlankPage(after pageIndex: Int) {
        guard let doc = document else { return }
        let targetSlot = min(max(0, pageIndex + 1), doc.pageCount)
        insertBlankPage(atSlot: targetSlot)
    }

    public func insertBlankPageAtSelection() {
        guard let doc = document else { return }
        let maxSelected = selectedThumbnailPageIndices.max() ?? currentPageIndex
        let targetSlot = min(max(0, maxSelected + 1), doc.pageCount)
        insertBlankPage(atSlot: targetSlot)
    }

    public func insertBlankPage(atSlot slot: Int, width: CGFloat? = nil, height: CGFloat? = nil) {
        guard let doc = document else { return }
        let clampedSlot = max(0, min(slot, doc.pageCount))
        performPageEdit(affectingPagesFrom: clampedSlot) { [weak self] in
            self?.applyInsertBlankPage(atSlot: clampedSlot, width: width, height: height)
        }
    }

    private func applyInsertBlankPage(atSlot slot: Int, width: CGFloat?, height: CGFloat?) {
        guard let doc = document else { return }
        let clampedSlot = max(0, min(slot, doc.pageCount))

        do {
            let insertedSlot = try doc.insertBlankPage(atSlot: clampedSlot, width: width, height: height)
            if workingCopyPath == nil {
                workingCopyPath = Self.newWorkingCopyPath()
            }
            guard let workingPath = workingCopyPath else { return }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()

                let newSelectedRange: Set<Int> = [insertedSlot]
                self.selectedThumbnailPageIndices = newSelectedRange
                self.selectionAnchorPageIndex = insertedSlot
                self.currentPageIndex = insertedSlot

                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, insertedSlot - 8)
                let end = min(doc.pageCount, insertedSlot + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to insert blank page at slot \(clampedSlot): \(error)")
        }
    }

    public func importPages(from fileURL: URL, toSlot: Int? = nil) {
        guard let doc = document else { return }
        let slot = toSlot ?? (selectedThumbnailPageIndices.max().map { $0 + 1 } ?? doc.pageCount)
        let clampedSlot = max(0, min(slot, doc.pageCount))
        performPageEdit(affectingPagesFrom: clampedSlot) { [weak self] in
            self?.applyImportPages(from: fileURL, atSlot: clampedSlot)
        }
    }

    private func applyImportPages(from fileURL: URL, atSlot slot: Int) {
        guard let doc = document else { return }
        let clampedSlot = max(0, min(slot, doc.pageCount))

        do {
            let (insertedSlot, count) = try doc.importPages(from: fileURL, atSlot: clampedSlot)
            if workingCopyPath == nil {
                workingCopyPath = Self.newWorkingCopyPath()
            }
            guard let workingPath = workingCopyPath else { return }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()

                let newSelectedRange = Set(insertedSlot..<(insertedSlot + count))
                self.selectedThumbnailPageIndices = newSelectedRange
                self.selectionAnchorPageIndex = insertedSlot
                self.currentPageIndex = insertedSlot

                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, insertedSlot - 8)
                let end = min(doc.pageCount, insertedSlot + count + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to import pages from \(fileURL.path): \(error)")
        }
    }

    public func promptImportPDF(atSlot slot: Int? = nil) {
        guard document != nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Insert"
        panel.message = "Choose a PDF file to insert into this document"

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importPages(from: url, toSlot: slot)
        }

        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }
}
