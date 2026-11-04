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
    // MARK: - Zoom Controls
    // Zoom bounds come from PDFViewerAppCoordinator.minZoomScale/maxZoomScale, which also drive
    // the View menu's Zoom In/Out enablement.
    public func zoomIn() {
        let step: CGFloat = 0.25
        let epsilon: CGFloat = 0.001
        let nextStep = (floor((zoomScale + epsilon) / step) + 1.0) * step
        setZoom(min(round(nextStep * 100) / 100, PDFViewerAppCoordinator.maxZoomScale))
    }

    public func zoomOut() {
        guard zoomScale > PDFViewerAppCoordinator.minZoomScale else { return }
        let step: CGFloat = 0.25
        let epsilon: CGFloat = 0.001
        let prevStep = (ceil((zoomScale - epsilon) / step) - 1.0) * step
        setZoom(min(zoomScale, max(round(prevStep * 100) / 100, PDFViewerAppCoordinator.minZoomScale)))
    }
    
    public func resetZoom() {
        setZoom(1.0)
    }
    
    /// The pages keep their bitmaps until they're rendered again at the new zoom (see
    /// `hasCurrentRender`), so they don't flash blank.
    public func setZoom(_ newZoom: CGFloat) {
        zoomScale = newZoom
        Task { await renderPage(currentPageIndex) }
    }

    public func zoomToFitWidth(viewportWidth: CGFloat? = nil) {
        guard let doc = document, doc.pageBounds.indices.contains(currentPageIndex) else { return }
        let sideways = isRotatedSideways
        let pageW = sideways ? doc.pageBounds[currentPageIndex].height : doc.pageBounds[currentPageIndex].width
        
        let effectiveW: CGFloat
        if isTwoPageMode {
            let pageGap: CGFloat = 16.0
            if currentPageIndex == 0 {
                let leftW = doc.pageCount > 1 ? (sideways ? doc.pageBounds[1].height : doc.pageBounds[1].width) : pageW
                effectiveW = leftW + pageGap + pageW
            } else {
                let isLeft = currentPageIndex % 2 == 1
                let leftIdx = isLeft ? currentPageIndex : currentPageIndex - 1
                let rightIdx = leftIdx + 1
                let leftW = sideways ? doc.pageBounds[leftIdx].height : doc.pageBounds[leftIdx].width
                let rightW = rightIdx < doc.pageCount ? (sideways ? doc.pageBounds[rightIdx].height : doc.pageBounds[rightIdx].width) : leftW
                effectiveW = leftW + pageGap + rightW
            }
        } else {
            effectiveW = pageW
        }
        
        // PDFVirtualizedScrollView applies 32pt padding on both left and right (total 64pt)
        let horizontalPadding: CGFloat = 64.0
        let availW: CGFloat
        if let custom = viewportWidth, custom > 100 {
            availW = max(custom - horizontalPadding, 200)
        } else if let vp = currentViewportSize, vp.width > 100 {
            availW = max(vp.width - horizontalPadding, 200)
        } else if let window = currentWindow ?? NSApplication.shared.keyWindow {
            let sidebarOffset: CGFloat = (isTwoPageMode || !isSidebarVisible) ? 0 : 260
            availW = max(window.contentLayoutRect.width - sidebarOffset - horizontalPadding, 200)
        } else {
            availW = 700
        }
        let targetEffectiveZoom = availW / effectiveW
        let baseScale = (PDFViewerAppCoordinator.shared.scaleMode == .physical ? displayScale : 1.0)
        let targetZoom = targetEffectiveZoom / max(baseScale, 0.1)
        let clamped = min(max(targetZoom, PDFViewerAppCoordinator.minZoomScale), PDFViewerAppCoordinator.maxZoomScale)
        setZoom(round(clamped * 100) / 100)
    }

    public func zoomToFitPage(viewportSize: CGSize? = nil) {
        guard let doc = document, doc.pageBounds.indices.contains(currentPageIndex) else { return }
        let sideways = isRotatedSideways
        let pageW = sideways ? doc.pageBounds[currentPageIndex].height : doc.pageBounds[currentPageIndex].width
        let pageH = sideways ? doc.pageBounds[currentPageIndex].width : doc.pageBounds[currentPageIndex].height
        
        let effectiveW: CGFloat
        if isTwoPageMode {
            let pageGap: CGFloat = 16.0
            if currentPageIndex == 0 {
                let leftW = doc.pageCount > 1 ? (sideways ? doc.pageBounds[1].height : doc.pageBounds[1].width) : pageW
                effectiveW = leftW + pageGap + pageW
            } else {
                let isLeft = currentPageIndex % 2 == 1
                let leftIdx = isLeft ? currentPageIndex : currentPageIndex - 1
                let rightIdx = leftIdx + 1
                let leftW = sideways ? doc.pageBounds[leftIdx].height : doc.pageBounds[leftIdx].width
                let rightW = rightIdx < doc.pageCount ? (sideways ? doc.pageBounds[rightIdx].height : doc.pageBounds[rightIdx].width) : leftW
                effectiveW = leftW + pageGap + rightW
            }
        } else {
            effectiveW = pageW
        }
        
        let horizontalPadding: CGFloat = 64.0
        let verticalPadding: CGFloat = 48.0
        let availW: CGFloat
        let availH: CGFloat
        if let size = viewportSize, size.width > 100, size.height > 100 {
            availW = max(size.width - horizontalPadding, 200)
            availH = max(size.height - verticalPadding, 200)
        } else if let vp = currentViewportSize, vp.width > 100, vp.height > 100 {
            availW = max(vp.width - horizontalPadding, 200)
            availH = max(vp.height - verticalPadding, 200)
        } else if let window = currentWindow ?? NSApplication.shared.keyWindow {
            let sidebarOffset: CGFloat = (isTwoPageMode || !isSidebarVisible) ? 0 : 260
            availW = max(window.contentLayoutRect.width - sidebarOffset - horizontalPadding, 200)
            availH = max(window.contentLayoutRect.height - verticalPadding, 200)
        } else {
            availW = 700
            availH = 900
        }
        let scaleX = availW / effectiveW
        let scaleY = availH / pageH
        let targetEffectiveZoom = min(scaleX, scaleY)
        let baseScale = (PDFViewerAppCoordinator.shared.scaleMode == .physical ? displayScale : 1.0)
        let targetZoom = targetEffectiveZoom / max(baseScale, 0.1)
        let clamped = min(max(targetZoom, PDFViewerAppCoordinator.minZoomScale), PDFViewerAppCoordinator.maxZoomScale)
        setZoom(round(clamped * 100) / 100)
    }

    public func toggleMarkupToolbar() {
        isMarkupBarVisible.toggle()
        if !isMarkupBarVisible {
            canvasMode = .select
        }
    }
}
