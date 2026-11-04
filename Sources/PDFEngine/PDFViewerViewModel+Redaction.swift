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
    // MARK: - Redaction & Security Scrubbing

    /// Runs `apply`, first explaining what redaction does and doesn't remove if this is the
    /// document's first redaction. The alert is shown once per open document.
    private func confirmFirstRedaction(of doc: PDFDocumentCore, then apply: @escaping @MainActor () -> Void) {
        guard redactionNoticeDocument !== doc, !Self.isRunningTests else {
            apply()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Redaction Reaches Beyond the Page"
        alert.informativeText = """
            Removed from the whole document: metadata, attachments, page thumbnails, alternative text and XFA form data.

            Bookmarks stay, with each redacted word replaced by \(PDFDocumentCore.redactedTitlePlaceholder). Text in images and scans can't be matched, so check the bookmarks yourself after redacting those.

            Not removed, and could still contain the text: named destinations, page labels, layer names and JavaScript.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Redact")   // .alertFirstButtonReturn
        alert.addButton(withTitle: "Cancel")   // .alertSecondButtonReturn

        let handle: @MainActor @Sendable (NSApplication.ModalResponse) -> Void = { [weak self] response in
            // The document may have been closed or replaced while the alert was up.
            guard let self, self.document === doc, response == .alertFirstButtonReturn else { return }
            self.redactionNoticeDocument = doc
            apply()
        }
        if let window = currentWindow ?? NSApplication.shared.keyWindow {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { handle(response) }
            }
        } else {
            handle(alert.runModal())
        }
    }

    /// Directly and immediately applies a redaction box over a user-drawn region.
    public func applyRedactionRegion(pageIndex: Int, rect: CGRect) {
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return }
        confirmFirstRedaction(of: doc) { [weak self] in
            self?.redactRegion(pageIndex: pageIndex, rect: rect, in: doc)
        }
    }

    private func redactRegion(pageIndex: Int, rect: CGRect, in doc: PDFDocumentCore) {
        let mode: Int32 = (redactionColor == .black) ? 1 : 2
        do {
            try doc.applyRedactions(pageIndex: pageIndex, rects: [rect], mode: mode)
            finalizeRedactionChanges(affectedPages: [pageIndex])
        } catch {
            print("Failed to apply redaction region on page \(pageIndex): \(error)")
        }
    }

    /// Directly and immediately applies the chosen RedactAction (.redact, .delete) to all selected search matches.
    public func applySelectedMatches() {
        guard redactionMatches.contains(where: \.isSelected), let doc = document else { return }
        confirmFirstRedaction(of: doc) { [weak self] in
            self?.redactSelectedMatches(in: doc)
        }
    }

    private func redactSelectedMatches(in doc: PDFDocumentCore) {
        let selected = redactionMatches.filter { $0.isSelected }
        var affectedPages = Set<Int>()
        let isBlack = (redactionColor == .black)
        let byPage = Dictionary(grouping: selected, by: { $0.result.pageIndex })

        for (pIdx, items) in byPage {
            let rects = items.flatMap { item in
                item.result.highlightQuads.isEmpty
                    ? [item.result.rect.insetBy(dx: -1.0, dy: -1.0)]
                    : item.result.highlightQuads.map { $0.boundingRect.insetBy(dx: -1.0, dy: -1.0) }
            }
            let matchedText = items.map(\.result.matchedText)

            switch replaceAction {
            case .redact:
                let mode: Int32 = isBlack ? 1 : 2
                do {
                    try doc.applyRedactions(pageIndex: pIdx, rects: rects, mode: mode, redactedText: matchedText)
                    affectedPages.insert(pIdx)
                } catch {
                    print("Failed to apply redactions on page \(pIdx): \(error)")
                }

            case .remove:
                do {
                    try doc.applyRedactions(pageIndex: pIdx, rects: rects, mode: 0, redactedText: matchedText)
                    affectedPages.insert(pIdx)
                } catch {
                    print("Failed to remove text on page \(pIdx): \(error)")
                }
            }
        }

        let appliedIDs = Set(selected.map { $0.id })
        redactionMatches.removeAll(where: { appliedIDs.contains($0.id) })

        finalizeRedactionChanges(affectedPages: affectedPages)
    }

    /// Saves document modifications to the working copy, updates background actors, and re-renders affected pages.
    public func finalizeRedactionChanges(affectedPages: Set<Int>) {
        guard !affectedPages.isEmpty, let doc = document else { return }

        if workingCopyPath == nil {
            workingCopyPath = Self.newWorkingCopyPath()
        }
        guard let workingPath = workingCopyPath else { return }

        do {
            try doc.save(to: workingPath)
        } catch {
            print("Failed to save modified working copy: \(error)")
        }

        self.isDocumentEdited = true
        self.currentWindow?.isDocumentEdited = true
        // Redacted text must not survive in the Agent's index — in memory or in its disk cache.
        invalidateAgentIndex(deleteCache: true)
        // So must text OCR read from them, and any selection of it.
        let staleOCR = discardOCR(onPages: affectedPages)
        if let sel = activeSelection, affectedPages.contains(sel.pageIndex) || additionalSelectionPages.contains(where: { affectedPages.contains($0.pageIndex) }) {
            clearSelection()
        }

        Task { @MainActor in
            await self.reopenActors(at: workingPath)
            self.thumbnailVersion = UUID()
            for pIdx in affectedPages {
                self.renderedPages.removeValue(forKey: pIdx)
                self.thumbnailImages.removeValue(forKey: pIdx)
                self.pageStructuredData.removeValue(forKey: pIdx)
                self.requestThumbnail(for: pIdx)
                await self.renderPage(pIdx)
            }
            self.objectWillChange.send()
            await self.recognizeAgain(staleOCR)
        }
    }

    public func toggleRedactionBar() {
        isRedactionBarVisible.toggle()
        if isRedactionBarVisible {
            if editRedactTab == .redactRegion {
                canvasMode = .redact
            }
        } else {
            if canvasMode == .redact {
                canvasMode = .select
            }
        }
    }

    public func performRedactionSearch() {
        redactionSearchTask?.cancel()
        
        let query: String
        let isRegex: Bool
        if let presetRegex = redactionPreset.regexPattern {
            query = presetRegex
            isRegex = true
        } else if redactionPreset == .customRegex {
            query = redactionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            isRegex = true
        } else {
            query = redactionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            isRegex = false
        }

        guard !query.isEmpty else {
            redactionMatches = []
            isRedactionSearching = false
            return
        }

        // Match Case / Whole Word are only offered for custom searches (Whole Word only for
        // plain text); a value left over from one must not silently narrow a preset's search.
        let options = SearchOptions(
            matchCase: (redactionPreset == .customText || redactionPreset == .customRegex) && redactionMatchCase,
            wholeWord: redactionPreset == .customText && redactionWholeWord,
            smartSearch: !isRegex,
            isRegex: isRegex
        )

        isRedactionSearching = true
        redactionMatches = []

        let nearPage = currentPageIndex
        let ocr = self.ocrResults

        redactionSearchTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let stream = await self.searchActor.searchStream(
                query: query,
                nearPage: nearPage,
                options: options,
                ocrPages: ocr
            )

            var items: [RedactionMatchItem] = []
            var lastUpdate = Date()

            for await result in stream {
                guard !Task.isCancelled else { break }
                // Pages arrive out of order; each page's matches come together, in reading order.
                let item = RedactionMatchItem(result: result, isSelected: true)
                items.insert(item, at: items.lastIndex { $0.result.pageIndex <= result.pageIndex }.map { $0 + 1 } ?? 0)
                if items.count < 5 || Date().timeIntervalSince(lastUpdate) > 0.08 {
                    self.redactionMatches = items
                    lastUpdate = Date()
                }
            }

            if !Task.isCancelled {
                self.redactionMatches = items
                self.isRedactionSearching = false
            }
        }
    }

    public func cancelRedactionSearch() {
        redactionSearchTask?.cancel()
        isRedactionSearching = false
    }

    public func selectAllRedactionMatches(_ selected: Bool) {
        for idx in redactionMatches.indices {
            redactionMatches[idx].isSelected = selected
        }
    }

    public func toggleRedactionMatchSelection(id: UUID) {
        if let idx = redactionMatches.firstIndex(where: { $0.id == id }) {
            redactionMatches[idx].isSelected.toggle()
        }
    }

    public func selectRedactionMatch(_ item: RedactionMatchItem) {
        activeRedactionMatchId = item.id
        let match = item.result
        let pageIdx = match.pageIndex
        activeScrollTargetId = item.id.uuidString
        searchJumpToken &+= 1
        currentPageIndex = pageIdx
        pruneCaches(around: pageIdx)
        Task {
            await renderPage(pageIdx)
        }
        objectWillChange.send()
    }
}
