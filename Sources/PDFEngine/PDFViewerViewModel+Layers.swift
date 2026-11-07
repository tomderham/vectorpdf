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

    // MARK: - Layer configurations

    /// Shows and hides layers as one of the document's configurations says, and lists them as it
    /// does: a CAD drawing may come with one for plotting, or a map with one for each language.
    /// Choosing the one already chosen puts back how it shows them. Nothing is saved.
    public func chooseLayerConfiguration(_ configuration: PDFLayerConfiguration) {
        guard let doc = document else { return }
        do {
            try doc.chooseLayerConfiguration(configuration.id)
        } catch {
            print("Failed to choose layer configuration \(configuration.displayName): \(error)")
            return
        }
        layers = doc.layers()
        layerVisibility = doc.layerVisibility()
        layerConfiguration = doc.layerConfiguration
        layerConfigurationVisibility = layerVisibility
        layerVisibilityChanged()
    }

    /// The configuration chosen, for the Layers tab.
    public var chosenLayerConfiguration: PDFLayerConfiguration? {
        layerConfigurations.first { $0.id == layerConfiguration }
    }

    /// Whether a layer the configuration showed or hid has been changed since. Layers added since
    /// don't count.
    private func noteLayerConfigurationChanges() {
        let changed = layerConfigurationVisibility.contains { number, shown in
            layerVisibility[number].map { $0 != shown } ?? false
        }
        if changed != isLayerConfigurationChanged {
            isLayerConfigurationChanged = changed
        }
    }

    /// Tells the renderer and search about the layers now shown, and drops everything drawn or
    /// read before.
    private func layerVisibilityChanged() {
        guard let doc = document else { return }
        noteLayerConfigurationChanges()
        // The Agent's index leaves out text on hidden layers too: build it again (the Agent tab,
        // if it's showing, starts that as the index goes back to idle).
        if agentIndexState != .idle {
            invalidateAgentIndex(deleteCache: false)
        }
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

    // MARK: - Adding, renaming and deleting layers

    /// Adds a layer to the document, shown, and makes it the one new annotations go on. In a
    /// document without layers, this is its first. Unlike showing and hiding layers, this changes
    /// the file. Undo takes it out again.
    @discardableResult
    public func addLayer(named name: String) -> Int? {
        guard let doc = document, doc.isPDF, !isReadOnlyDocument else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let before = doc.copyLayerConfiguration() else { return nil }
        let number: Int
        do {
            number = try doc.addLayer(named: trimmed)
        } catch {
            print("Failed to add layer \(trimmed): \(error)")
            return nil
        }
        registerLayerListUndo("New Layer", restoring: before, annotations: [], layer: nil, otherwise: nil)
        layersChanged(annotationPages: [])
        annotationLayer = number
        return number
    }

    /// Renames a layer, with Undo. This changes the file.
    public func renameLayer(objectNumber: Int, to name: String) {
        guard let doc = document, !isReadOnlyDocument,
              let old = layers.first(where: { $0.objectNumber == objectNumber })?.name else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old else { return }
        do {
            try doc.renameLayer(objectNumber: objectNumber, to: trimmed)
        } catch {
            print("Failed to rename layer \(old): \(error)")
            return
        }
        undoManager.registerUndo(withTarget: self) { $0.renameLayer(objectNumber: objectNumber, to: old) }
        if !undoManager.isUndoing, !undoManager.isRedoing { undoManager.setActionName("Rename Layer") }
        layersChanged(annotationPages: [])
    }

    /// The layers that can be deleted: ones holding only annotations, or nothing. Deleting one
    /// the drawing itself is on would leave that content always shown, so those can't be.
    public func deletableLayers() -> [PDFLayer] {
        guard let doc = document, !isReadOnlyDocument else { return [] }
        return annotationLayers.filter { layer in
            layer.objectNumber.map { !doc.layerHoldsPageContent(objectNumber: $0) } ?? false
        }
    }

    /// Deletes a layer holding only annotations, with Undo. The annotations on it stay on the
    /// page, on no layer.
    @discardableResult
    public func deleteLayer(objectNumber: Int) -> Bool {
        guard let doc = document, !isReadOnlyDocument, layerVisibility[objectNumber] != nil,
              !doc.layerHoldsPageContent(objectNumber: objectNumber),
              let before = doc.copyLayerConfiguration() else { return false }
        let onIt = doc.annotationsOnLayer(objectNumber: objectNumber)
        do {
            try putAnnotations(onIt, onLayer: nil)
            try doc.removeLayer(objectNumber: objectNumber)
        } catch {
            print("Failed to delete layer \(objectNumber): \(error)")
            try? putAnnotations(onIt, onLayer: objectNumber)
            return false
        }
        registerLayerListUndo("Delete Layer", restoring: before, annotations: onIt, layer: objectNumber, otherwise: nil)
        layersChanged(annotationPages: Set(onIt.map(\.pageIndex)))
        return true
    }

    /// Undo for a change to the list of layers: puts back `configuration`, and the annotations on
    /// `layer` (nil for none), registering the opposite for Redo.
    private func registerLayerListUndo(_ name: String, restoring configuration: PDFDocumentCore.LayerConfiguration,
                                       annotations: [(pageIndex: Int, objectNumber: Int)], layer: Int?, otherwise: Int?) {
        undoManager.registerUndo(withTarget: self) { vm in
            guard let doc = vm.document, let now = doc.copyLayerConfiguration() else { return }
            do {
                // A layer the annotations go back on has to be there first; one they leave, after.
                if layer != nil { try doc.restoreLayerConfiguration(configuration) }
                try vm.putAnnotations(annotations, onLayer: layer)
                if layer == nil { try doc.restoreLayerConfiguration(configuration) }
            } catch {
                print("Failed to undo the change to layers: \(error)")
                return
            }
            vm.registerLayerListUndo(name, restoring: now, annotations: annotations, layer: otherwise, otherwise: layer)
            vm.layersChanged(annotationPages: Set(annotations.map(\.pageIndex)))
        }
        if !undoManager.isUndoing, !undoManager.isRedoing { undoManager.setActionName(name) }
    }

    /// Puts annotations on a layer, or none, without Undo of their own.
    private func putAnnotations(_ annotations: [(pageIndex: Int, objectNumber: Int)], onLayer layer: Int?) throws {
        guard let doc = document else { return }
        for annot in annotations {
            try doc.setAnnotationLayer(pageIndex: annot.pageIndex, objectNumber: annot.objectNumber, layer: layer)
            if let index = pageAnnotations[annot.pageIndex]?.firstIndex(where: { $0.documentObjectNumber == annot.objectNumber }) {
                pageAnnotations[annot.pageIndex]?[index].layerObjectNumber = layer
            }
        }
    }

    /// After layers were added, renamed or deleted: reads them again, and brings the renderer and
    /// search, which only follow the layers their copy of the file has, up to date.
    private func layersChanged(annotationPages: Set<Int>) {
        guard let doc = document else { return }
        layers = doc.layers()
        layerVisibility = doc.layerVisibility()
        layerConfigurations = doc.layerConfigurations()
        layerConfiguration = doc.layerConfiguration
        noteLayerConfigurationChanges()
        if let layer = annotationLayer, layerVisibility[layer] == nil {
            annotationLayer = nil
        }
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
        if !annotationPages.isEmpty {
            noteAnnotationsChanged(onPage: nil)
        }
        refreshRendererCopy(pages: annotationPages)
    }

    // MARK: - Asking

    /// Asks for a name and adds a layer with it (see `addLayer`).
    public func promptForNewLayer() {
        guard !Self.isRunningTests, document?.isPDF == true, !isReadOnlyDocument else { return }
        let alert = NSAlert()
        alert.messageText = "New Layer"
        alert.informativeText = "Annotations you make go on the new layer, so you can show and hide them together. The layer is saved with the document."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = layers.contains { $0.name == "Markups" } ? "" : "Markups"
        field.placeholderString = "Layer Name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add Layer")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        addLayer(named: field.stringValue)
    }

    /// Asks which layer to rename, and what to.
    public func promptToRenameLayer() {
        guard !Self.isRunningTests, !isReadOnlyDocument else { return }
        let candidates = annotationLayers
        guard !candidates.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Layer"
        alert.informativeText = "The new name is saved with the document."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Layer Name"
        let chooser = LayerChooser(candidates, selecting: annotationLayer) { field.stringValue = $0.name }
        field.stringValue = chooser.selected.name
        alert.accessoryView = chooser.stack(with: field)
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, let number = chooser.selected.objectNumber else { return }
        renameLayer(objectNumber: number, to: field.stringValue)
    }

    /// Asks which layer to delete, of the ones that can be.
    public func promptToDeleteLayer() {
        guard !Self.isRunningTests, !isReadOnlyDocument else { return }
        let candidates = deletableLayers()
        guard !candidates.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Layers Can Be Deleted"
            alert.informativeText = "The drawing itself is on this document's layers. Deleting one would leave what's on it always shown, so only layers that hold just annotations can be deleted."
            alert.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete Layer"
        alert.informativeText = "Annotations on the layer stay on the page, on no layer. Layers the drawing itself is on can't be deleted, so they aren't listed."
        let chooser = LayerChooser(candidates, selecting: annotationLayer) { _ in }
        alert.accessoryView = chooser.stack(with: nil)
        let delete = alert.addButton(withTitle: "Delete")
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let number = chooser.selected.objectNumber else { return }
        deleteLayer(objectNumber: number)
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

/// A pop-up of layers for the Rename and Delete Layer alerts.
@MainActor
private final class LayerChooser: NSObject {
    private let layers: [PDFLayer]
    private let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
    private let onChange: (PDFLayer) -> Void

    init(_ layers: [PDFLayer], selecting objectNumber: Int?, onChange: @escaping (PDFLayer) -> Void) {
        self.layers = layers
        self.onChange = onChange
        super.init()
        popUp.addItems(withTitles: layers.map(\.displayName))
        if let index = layers.firstIndex(where: { $0.objectNumber == objectNumber }) {
            popUp.selectItem(at: index)
        }
        popUp.target = self
        popUp.action = #selector(changed)
    }

    var selected: PDFLayer { layers[max(0, popUp.indexOfSelectedItem)] }

    @objc private func changed() {
        onChange(selected)
    }

    /// The pop-up, and `field` below it if there's one. Holds on to this chooser while shown.
    func stack(with field: NSTextField?) -> NSView {
        let stack = NSStackView(views: [popUp] + (field.map { [$0] } ?? []))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: field == nil ? 26 : 60)
        objc_setAssociatedObject(stack, &layerChooserKey, self, .OBJC_ASSOCIATION_RETAIN)
        return stack
    }
}

@MainActor private var layerChooserKey: UInt8 = 0
