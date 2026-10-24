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
    public func updateWidgetValueDebounced(pageIndex: Int, widgetIndex: Int, value: String) {
        let key = "p\(pageIndex)_w\(widgetIndex)"
        debouncedWidgetTasks[key]?.cancel()
        pendingWidgetValues[key] = (pageIndex, widgetIndex, value)
        
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
        
        debouncedWidgetTasks[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
            guard !Task.isCancelled else { return }
            self?.debouncedWidgetTasks.removeValue(forKey: key)
            self?.pendingWidgetValues.removeValue(forKey: key)
            self?.commitWidgetValue(pageIndex: pageIndex, widgetIndex: widgetIndex, value: value)
        }
    }
    
    public func updateWidgetValue(pageIndex: Int, widgetIndex: Int, value: String) {
        let key = "p\(pageIndex)_w\(widgetIndex)"
        debouncedWidgetTasks[key]?.cancel()
        debouncedWidgetTasks.removeValue(forKey: key)
        pendingWidgetValues.removeValue(forKey: key)
        commitWidgetValue(pageIndex: pageIndex, widgetIndex: widgetIndex, value: value)
    }
    
    /// Flushes any pending debounced form edits and commits active field edits immediately.
    public func flushPendingFormEdits() {
        currentWindow?.makeFirstResponder(nil)
        guard !pendingWidgetValues.isEmpty else { return }
        for (_, task) in debouncedWidgetTasks {
            task.cancel()
        }
        debouncedWidgetTasks.removeAll()
        let pending = pendingWidgetValues
        pendingWidgetValues.removeAll()
        for (_, entry) in pending {
            commitWidgetValue(pageIndex: entry.pageIndex, widgetIndex: entry.widgetIndex, value: entry.value)
        }
    }
    
    private func commitWidgetValue(pageIndex: Int, widgetIndex: Int, value: String) {
        guard let doc = document else { return }
        // Focusing a field and leaving it commits its value too; unchanged, that's not an edit.
        if let current = pageFormWidgets[pageIndex]?.first(where: { $0.widgetIndex == widgetIndex }),
           current.value == value {
            return
        }
        do {
            try doc.setFormWidgetValue(pageIndex: pageIndex, widgetIndex: widgetIndex, value: value)
            let refreshed = doc.loadFormWidgets(for: pageIndex)
            pageFormWidgets[pageIndex] = refreshed
            // Other pages only matter if they have fields a calculation could have changed.
            for otherPage in pageFormWidgets.keys where otherPage != pageIndex && pageFormWidgets[otherPage]?.isEmpty == false {
                pageFormWidgets[otherPage] = doc.loadFormWidgets(for: otherPage)
            }
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            NotificationCenter.default.post(name: .formWidgetDidChange, object: nil)
        } catch {
            print("Failed to set form widget value: \(error)")
        }
    }
    
    public func resetForm() {
        guard let doc = document else { return }
        for (_, task) in debouncedWidgetTasks {
            task.cancel()
        }
        debouncedWidgetTasks.removeAll()
        pendingWidgetValues.removeAll()
        do {
            try doc.resetForm()
            for page in pageFormWidgets.keys {
                pageFormWidgets[page] = doc.loadFormWidgets(for: page)
            }
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            NotificationCenter.default.post(name: .formWidgetDidChange, object: nil)
        } catch {
            print("Failed to reset form: \(error)")
        }
    }
    
    /// Places a visual signature stamp (drawn or picked image, not a cryptographic signature) into
    /// `rect` on a page. PDFSignatureStampButton shows the image itself, so no on-screen preview
    /// refresh is needed here beyond updating the in-memory document for the next save.
    public func insertSignatureStamp(pageIndex: Int, rect: CGRect, imageData: Data) {
        guard let doc = document else { return }
        // `rect` (PDFFormWidget.rect) is top-down; stampImage needs bottom-up. Flip using
        // pageBounds' actual top edge (maxY), not height, since MediaBox may not start at y=0.
        let pageTopY = doc.pageBounds[pageIndex].maxY
        let nativeRect = CGRect(x: rect.minX, y: pageTopY - rect.maxY, width: rect.width, height: rect.height)
        do {
            try doc.stampImage(pageIndex: pageIndex, rect: nativeRect, imageData: imageData)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
        } catch {
            print("Failed to insert signature stamp: \(error)")
        }
    }
}
