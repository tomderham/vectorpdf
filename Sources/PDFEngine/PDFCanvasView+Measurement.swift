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
import Combine
import CoreGraphics
import MuPDFBridge

extension PDFCanvasView {
    // MARK: - Engineering Measurement & Takeoff Helpers

    func drawMeasureLength(annot: PDFAnnotation, pFrame: NSRect, pBounds: CGRect, isSelected: Bool) {
        guard annot.measurementPoints.count >= 2 else { return }
        let p0 = annot.measurementPoints[0]
        let p1 = annot.measurementPoints[1]
        let color = annot.color.nsColor
        let strokeW = max(annot.strokeWidth * viewModel.effectiveZoom, 1.2)

        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let len = hypot(dx, dy)
        guard len > 0.001 else { return }

        let nx = (-dy / len) * annot.leaderOffset
        let ny = (dx / len) * annot.leaderOffset
        let off0 = CGPoint(x: p0.x + nx, y: p0.y + ny)
        let off1 = CGPoint(x: p1.x + nx, y: p1.y + ny)

        let sp0 = canvasPoint(for: p0, pFrame: pFrame, pBounds: pBounds)
        let sp1 = canvasPoint(for: p1, pFrame: pFrame, pBounds: pBounds)
        let soff0 = canvasPoint(for: off0, pFrame: pFrame, pBounds: pBounds)
        let soff1 = canvasPoint(for: off1, pFrame: pFrame, pBounds: pBounds)

        color.setStroke()

        // Witness lines
        if abs(annot.leaderOffset) > 1.0 {
            let wPath = NSBezierPath()
            wPath.lineWidth = max(strokeW * 0.75, 1.0)
            let dashes: [CGFloat] = [4.0, 2.0]
            wPath.setLineDash(dashes, count: 2, phase: 0)
            wPath.move(to: sp0)
            wPath.line(to: soff0)
            wPath.move(to: sp1)
            wPath.line(to: soff1)
            wPath.stroke()
        }

        // Dimension line
        let dPath = NSBezierPath()
        dPath.lineWidth = strokeW
        dPath.move(to: soff0)
        dPath.line(to: soff1)
        dPath.stroke()

        // 45° Architectural Slash Tick Marks
        let tickLen: CGFloat = 6.0 * viewModel.effectiveZoom
        let sLen = hypot(soff1.x - soff0.x, soff1.y - soff0.y)
        if sLen > 0.001 {
            let ux = (soff1.x - soff0.x) / sLen
            let uy = (soff1.y - soff0.y) / sLen
            let tx = (ux - uy) * 0.7071 * tickLen
            let ty = (ux + uy) * 0.7071 * tickLen

            let tPath = NSBezierPath()
            tPath.lineWidth = strokeW * 1.4
            tPath.move(to: NSPoint(x: soff0.x - tx, y: soff0.y - ty))
            tPath.line(to: NSPoint(x: soff0.x + tx, y: soff0.y + ty))
            tPath.move(to: NSPoint(x: soff1.x - tx, y: soff1.y - ty))
            tPath.line(to: NSPoint(x: soff1.x + tx, y: soff1.y + ty))
            tPath.stroke()
        }

        // Dimension Text Pill
        let mid = NSPoint(x: (soff0.x + soff1.x) * 0.5, y: (soff0.y + soff1.y) * 0.5)
        let text = annot.measurementText.isEmpty ? annot.text : annot.measurementText
        drawMeasurementTextPill(text: text, at: mid, color: color, isSelected: isSelected)
    }

    func drawMeasurePerimeter(annot: PDFAnnotation, pFrame: NSRect, pBounds: CGRect, isSelected: Bool) {
        guard annot.measurementPoints.count >= 2 else { return }
        let color = annot.color.nsColor
        let strokeW = max(annot.strokeWidth * viewModel.effectiveZoom, 1.5)

        let path = NSBezierPath()
        path.lineWidth = strokeW
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let screenPts = annot.measurementPoints.map { canvasPoint(for: $0, pFrame: pFrame, pBounds: pBounds) }
        path.move(to: screenPts[0])
        for pt in screenPts.dropFirst() {
            path.line(to: pt)
        }
        color.setStroke()
        path.stroke()

        for pt in screenPts {
            let dotRect = NSRect(x: pt.x - 3.0, y: pt.y - 3.0, width: 6.0, height: 6.0)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            color.setStroke()
            let b = NSBezierPath(ovalIn: dotRect)
            b.lineWidth = 1.2
            b.stroke()
        }

        let midIdx = screenPts.count / 2
        let mid = screenPts[midIdx]
        let text = annot.measurementText.isEmpty ? annot.text : annot.measurementText
        drawMeasurementTextPill(text: "Perimeter: \(text)", at: mid, color: color, isSelected: isSelected)
    }

    func drawMeasureArea(annot: PDFAnnotation, pFrame: NSRect, pBounds: CGRect, isSelected: Bool) {
        guard annot.measurementPoints.count >= 3 else { return }
        let color = annot.color.nsColor
        let strokeW = max(annot.strokeWidth * viewModel.effectiveZoom, 1.8)

        let path = NSBezierPath()
        path.lineWidth = strokeW
        let screenPts = annot.measurementPoints.map { canvasPoint(for: $0, pFrame: pFrame, pBounds: pBounds) }
        path.move(to: screenPts[0])
        for pt in screenPts.dropFirst() {
            path.line(to: pt)
        }
        path.close()

        color.withAlphaComponent(0.22).setFill()
        path.fill()

        color.setStroke()
        path.stroke()

        var sumX: CGFloat = 0, sumY: CGFloat = 0
        for pt in screenPts {
            sumX += pt.x
            sumY += pt.y
        }
        let centroid = NSPoint(x: sumX / CGFloat(screenPts.count), y: sumY / CGFloat(screenPts.count))
        let text = annot.measurementText.isEmpty ? annot.text : annot.measurementText
        drawMeasurementTextPill(text: "Area: \(text)", at: centroid, color: color, isSelected: isSelected)
    }

    func drawMeasureAngle(annot: PDFAnnotation, pFrame: NSRect, pBounds: CGRect, isSelected: Bool) {
        guard annot.measurementPoints.count >= 3 else { return }
        let color = annot.color.nsColor
        let strokeW = max(annot.strokeWidth * viewModel.effectiveZoom, 1.5)

        let r1 = canvasPoint(for: annot.measurementPoints[0], pFrame: pFrame, pBounds: pBounds)
        let apex = canvasPoint(for: annot.measurementPoints[1], pFrame: pFrame, pBounds: pBounds)
        let r2 = canvasPoint(for: annot.measurementPoints[2], pFrame: pFrame, pBounds: pBounds)

        let path = NSBezierPath()
        path.lineWidth = strokeW
        path.move(to: apex)
        path.line(to: r1)
        path.move(to: apex)
        path.line(to: r2)
        color.setStroke()
        path.stroke()

        let angle1 = atan2(r1.y - apex.y, r1.x - apex.x) * 180.0 / .pi
        let angle2 = atan2(r2.y - apex.y, r2.x - apex.x) * 180.0 / .pi
        // The measured value is the interior angle (at most 180°), so the arc must take the short
        // way round from ray 1 to ray 2 — whichever direction that is.
        var sweep = angle2 - angle1
        if sweep > 180 { sweep -= 360 }
        if sweep < -180 { sweep += 360 }
        let arcRadius: CGFloat = 24.0 * viewModel.effectiveZoom

        let arcPath = NSBezierPath()
        arcPath.appendArc(withCenter: apex, radius: arcRadius, startAngle: angle1, endAngle: angle1 + sweep, clockwise: sweep < 0)
        arcPath.lineWidth = strokeW * 0.8
        color.setStroke()
        arcPath.stroke()

        let midAngle = (angle1 + sweep * 0.5) * .pi / 180.0
        let pillPos = NSPoint(x: apex.x + (arcRadius + 14.0) * cos(midAngle), y: apex.y + (arcRadius + 14.0) * sin(midAngle))
        let text = annot.measurementText.isEmpty ? annot.text : annot.measurementText
        drawMeasurementTextPill(text: text, at: pillPos, color: color, isSelected: isSelected)
    }

    func drawMeasurementTextPill(text: String, at point: NSPoint, color: NSColor, isSelected: Bool) {
        guard !text.isEmpty else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.0, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let str = text as NSString
        let size = str.size(withAttributes: attrs)
        let padX: CGFloat = 6.0
        let padY: CGFloat = 3.0
        let pillRect = NSRect(
            x: point.x - size.width * 0.5 - padX,
            y: point.y - size.height * 0.5 - padY,
            width: size.width + padX * 2.0,
            height: size.height + padY * 2.0
        )

        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 4.0, yRadius: 4.0)
        pillPath.fill()

        (isSelected ? NSColor.controlAccentColor : color.withAlphaComponent(0.7)).setStroke()
        pillPath.lineWidth = isSelected ? 1.8 : 0.8
        pillPath.stroke()

        str.draw(at: NSPoint(x: pillRect.minX + padX, y: pillRect.minY + padY), withAttributes: attrs)
    }

    /// The outline to fill for a highlight: a rounded box, or the quad itself on slanted text,
    /// e.g. OCR of a skewed scan.
    func highlightPath(for quad: PDFQuad, minSize: CGSize, pFrame: NSRect, pBounds: CGRect) -> NSBezierPath {
        if quad.isAxisAligned() {
            let r = quad.boundingRect
            let origin = canvasPoint(for: r.origin, pFrame: pFrame, pBounds: pBounds)
            let size = NSSize(width: max(r.width * viewModel.effectiveZoom, minSize.width),
                              height: max(r.height * viewModel.effectiveZoom, minSize.height))
            return NSBezierPath(roundedRect: NSRect(origin: origin, size: size), xRadius: 2, yRadius: 2)
        }
        let path = NSBezierPath()
        let corners = [quad.ul, quad.ur, quad.lr, quad.ll].map {
            canvasPoint(for: $0, pFrame: pFrame, pBounds: pBounds)
        }
        path.move(to: corners[0])
        corners.dropFirst().forEach { path.line(to: $0) }
        path.close()
        path.lineJoinStyle = .round
        return path
    }

    func canvasPoint(for pagePoint: CGPoint, pFrame: NSRect, pBounds: CGRect) -> NSPoint {
        NSPoint(
            x: pFrame.minX + (pagePoint.x - pBounds.minX) * viewModel.effectiveZoom,
            y: pFrame.minY + (pagePoint.y - pBounds.minY) * viewModel.effectiveZoom
        )
    }

    func applySnapping(
        to candidate: CGPoint,
        fromPoint: CGPoint?,
        inPage pageIndex: Int,
        modifierFlags: NSEvent.ModifierFlags
    ) -> CGPoint {
        var snapped = candidate
        isSnappedOrtho = false
        isSnappedVertex = false

        // 1. Magnetic vertex snapping
        if viewModel.isVertexSnapEnabled {
            let snapThreshold: CGFloat = 8.0 / viewModel.effectiveZoom
            var closestDist = snapThreshold
            var closestVertex: CGPoint? = nil

            if case let annots = viewModel.shownAnnotations(onPage: pageIndex), !annots.isEmpty {
                for annot in annots {
                    for pt in annot.measurementPoints {
                        let d = hypot(candidate.x - pt.x, candidate.y - pt.y)
                        if d < closestDist {
                            closestDist = d
                            closestVertex = pt
                        }
                    }
                    if let tp = annot.targetPoint {
                        let d = hypot(candidate.x - tp.x, candidate.y - tp.y)
                        if d < closestDist {
                            closestDist = d
                            closestVertex = tp
                        }
                    }
                    if let r = annot.rect {
                        let corners = [
                            CGPoint(x: r.minX, y: r.minY),
                            CGPoint(x: r.maxX, y: r.minY),
                            CGPoint(x: r.minX, y: r.maxY),
                            CGPoint(x: r.maxX, y: r.maxY)
                        ]
                        for c in corners {
                            let d = hypot(candidate.x - c.x, candidate.y - c.y)
                            if d < closestDist {
                                closestDist = d
                                closestVertex = c
                            }
                        }
                    }
                }
            }

            for pt in currentMeasurePoints {
                let d = hypot(candidate.x - pt.x, candidate.y - pt.y)
                if d < closestDist {
                    closestDist = d
                    closestVertex = pt
                }
            }

            if let v = closestVertex {
                isSnappedVertex = true
                return v
            }
        }

        // 2. Ortho / 45° snapping constraint (Shift key or isOrthoSnapEnabled)
        let isShiftHeld = modifierFlags.contains(.shift)
        if (viewModel.isOrthoSnapEnabled || isShiftHeld), let origin = fromPoint {
            let dx = candidate.x - origin.x
            let dy = candidate.y - origin.y
            let dist = hypot(dx, dy)
            if dist > 2.0 {
                var angle = atan2(dy, dx)
                if angle < 0 { angle += 2.0 * .pi }
                let step = CGFloat.pi / 4.0
                let snappedAngle = round(angle / step) * step
                snapped = CGPoint(
                    x: origin.x + dist * cos(snappedAngle),
                    y: origin.y + dist * sin(snappedAngle)
                )
                isSnappedOrtho = true
                currentSnappedGuideOrigin = origin
            }
        }

        return snapped
    }

    func commitCurrentPerimeter() {
        guard let pIdx = currentMeasurePage, currentMeasurePoints.count >= 2 else { return }
        var totalDist: Double = 0.0
        for i in 1..<currentMeasurePoints.count {
            totalDist += hypot(currentMeasurePoints[i].x - currentMeasurePoints[i-1].x, currentMeasurePoints[i].y - currentMeasurePoints[i-1].y)
        }
        let pageScale = viewModel.scaleConfig(for: pIdx)
        let text = pageScale.formatLength(points: totalDist)
        viewModel.addMeasurementAnnotation(
            pageIndex: pIdx,
            type: .measurePerimeter,
            points: currentMeasurePoints,
            value: totalDist,
            formattedText: text,
            color: viewModel.selectedAnnotationColor,
            strokeWidth: viewModel.drawStrokeWidth
        )
        currentMeasurePage = nil
        currentMeasurePoints = []
        currentMeasureCandidatePoint = nil
        needsDisplay = true
    }

    func commitCurrentArea() {
        guard let pIdx = currentMeasurePage, currentMeasurePoints.count >= 3 else { return }
        let areaPts = calculateShoelaceArea(points: currentMeasurePoints)
        let pageScale = viewModel.scaleConfig(for: pIdx)
        let text = pageScale.formatArea(pointsSquared: areaPts)
        viewModel.addMeasurementAnnotation(
            pageIndex: pIdx,
            type: .measureArea,
            points: currentMeasurePoints,
            value: areaPts,
            formattedText: text,
            color: viewModel.selectedAnnotationColor,
            strokeWidth: viewModel.drawStrokeWidth
        )
        currentMeasurePage = nil
        currentMeasurePoints = []
        currentMeasureCandidatePoint = nil
        needsDisplay = true
    }

    func commitCurrentAngle() {
        guard let pIdx = currentMeasurePage, currentMeasurePoints.count == 3 else { return }
        let r1 = currentMeasurePoints[0]
        let apex = currentMeasurePoints[1]
        let r2 = currentMeasurePoints[2]
        let deg = calculateAngleDegrees(r1: r1, apex: apex, r2: r2)
        let text = String(format: "%.1f°", deg)
        viewModel.addMeasurementAnnotation(
            pageIndex: pIdx,
            type: .measureAngle,
            points: currentMeasurePoints,
            value: deg,
            formattedText: text,
            color: viewModel.selectedAnnotationColor,
            strokeWidth: viewModel.drawStrokeWidth
        )
        currentMeasurePage = nil
        currentMeasurePoints = []
        currentMeasureCandidatePoint = nil
        needsDisplay = true
    }

    func calculateShoelaceArea(points: [CGPoint]) -> Double {
        return PDFMeasurementGeometry.shoelaceArea(points: points)
    }

    func calculateAngleDegrees(r1: CGPoint, apex: CGPoint, r2: CGPoint) -> Double {
        return PDFMeasurementGeometry.angleDegrees(r1: r1, apex: apex, r2: r2)
    }
}
