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
    /// Whether anything shows where the pointer is: the status bar or the rulers.
    var showsPointerReadout: Bool {
        let coordinator = PDFViewerAppCoordinator.shared
        return coordinator.showsStatusBar || coordinator.showsRulers
    }

    /// Tells the status bar and rulers where the pointer is on the page; nil when it's left the
    /// canvas.
    func updatePointerReadout(_ event: NSEvent?) {
        guard showsPointerReadout else { return }
        guard let event, let doc = viewModel.document else {
            viewModel.canvasReadout.setPointer(nil)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard let (pageIndex, _, pagePoint) = pageInfo(at: point), pageIndex < doc.pageBounds.count else {
            viewModel.canvasReadout.setPointer(nil)
            return
        }
        let origin = doc.pageBounds[pageIndex].origin
        viewModel.canvasReadout.setPointer(PointerLocation(
            pageIndex: pageIndex,
            point: CGPoint(x: pagePoint.x - origin.x, y: pagePoint.y - origin.y)
        ))
    }

    /// The figures of the measurement being drawn, for the status bar.
    func updateMeasurementReadout() {
        guard PDFViewerAppCoordinator.shared.showsStatusBar || !viewModel.canvasReadout.measurement.isEmpty else { return }
        guard let page = currentMeasurePage else {
            viewModel.canvasReadout.setMeasurement([])
            return
        }
        viewModel.canvasReadout.setMeasurement(CanvasReadout.measurementItems(
            mode: viewModel.canvasMode,
            points: currentMeasurePoints,
            candidate: currentMeasureCandidatePoint,
            scale: viewModel.scaleConfig(for: page)
        ))
    }
}

extension PDFCanvasView {
    /// Moves or resizes an annotation as the Inspector asked: a move as a drag of the whole
    /// annotation, then a resize as a drag of the corner away from its origin.
    func applyInspectorEdit(_ edit: AnnotationGeometryEdit) {
        func current() -> PDFAnnotation? {
            let id = selectedAnnotation?.id ?? edit.annotationID
            return viewModel.pageAnnotations[edit.pageIndex]?.first { $0.id == id }
        }
        guard var annotation = viewModel.pageAnnotations[edit.pageIndex]?.first(where: { $0.id == edit.annotationID }) else { return }
        let tiny: (CGFloat, CGFloat) = (0.0001, 0.0001)
        if edit.offset != .zero {
            commitAnnotationEdit(annotation, pageIndex: edit.pageIndex, part: .entireAnnotation, delta: edit.offset, minimumDistance: tiny)
            guard let moved = current() else { needsDisplay = true; return }
            annotation = moved
        }
        if edit.growth != .zero {
            // In page coordinates the box's origin is its minimum corner; this handle moves the
            // opposite one (see updatedRect).
            commitAnnotationEdit(annotation, pageIndex: edit.pageIndex, part: .resizeTopRight, delta: edit.growth, minimumDistance: tiny)
        }
        needsDisplay = true
    }
}
