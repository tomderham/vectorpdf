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
    // MARK: - Layers

    /// Shows or hides a layer listed in `layers`, then redraws and reads the pages again: hidden
    /// layers aren't drawn, printed, selected or found by search. The file isn't changed.
    public func toggleLayer(_ layer: PDFLayer) {
        guard layer.canToggle, let doc = document else { return }
        do {
            try doc.toggleLayer(id: layer.id)
        } catch {
            print("Failed to change layer \(layer.name): \(error)")
            return
        }
        layers = doc.layers()
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
}
