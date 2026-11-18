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
import UniformTypeIdentifiers

/// How far recognizing a document's scanned pages has got, for the sheet shown meanwhile.
@MainActor
final class RecognitionProgress: ObservableObject {
    @Published var done = 0
    let total: Int
    @Published var isCancelled = false

    init(total: Int) { self.total = total }
}

struct RecognitionProgressView: View {
    @ObservedObject var progress: RecognitionProgress
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
            HStack {
                Text("Page \(min(progress.done + 1, progress.total)) of \(progress.total)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel") { progress.isCancelled = true }
                    .keyboardShortcut(.cancelAction)
                    .disabled(progress.isCancelled)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

extension PDFViewerViewModel {
    /// A PDF with scanned pages, whose recognized text can be saved in it.
    public var canSaveRecognizedText: Bool {
        guard let doc = document, doc.isPDF, !isReadOnlyDocument else { return false }
        return !ocrResults.isEmpty || !detectedScannedPages.isEmpty
    }

    /// Saves the document with the text recognized on its scanned pages written into them, so
    /// other apps can search, select and copy it. Recognizes the scanned pages not done yet first.
    /// Other unsaved changes are saved too, and the document is opened again from the file.
    public func saveWithRecognizedText() async {
        guard let doc = document, canSaveRecognizedText else { return }
        flushPendingFormEdits()
        guard await recognizeAllScannedPagesShowingProgress(title: "Recognizing text in scanned pages…"),
              document === doc else { return }
        await writeRecognizedText(of: doc, to: URL(fileURLWithPath: doc.filePath))
    }

    /// Asks where to save a copy of the document with its recognized text in it (see
    /// `saveWithRecognizedText`), leaving the document as it is.
    public func exportSearchablePDF() {
        guard let doc = document, doc.isPDF, !isReadOnlyDocument else { return }
        flushPendingFormEdits()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canCreateDirectories = true
        let baseName = ((doc.filePath as NSString).lastPathComponent as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName) (Searchable).pdf"
        panel.prompt = "Save"
        panel.title = "Save as Searchable PDF"
        panel.message = "Text is recognized on scanned pages and saved in the copy, so other apps can search and select it."

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self, self.document === doc else { return }
                guard await self.recognizeAllScannedPagesShowingProgress(title: "Recognizing text in scanned pages…"),
                      self.document === doc else { return }
                await self.writeRecognizedText(of: doc, to: url)
            }
        }
        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    /// Recognizes every scanned page not recognized yet, in a sheet with progress and Cancel.
    /// False when cancelled, or the document changed meanwhile.
    func recognizeAllScannedPagesShowingProgress(title: String) async -> Bool {
        guard let doc = document else { return false }
        let generation = ocrGeneration
        let scanned = await Task.detached(priority: .userInitiated) {
            (0..<doc.pageCount).filter { doc.isScannedPage(pageIndex: $0) }
        }.value
        guard document === doc, ocrGeneration == generation else { return false }
        let pages = scanned.filter { ocrResults[$0] == nil }
        guard !pages.isEmpty else { return true }

        let progress = RecognitionProgress(total: pages.count)
        var sheet: NSWindow?
        if !Self.isRunningTests, let window = currentWindow, window.attachedSheet == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
            panel.contentView = NSHostingView(rootView: RecognitionProgressView(progress: progress, title: title))
            panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 380, height: 100))
            window.beginSheet(panel, completionHandler: nil)
            sheet = panel
        }
        defer {
            if let sheet { sheet.sheetParent?.endSheet(sheet) }
        }
        for page in pages {
            guard !progress.isCancelled, document === doc, ocrGeneration == generation else { return false }
            if ocrResults[page] == nil {
                await runOCR(onPageIndex: page)
            }
            progress.done += 1
        }
        return !progress.isCancelled && document === doc && ocrGeneration == generation
    }

    /// Saves `doc` to `url` with the recognized text in it; when that's the document's own file,
    /// opens it again from there, as the edits and text are now in the file.
    private func writeRecognizedText(of doc: PDFDocumentCore, to url: URL) async {
        let results = Array(ocrResults.values)
        let overwritesOpenFile = url.path == doc.filePath
        if overwritesOpenFile { fileChangeWatcher = nil }
        let failure: String? = await Task.detached(priority: .userInitiated) {
            do {
                try doc.saveWithRecognizedText(to: url.path, results: results)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        if let failure {
            if overwritesOpenFile { armFileChangeWatcher(path: doc.filePath) }
            showErrorAlert(title: "Failed to Save Recognized Text", message: failure)
            return
        }
        if overwritesOpenFile, document === doc {
            isDocumentEdited = false
            currentWindow?.isDocumentEdited = false
            await loadDocument(from: url.path, password: currentDocumentPassword)
        } else {
            PDFViewerAppCoordinator.shared.noteRecentDocument(url)
        }
    }
}
