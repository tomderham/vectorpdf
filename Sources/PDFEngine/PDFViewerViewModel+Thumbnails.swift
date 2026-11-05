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
    // MARK: - Page Thumbnail Generation

    public func requestThumbnail(for pageIndex: Int) {
        guard thumbnailImages[pageIndex] == nil, !thumbnailsLoading.contains(pageIndex), let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return }
        thumbnailsLoading.insert(pageIndex)
        let startLayers = layerGeneration
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let rendered = try await self.renderActor.renderPage(pageIndex: pageIndex, scale: 0.25)
                let cgImg = rendered.image
                let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: CGFloat(cgImg.width), height: CGFloat(cgImg.height)))
                await MainActor.run {
                    self.thumbnailsLoading.remove(pageIndex)
                    if self.layerGeneration == startLayers {
                        self.thumbnailImages[pageIndex] = nsImg
                    } else {
                        // Drawn before layers were shown or hidden; its placeholder has
                        // already asked, so ask again.
                        self.requestThumbnail(for: pageIndex)
                    }
                }
            } catch {
                await MainActor.run {
                    _ = self.thumbnailsLoading.remove(pageIndex)
                }
            }
        }
    }

    // MARK: - Thumbnail Selection Management

    public func selectThumbnail(pageIndex: Int, isShift: Bool, isCommand: Bool) {
        if let doc = document {
            guard pageIndex >= 0, pageIndex < doc.pageCount else { return }
        }

        if isCommand {
            if selectedThumbnailPageIndices.contains(pageIndex) {
                if selectedThumbnailPageIndices.count > 1 {
                    selectedThumbnailPageIndices.remove(pageIndex)
                }
            } else {
                selectedThumbnailPageIndices.insert(pageIndex)
            }
            selectionAnchorPageIndex = pageIndex
            jumpToPage(pageIndex)
        } else if isShift {
            let start = min(selectionAnchorPageIndex, pageIndex)
            let end = max(selectionAnchorPageIndex, pageIndex)
            selectedThumbnailPageIndices = Set(start...end)
            jumpToPage(pageIndex)
        } else {
            selectedThumbnailPageIndices = [pageIndex]
            selectionAnchorPageIndex = pageIndex
            jumpToPage(pageIndex)
        }
    }

    public func selectAllThumbnails() {
        guard let doc = document, doc.pageCount > 0 else { return }
        selectedThumbnailPageIndices = Set(0..<doc.pageCount)
    }

    // MARK: - Thumbnail Drag and Drop Lifecycle

    public func startThumbnailDrag(pageIndex: Int) {
        self.endThumbnailDrag()
        // Dragging a thumbnail reorders pages.
        guard !isReadOnlyDocument else { return }

        // If the dragged thumbnail is part of multi-selection, drag the whole selection;
        // otherwise, collapse selection to just this page.
        if selectedThumbnailPageIndices.contains(pageIndex) {
            self.draggedThumbnailPageIndices = selectedThumbnailPageIndices
        } else {
            self.selectedThumbnailPageIndices = [pageIndex]
            self.selectionAnchorPageIndex = pageIndex
            self.draggedThumbnailPageIndices = [pageIndex]
        }
        self.draggedThumbnailPageIndex = pageIndex

        // Local event monitor for immediate mouse-up and Escape key detection
        self.dragEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if event.type == .leftMouseUp || (event.type == .keyDown && event.keyCode == 53 /* Escape */) {
                    self.endThumbnailDrag()
                }
            }
            return event
        }

        // Repeating timer in .common run loop mode to guarantee reset if mouse is released anywhere,
        // even if AppKit's dragging session swallowed the mouse-up event.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if self.draggedThumbnailPageIndex == nil || (NSEvent.pressedMouseButtons & 1) == 0 {
                    self.endThumbnailDrag()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.dragWatchdogTimer = timer
    }

    public func endThumbnailDrag() {
        self.dragWatchdogTimer?.invalidate()
        self.dragWatchdogTimer = nil
        if let monitor = self.dragEventMonitor {
            NSEvent.removeMonitor(monitor)
            self.dragEventMonitor = nil
        }
        if self.draggedThumbnailPageIndex != nil || !self.draggedThumbnailPageIndices.isEmpty || self.activeThumbnailDropSlot != nil {
            self.draggedThumbnailPageIndex = nil
            self.draggedThumbnailPageIndices = []
            self.activeThumbnailDropSlot = nil
        }
    }

    /// Checks all active snapshots for missing cached thumbnail images (e.g. when synced across devices
    /// via iCloud KVS without local disk cache files) and regenerates them in the background.
    public func regenerateMissingThumbnails() {
        guard let doc = document else { return }
        let currentDocPath = doc.filePath
        let snapshotsToRecreate = activeSnapshots.filter { snap in
            (snap.thumbnailFileName != nil || snap.label.hasPrefix("Area Anchor"))
            && snap.thumbnailImage == nil
            && snap.targetRect != nil
            && snap.targetPage >= 0
            && snap.targetPage < doc.pageCount
        }
        guard !snapshotsToRecreate.isEmpty else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            var didRegenerateAny = false
            for snap in snapshotsToRecreate {
                guard let rect = snap.targetRect, rect.width > 2 && rect.height > 2 else { continue }
                do {
                    let cgImage = try await self.renderActor.renderPageRect(
                        pageIndex: snap.targetPage,
                        rect: rect,
                        scale: 2.0
                    )
                    let rep = NSBitmapImageRep(cgImage: cgImage)
                    if let pngData = rep.representation(using: .png, properties: [:]) {
                        SnapshotTarget.writeThumbnailFile(id: snap.id, data: pngData)
                        didRegenerateAny = true
                    }
                } catch {
                    // Gracefully continue on error
                }
            }
            if didRegenerateAny {
                await MainActor.run {
                    guard let activeDoc = self.document, activeDoc.filePath == currentDocPath else { return }
                    var changed = false
                    for idx in self.activeSnapshots.indices {
                        let snap = self.activeSnapshots[idx]
                        if snap.thumbnailFileName == nil && SnapshotTarget.hasCachedThumbnail(fileName: "\(snap.id.uuidString).png") {
                            self.activeSnapshots[idx].thumbnailFileName = "\(snap.id.uuidString).png"
                            changed = true
                        }
                    }
                    if changed {
                        self.saveReadingStateIfNeeded()
                    }
                    self.objectWillChange.send()
                }
            }
        }
    }
}
