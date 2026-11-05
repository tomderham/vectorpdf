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

extension PDFViewerViewModel {
    // MARK: - Showing and hiding layers

    /// Shows or hides a layer listed in `layers`, then redraws and reads the pages again: hidden
    /// layers aren't drawn, printed, selected or found by search, and nor are annotations on
    /// them. Which layers are shown isn't saved.
    public func toggleLayer(_ layer: PDFLayer) {
        guard layer.canToggle, let doc = document else { return }
        do {
            try doc.toggleLayer(id: layer.id)
        } catch {
            print("Failed to change layer \(layer.name): \(error)")
            return
        }
        layers = doc.layers()
        layerVisibility = doc.layerVisibility()
        layerVisibilityChanged()
    }

    /// Tells the renderer and search about the layers now shown, and drops everything drawn or
    /// read before.
    private func layerVisibilityChanged() {
        guard let doc = document else { return }
        layerGeneration += 1
        let generation = layerGeneration
        thumbnailImages.removeAll()
        // Its text, for selection, came from the layers then shown.
        pageStructuredData.removeAll()
        activeSelection = nil
        additionalSelectionPages = []
        let pages = renderedPages.keys.sorted { abs($0 - currentPageIndex) < abs($1 - currentPageIndex) }
        Task {
            // Read when it runs, not when asked: another change may have come first.
            let states = doc.layerStates()
            await renderActor.setLayerStates(states)
            await searchActor.setLayerStates(states)
            guard document === doc, layerGeneration == generation else { return }
            for page in pages {
                await renderPage(page, replacing: true)
            }
            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                performSearch()
            }
        }
    }

    // MARK: - Annotations on layers

    /// The layers annotations can be put on.
    public var annotationLayers: [PDFLayer] {
        layers.filter(\.canHoldAnnotations)
    }

    /// The name of the layer with this object number, for menus.
    public func layerName(_ objectNumber: Int?) -> String? {
        guard let objectNumber else { return nil }
        return layers.first { $0.objectNumber == objectNumber }?.displayName
    }

    /// Whether the layer with this object number is hidden. A layer the document doesn't list
    /// counts as shown unless it's known to be hidden.
    public func isLayerHidden(_ objectNumber: Int?) -> Bool {
        guard let objectNumber else { return false }
        return layerVisibility[objectNumber] == false
    }

    /// Whether an annotation is on the page as layers are shown now.
    public func isAnnotationShown(_ annot: PDFAnnotation) -> Bool {
        !isLayerHidden(annot.layerObjectNumber)
    }

    /// The annotations the canvas draws and can hit on a page: not ones on hidden layers.
    public func shownAnnotations(onPage pageIndex: Int) -> [PDFAnnotation] {
        (pageAnnotations[pageIndex] ?? []).filter(isAnnotationShown)
    }

    /// Whether a comment's annotation is on a hidden layer, so the Comments tab leaves it out.
    public func isOnHiddenLayer(_ comment: PDFAnnotationComment) -> Bool {
        comment.layerObjectNumber.map { isLayerHidden($0) } ?? comment.isOnHiddenLayer
    }

    /// Sets the layer annotations made from now on go on, or none, showing it if it's hidden so
    /// they don't disappear as they're made.
    public func setAnnotationLayer(_ objectNumber: Int?) {
        annotationLayer = objectNumber
        showLayerIfHidden(objectNumber)
    }

    private func showLayerIfHidden(_ objectNumber: Int?) {
        guard isLayerHidden(objectNumber),
              let layer = layers.first(where: { $0.objectNumber == objectNumber }), layer.canToggle else { return }
        toggleLayer(layer)
    }

    /// The layer for an annotation `recordAddedAnnotation` is adding: the one it was on when
    /// Undo puts it back or an edit replaces it, otherwise the one new annotations go on.
    func layerForAddedAnnotation(onPage pageIndex: Int) -> Int? {
        if let restoring = restoringAnnotationLayer {
            return restoring
        }
        if let old = annotationBeingReplaced {
            return old.documentObjectNumber.flatMap { document?.annotationLayer(pageIndex: pageIndex, objectNumber: $0) }
                ?? old.layerObjectNumber
        }
        guard let layer = annotationLayer, layerVisibility[layer] != nil else { return nil }
        showLayerIfHidden(layer)
        return layer
    }

    /// Moves an annotation onto a layer, or off any, with Undo.
    public func moveAnnotation(_ annot: PDFAnnotation, toLayer layer: Int?) {
        guard let number = annot.documentObjectNumber else { return }
        moveAnnotation(pageIndex: annot.pageIndex, objectNumber: number, toLayer: layer)
    }

    /// Moves the annotation with this object number onto a layer, or off any, with Undo. Its
    /// replies go with it, as they're shown with it.
    public func moveAnnotation(pageIndex: Int, objectNumber: Int, toLayer layer: Int?) {
        guard let doc = document, !isReadOnlyDocument else { return }
        let old = doc.annotationLayer(pageIndex: pageIndex, objectNumber: objectNumber)
        guard old != layer else { return }
        do {
            try doc.setAnnotationLayer(pageIndex: pageIndex, objectNumber: objectNumber, layer: layer)
        } catch {
            print("Failed to move annotation \(objectNumber) to layer \(layer ?? 0): \(error)")
            return
        }
        let index = pageAnnotations[pageIndex]?.firstIndex { $0.documentObjectNumber == objectNumber }
        if let index {
            pageAnnotations[pageIndex]?[index].layerObjectNumber = layer
        }
        undoManager.registerUndo(withTarget: self) { $0.moveAnnotation(pageIndex: pageIndex, objectNumber: objectNumber, toLayer: old) }
        if !undoManager.isUndoing, !undoManager.isRedoing {
            undoManager.setActionName("Move to Layer")
        }
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
        noteAnnotationsChanged(onPage: pageIndex)
        // The canvas draws the ones it holds; the renderer draws the rest, from its own copy.
        if index == nil {
            refreshRendererCopy(pages: [pageIndex])
        }
    }

    // MARK: - New layers

    /// Adds a layer to the document, shown, and makes it the one new annotations go on.
    /// Unlike showing and hiding layers, this changes the file.
    @discardableResult
    public func addLayer(named name: String) -> Int? {
        guard let doc = document, doc.isPDF, !isReadOnlyDocument else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let number: Int
        do {
            number = try doc.addLayer(named: trimmed)
        } catch {
            print("Failed to add layer \(trimmed): \(error)")
            return nil
        }
        layers = doc.layers()
        layerVisibility = doc.layerVisibility()
        annotationLayer = number
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
        // The renderer and search only follow layers their copy of the file has.
        refreshRendererCopy(pages: [])
        return number
    }

    /// Asks for a name and adds a layer with it (see `addLayer`).
    public func promptForNewLayer() {
        guard !Self.isRunningTests else { return }
        let alert = NSAlert()
        alert.messageText = "New Layer"
        alert.informativeText = "Annotations you make go on the new layer, so you can show and hide them together. The layer is saved with the document."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = annotationLayers.contains { $0.name == "Markups" } ? "" : "Markups"
        field.placeholderString = "Layer Name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add Layer")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        addLayer(named: field.stringValue)
    }

    /// Saves the document to its working copy and opens the renderer and search on it again, for
    /// a change their copies don't have, then redraws `pages`.
    private func refreshRendererCopy(pages: Set<Int>) {
        guard let doc = document else { return }
        if workingCopyPath == nil {
            workingCopyPath = Self.newWorkingCopyPath()
        }
        guard let workingPath = workingCopyPath else { return }
        do {
            try doc.save(to: workingPath)
        } catch {
            print("Failed to save working copy: \(error)")
            return
        }
        Task { @MainActor in
            guard await self.reopenActors(at: workingPath) else { return }
            for page in pages {
                self.thumbnailImages.removeValue(forKey: page)
                if self.renderedPages[page] != nil {
                    await self.renderPage(page, replacing: true)
                }
            }
        }
    }
}
