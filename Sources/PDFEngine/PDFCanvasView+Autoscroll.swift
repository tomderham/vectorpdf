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

// Dragging past the edge of the view scrolls it, faster the further past, and keeps scrolling
// while the pointer is held there: AppKit only sends drag events while the mouse moves. Each step
// sends the drag again, so a selection, box or line follows the content under the pointer.

extension PDFCanvasView {
    /// Steps a second while the pointer is held past the edge.
    static let autoscrollInterval: TimeInterval = 1.0 / 60

    /// A drag that makes something: a selection, a box, a shape, a line, a drawing or a move.
    var hasAutoscrollableDrag: Bool {
        isDraggingSelection || activeAnnotationDrag != nil || currentMeasurePage != nil
            || currentRedactionPage != nil || currentShapePage != nil || currentCalloutPage != nil
            || currentDrawingPageIndex != nil
    }

    /// The part of the canvas the scroll view shows, leaving out what's under the toolbar.
    var unobscuredVisibleRect: CGRect? {
        guard let scrollView = enclosingScrollView else { return nil }
        let insets = scrollView.contentInsets
        var rect = scrollView.contentView.bounds
        // The canvas is flipped, so the top inset is at the low y.
        rect.origin.x += insets.left
        rect.origin.y += insets.top
        rect.size.width -= insets.left + insets.right
        rect.size.height -= insets.top + insets.bottom
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }

    /// How far, and which way, to scroll in one step for a pointer at `point` (canvas space):
    /// zero inside the visible area.
    static func autoscrollStep(for point: CGPoint, visible: CGRect) -> CGVector {
        func step(_ overshoot: CGFloat) -> CGFloat {
            guard overshoot != 0 else { return 0 }
            // A few points a step just past the edge, up to a page-ish jump far past it.
            let magnitude = min(max(abs(overshoot) * 0.5, 4), 120)
            return overshoot < 0 ? -magnitude : magnitude
        }
        let dx = point.x < visible.minX ? point.x - visible.minX : (point.x > visible.maxX ? point.x - visible.maxX : 0)
        let dy = point.y < visible.minY ? point.y - visible.minY : (point.y > visible.maxY ? point.y - visible.maxY : 0)
        return CGVector(dx: step(dx), dy: step(dy))
    }

    /// Starts scrolling when a drag event is past the edge; the timer stops it once the pointer is
    /// back inside or the button is up.
    func updateAutoscroll(for event: NSEvent) {
        guard hasAutoscrollableDrag, autoscrollTimer == nil, let visible = unobscuredVisibleRect else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard Self.autoscrollStep(for: point, visible: visible) != .zero else { return }
        let timer = Timer(timeInterval: Self.autoscrollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoscrollTick() }
        }
        // Keeps firing during event tracking.
        RunLoop.main.add(timer, forMode: .common)
        autoscrollTimer = timer
    }

    func stopAutoscroll() {
        autoscrollTimer?.invalidate()
        autoscrollTimer = nil
    }

    private func autoscrollTick() {
        guard let window, NSEvent.pressedMouseButtons & 1 != 0,
              autoscroll(towards: window.mouseLocationOutsideOfEventStream) else {
            stopAutoscroll()
            return
        }
    }

    /// One step: scrolls towards a pointer past the edge, at `locationInWindow`, then drags to it.
    /// False when there's nothing to do: no drag, or the pointer is inside the view.
    @discardableResult
    func autoscroll(towards locationInWindow: CGPoint) -> Bool {
        guard let window, hasAutoscrollableDrag, let scrollView = enclosingScrollView,
              let visible = unobscuredVisibleRect else { return false }
        let step = Self.autoscrollStep(for: convert(locationInWindow, from: nil), visible: visible)
        guard step != .zero else { return false }
        let clipView = scrollView.contentView
        var bounds = clipView.bounds
        bounds.origin.x += step.dx
        bounds.origin.y += step.dy
        let origin = clipView.constrainBoundsRect(bounds).origin
        if origin != clipView.bounds.origin {
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
        }
        // The pointer is now over different content: drag to it.
        if let drag = NSEvent.mouseEvent(
            with: .leftMouseDragged, location: locationInWindow, modifierFlags: NSEvent.modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ) {
            mouseDragged(with: drag)
        }
        return true
    }
}
