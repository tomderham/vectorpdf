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

extension PDFCanvasView {
    /// Draws the grid (View > Show Grid) and the page's guides over it.
    func drawGridAndGuides(onPage page: Int) {
        let coordinator = PDFViewerAppCoordinator.shared
        var guides = viewModel.guides(onPage: page)
        if let preview = guidePreview, preview.pageIndex == page {
            guides.removeAll { $0.id == preview.guide.id }
            guides.append(preview.guide)
        }
        guard coordinator.showsGrid || !guides.isEmpty, let geometry = pageGeometry(for: page) else { return }
        let bounds = geometry.pageBounds
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: geometry.frame).addClip()

        func line(_ isVertical: Bool, _ position: CGFloat) -> (NSPoint, NSPoint) {
            let a = isVertical ? CGPoint(x: position, y: bounds.minY) : CGPoint(x: bounds.minX, y: position)
            let b = isVertical ? CGPoint(x: position, y: bounds.maxY) : CGPoint(x: bounds.maxX, y: position)
            return (geometry.canvasPoint(forPagePoint: a), geometry.canvasPoint(forPagePoint: b))
        }

        if coordinator.showsGrid {
            let spacing = CGFloat(coordinator.gridSpacing)
            // Skipped when its lines would be under 6 pixels apart.
            if spacing * geometry.zoom >= 6 {
                let minor = NSBezierPath(), major = NSBezierPath()
                minor.lineWidth = 0.5
                major.lineWidth = 0.75
                for isVertical in [true, false] {
                    let length = isVertical ? bounds.width : bounds.height
                    let count = Int(length / spacing)
                    guard count < 4000 else { continue }
                    for i in 0...count {
                        let (a, b) = line(isVertical, (isVertical ? bounds.minX : bounds.minY) + CGFloat(i) * spacing)
                        let path = i % 5 == 0 ? major : minor
                        path.move(to: a)
                        path.line(to: b)
                    }
                }
                NSColor.systemTeal.withAlphaComponent(0.18).setStroke()
                minor.stroke()
                NSColor.systemTeal.withAlphaComponent(0.32).setStroke()
                major.stroke()
            }
        }

        for guide in guides {
            let (a, b) = line(guide.isVertical, guide.position)
            let path = NSBezierPath()
            path.move(to: a)
            path.line(to: b)
            path.lineWidth = 1
            let isMoving = guidePreview?.guide.id == guide.id
            (isMoving ? NSColor.controlAccentColor : NSColor.systemPink).withAlphaComponent(0.85).setStroke()
            path.stroke()
        }
    }

    /// The guide within a few pixels of `canvasPoint`, while the rulers show.
    func guide(at canvasPoint: CGPoint) -> (pageIndex: Int, guide: PageGuide)? {
        guard PDFViewerAppCoordinator.shared.showsRulers,
              let (page, _, pagePoint) = pageInfo(at: canvasPoint) else { return nil }
        let reach = 4 / max(viewModel.effectiveZoom, 0.01)
        return viewModel.guides(onPage: page)
            .first { abs(($0.isVertical ? pagePoint.x : pagePoint.y) - $0.position) <= reach }
            .map { (page, $0) }
    }

    func beginGuideDrag(at canvasPoint: CGPoint) -> Bool {
        guard viewModel.canvasMode == .select, let (page, guide) = guide(at: canvasPoint) else { return false }
        activeGuideDrag = (page, guide.id)
        guidePreview = (page, guide)
        NSCursor.closedHand.set()
        return true
    }

    func continueGuideDrag(_ event: NSEvent) -> Bool {
        guard let drag = activeGuideDrag, var guide = guidePreview?.guide else { return false }
        let point = convert(event.locationInWindow, from: nil)
        if let pagePoint = pagePoint(forCanvasPoint: point, onPage: drag.pageIndex) {
            guide.position = guide.isVertical ? pagePoint.x : pagePoint.y
            guidePreview = (drag.pageIndex, guide)
        }
        needsDisplay = true
        return true
    }

    func endGuideDrag(_ event: NSEvent) -> Bool {
        guard let drag = activeGuideDrag else { return false }
        activeGuideDrag = nil
        let point = convert(event.locationInWindow, from: nil)
        // Dropped off its page: removed, as in drawing apps.
        if let (page, _, _) = pageInfo(at: point), page == drag.pageIndex, let guide = guidePreview?.guide {
            viewModel.moveGuide(drag.id, onPage: drag.pageIndex, to: guide.position)
        } else {
            viewModel.removeGuide(drag.id, onPage: drag.pageIndex)
        }
        guidePreview = nil
        NSCursor.openHand.set()
        needsDisplay = true
        return true
    }
}
