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
import SyncTeXLink

/// A request to show, and briefly highlight, what a line of TeX source made. The view scrolls
/// only if it isn't on screen.
public struct SyncTeXReveal: Equatable, Sendable {
    /// Changes with every request, so showing the same line twice highlights it twice.
    public let token: Int
    public let pageIndex: Int
    /// The line's boxes, in page space.
    public let rects: [CGRect]

    /// All of `rects`.
    public var bounds: CGRect {
        rects.dropFirst().reduce(rects.first ?? .null) { $0.union($1) }
    }
}

extension PDFViewerViewModel {
    /// How long a build may take to write the SyncTeX file after the PDF.
    static let syncTeXBuildAllowance: TimeInterval = 5
    /// How far from the requested line to look when TeX recorded nothing for it (a blank line or
    /// a comment between paragraphs).
    static let syncTeXNearbyLines = 10

    /// Looks for the SyncTeX file again: the first build with SyncTeX on can come after opening.
    @discardableResult
    public func refreshSyncTeXAvailability() -> Bool {
        guard let doc = document, !isComparePane else {
            hasSyncTeX = false
            return false
        }
        let found = SyncTeXFile.find(forPDF: doc.filePath) != nil
        if hasSyncTeX != found { hasSyncTeX = found }
        if !found { syncTeXIndex = nil }
        return found
    }

    /// The document's SyncTeX index, parsing (off the main thread) if there's none yet or TeX has
    /// rewritten the file. With `waitingForBuild`, a build still writing it is given a few seconds
    /// to finish. Nil when there's no SyncTeX file, or it was left by a different document.
    func currentSyncTeXIndex(waitingForBuild: Bool) async -> SyncTeXIndex? {
        guard let doc = document, refreshSyncTeXAvailability() else { return nil }
        let pdfPath = doc.filePath

        if waitingForBuild {
            let pdfModified = loadedFileModificationDate ?? .distantPast
            let deadline = Date().addingTimeInterval(Self.syncTeXBuildAllowance)
            while Date() < deadline, let file = SyncTeXFile.find(forPDF: pdfPath) {
                // Busy: TeX is writing it now. Older than a PDF just written: the build hasn't got
                // to it yet. (Older than a PDF saved long ago is fine: saving annotations rewrites
                // the PDF but leaves its text where TeX put it.)
                let synctexModified = file.signature?.modified ?? .distantPast
                let justBuilt = Date().timeIntervalSince(pdfModified) < Self.syncTeXBuildAllowance
                guard file.isBusy || (justBuilt && synctexModified < pdfModified.addingTimeInterval(-1)) else { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        if let index = syncTeXIndex, index.pdfPath == pdfPath, index.isCurrent {
            return index
        }
        guard let file = SyncTeXFile.find(forPDF: pdfPath) else { return nil }
        let index = await Task.detached(priority: .userInitiated) {
            SyncTeXIndex(file: file, pdfPath: pdfPath)
        }.value
        // The document may have changed while it parsed.
        guard document?.filePath == pdfPath else { return nil }
        guard let index, index.matches(pageCount: doc.pageCount) else {
            syncTeXIndex = nil
            return nil
        }
        syncTeXIndex = index
        return index
    }

    /// Reloads the document if a build has replaced it since it was loaded (or `force`), waiting
    /// for a load already under way to finish first.
    func reloadIfReplaced(force: Bool) async {
        for _ in 0..<200 where isLoadingDocument {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let doc = document else { return }
        let onDisk = Self.modificationDate(ofFileAt: doc.filePath)
        if force || (onDisk != nil && onDisk != loadedFileModificationDate) {
            await handleExternalFileChange(path: doc.filePath)
        }
    }

    /// Forward search: shows, and briefly highlights, what `line` of `source` made, scrolling only
    /// if it's off screen. TeX records nothing for some lines (blank ones, comments), so the
    /// nearest line it did record is used, looking first below. Returns whether anything was found.
    @discardableResult
    public func showSyncTeXLocation(source: String?, line: Int, column: Int?, reloading: Bool = false) async -> Bool {
        await reloadIfReplaced(force: reloading)
        guard let doc = document, let index = await currentSyncTeXIndex(waitingForBuild: true) else { return false }
        // Without a source file, the main file: the PDF's name with .tex.
        let sourcePath = source ?? (URL(fileURLWithPath: doc.filePath).deletingPathExtension().path + ".tex")
        let hint = currentPageIndex
        let candidates = [line] + (1...Self.syncTeXNearbyLines).flatMap { [line + $0, line - $0] }.filter { $0 > 0 }
        let found: [SyncTeXBox] = await Task.detached(priority: .userInitiated) {
            for candidate in candidates {
                let boxes = index.boxes(source: sourcePath, line: candidate, column: candidate == line ? column : nil, pageHint: hint)
                if !boxes.isEmpty { return boxes }
            }
            return []
        }.value
        guard document === doc, let page = found.first?.pageIndex, page < doc.pageCount,
              let mapping = doc.syncTeXMapping(for: page) else { return false }
        let bounds = doc.pageBounds[page]
        let rects = found.map { mapping.pageRect(fromSyncTeX: $0.rect).intersection(bounds.insetBy(dx: -2, dy: -2)) }
            .filter { !$0.isNull && $0.width > 0.5 && $0.height > 0.5 }
        guard !rects.isEmpty else { return false }
        loadPageMetadata(page)
        syncTeXReveal = SyncTeXReveal(token: (syncTeXReveal?.token ?? 0) &+ 1, pageIndex: page, rects: Self.mergedLines(rects))
        jumpToPage(page)
        return true
    }

    /// Boxes on the same line joined into one, so a line TeX set as several boxes highlights as
    /// one band.
    nonisolated static func mergedLines(_ rects: [CGRect]) -> [CGRect] {
        var lines: [CGRect] = []
        for rect in rects.sorted(by: { ($0.minY, $0.minX) < ($1.minY, $1.minX) }) {
            if let last = lines.last, abs(last.midY - rect.midY) < min(last.height, rect.height) / 2 {
                lines[lines.count - 1] = last.union(rect)
            } else {
                lines.append(rect)
            }
        }
        return lines
    }

    /// Backward search: the source line that made what's at `pagePoint` on page `pageIndex`.
    public func syncTeXSourceLocation(pageIndex: Int, pagePoint: CGPoint) async -> SyncTeXSourceLocation? {
        guard let doc = document, let mapping = doc.syncTeXMapping(for: pageIndex),
              let index = await currentSyncTeXIndex(waitingForBuild: false) else { return nil }
        let point = mapping.syncTeXPoint(fromPage: pagePoint)
        return await Task.detached(priority: .userInitiated) {
            index.sourceLocation(pageIndex: pageIndex, point: point)
        }.value
    }

    /// Backward search: opens, in the editor chosen in Settings, the source line that made what's
    /// at `pagePoint`. Says why if it can't.
    public func showInEditor(pageIndex: Int, pagePoint: CGPoint) {
        Task { @MainActor in
            guard let location = await syncTeXSourceLocation(pageIndex: pageIndex, pagePoint: pagePoint) else {
                if hasSyncTeX {
                    showErrorAlert(title: "No Source Here",
                                   message: "SyncTeX has no source line for that place. Try clicking on text, or build the document again.")
                } else {
                    NSSound.beep()
                }
                return
            }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try EditorLauncher.open(location)
                }.value
            } catch {
                showErrorAlert(title: "Couldn't Open the Source", message: error.localizedDescription)
            }
        }
    }
}

extension PDFViewerAppCoordinator {
    /// Acts on a `vectorpdf://synctex` URL from `displayline`: shows the PDF's tab (opening the
    /// PDF if no tab has it) and the place the source line made. Does nothing for a PDF without a
    /// SyncTeX file, so a link on a web page can't open arbitrary files, and never starts an editor.
    public func handleSyncTeXForwardRequest(_ request: SyncTeXForwardRequest) async {
        let path = request.pdfPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue,
              SyncTeXFile.find(forPDF: path) != nil else { return }

        let target: PDFViewerViewModel
        if let open = self.viewModel(showingFileAt: path) {
            target = open
            if let window = open.currentWindow {
                if let group = window.tabGroup, group.selectedWindow !== window {
                    group.selectedWindow = window
                }
                if request.inBackground { window.orderFront(nil) } else { window.makeKeyAndOrderFront(nil) }
            }
        } else {
            let window = DocumentWindowing.openDocumentHandlingEmptyStart(url: URL(fileURLWithPath: path))
            if request.inBackground { window.orderFront(nil) }
            // Wait for the new tab's view model to load the file.
            var found: PDFViewerViewModel?
            for _ in 0..<200 {
                if let candidate = self.viewModel(showingFileAt: path), !candidate.isLoadingDocument {
                    found = candidate
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let found else { return }
            target = found
        }
        if !request.inBackground { NSApp.activate(ignoringOtherApps: true) }
        await target.showSyncTeXLocation(source: request.sourcePath, line: request.line, column: request.column, reloading: request.reloads)
    }
}

