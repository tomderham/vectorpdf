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
import SwiftUI

extension PDFViewerViewModel {
    private static let lastPageMarksKey = "com.thomasderham.vectorpdf.lastPageMarkSettings"

    public func showPageMarks() {
        guard document?.isPDF == true, !isReadOnlyDocument else { return }
        isShowingPageMarks = true
    }

    /// What the sheet starts with: the document's own marks, else the ones used last (without
    /// their text, which belongs to that document), else the defaults.
    public func initialPageMarkSettings() -> PageMarkSettings {
        if let own = document?.pageMarkSettings() { return own }
        guard let data = UserDefaults.standard.data(forKey: Self.lastPageMarksKey),
              var last = try? JSONDecoder().decode(PageMarkSettings.self, from: data) else { return PageMarkSettings() }
        last.pages = PageMarkSettings.PageChoice()
        return last
    }

    /// Whether the document has headers, footers or a watermark VectorPDF added.
    public var hasPageMarks: Bool {
        guard let kinds = document?.pageMarkKinds() else { return false }
        return kinds.headerFooter || kinds.watermark
    }

    /// Puts these headers, footers and watermark on the pages, in place of any VectorPDF added
    /// before; with empty settings, takes them off.
    public func applyPageMarks(_ settings: PageMarkSettings) {
        guard let doc = document, !isReadOnlyDocument else { return }
        flushPendingFormEdits()
        let changed: Set<Int>
        do {
            changed = try doc.applyPageMarks(settings)
        } catch {
            showErrorAlert(title: "Couldn't Change the Headers and Footers", message: error.localizedDescription)
            return
        }
        if !settings.isEmpty, let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.lastPageMarksKey)
        }
        guard !changed.isEmpty else { return }
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
        // The pages' text changed: selection, search and the Agent read it again.
        for page in changed { pageStructuredData.removeValue(forKey: page) }
        invalidateAgentIndex(deleteCache: false)
        thumbnailVersion = UUID()
        refreshRendererCopy(pages: changed)
    }

    /// Puts these marks on other PDFs, chosen next, saving marked copies in a folder chosen
    /// after them; Bates numbers run on from file to file. Shows progress, then what was done.
    public func applyPageMarksToOtherFiles(_ settings: PageMarkSettings) {
        guard !settings.isEmpty, let window = currentWindow ?? NSApp.keyWindow else { return }
        let files = NSOpenPanel()
        files.allowedContentTypes = [.pdf]
        files.allowsMultipleSelection = true
        files.message = "Choose the PDFs to mark. They're numbered in order of their names."
        files.prompt = "Choose"
        guard files.runModal() == .OK, !files.urls.isEmpty else { return }
        let folder = NSOpenPanel()
        folder.canChooseFiles = false
        folder.canChooseDirectories = true
        folder.canCreateDirectories = true
        folder.message = "Choose a folder for the marked copies. The files themselves aren't changed."
        folder.prompt = "Save Here"
        guard folder.runModal() == .OK, let destination = folder.url else { return }
        let urls = files.urls
        let progress = RecognitionProgress(total: urls.count)
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        panel.contentView = NSHostingView(rootView: RecognitionProgressView(progress: progress, title: "Marking files…"))
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 380, height: 100))
        window.beginSheet(panel, completionHandler: nil)
        Task {
            let cancelled = MarkingCancelFlag()
            let result = await Task.detached(priority: .userInitiated) {
                PageMarksBatch.mark(urls, with: settings, into: destination, progress: { done in
                    DispatchQueue.main.async {
                        progress.done = done
                        if progress.isCancelled { cancelled.cancel() }
                    }
                }, isCancelled: { cancelled.isCancelled })
            }.value
            window.endSheet(panel)
            let alert = NSAlert()
            alert.messageText = result.written.count == 1 ? "1 File Marked" : "\(result.written.count) Files Marked"
            var info = "The marked copies are in “\(destination.lastPathComponent)”."
            if let first = result.firstBates, let last = result.lastBates, settings.header.texts.contains(where: { $0.contains(PageMarkSettings.Token.bates.rawValue) }) {
                info += " Bates numbers \(first) to \(last)."
            }
            if !result.failed.isEmpty {
                info += "\n\nNot marked:\n" + result.failed.map { "\($0.file): \($0.reason)" }.joined(separator: "\n")
            }
            alert.informativeText = info
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }
}

/// Stops marking files when set from the main thread.
private final class MarkingCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var isCancelled: Bool { lock.withLock { flag } }
    func cancel() { lock.withLock { flag = true } }
}
