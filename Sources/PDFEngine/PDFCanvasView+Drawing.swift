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
    // MARK: - Direct Quartz 2D Drawing
    
    public override func draw(_ dirtyRect: NSRect) {
        guard hasLiveViewModel, let doc = viewModel.document else {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
            return
        }
        
        // High-quality area-averaging interpolation for razor-sharp downscaled text and lines
        NSGraphicsContext.current?.imageInterpolation = .high
        
        // Canvas background
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        pruneThemedPageCache()
        defer { scheduleDetailRenders() }

        guard let visiblePages = pages(in: dirtyRect) else { return }
        for pageIdx in visiblePages {
            guard let canvasFrame = pageFrame(for: pageIdx) else { continue }
            guard canvasFrame.intersects(dirtyRect) else { continue }
            
            let pBounds = doc.pageBounds[pageIdx]
            
            // Page fill color follows the active theme (dark or sepia) — matters mainly while a
            // page is still rendering (below) and briefly shows just this background.
            let pageFillColor: NSColor
            switch activeColorAppearance {
            case .dark:
                pageFillColor = NSColor(calibratedWhite: CGFloat(Self.darkModeBackgroundGray) / 255.0, alpha: 1.0)
            case .sepia:
                pageFillColor = NSColor(
                    calibratedRed: CGFloat(Self.sepiaBackgroundR) / 255.0,
                    green: CGFloat(Self.sepiaBackgroundG) / 255.0,
                    blue: CGFloat(Self.sepiaBackgroundB) / 255.0,
                    alpha: 1.0
                )
            case .light, .system:
                pageFillColor = .white
            }

            // 1. Page Background & Drop Shadow
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 4
            shadow.set()

            pageFillColor.setFill()
            let pagePath = NSBezierPath(rect: canvasFrame)
            pagePath.fill()
            NSGraphicsContext.restoreGraphicsState()

            // Page border
            NSColor.separatorColor.setStroke()
            pagePath.lineWidth = 0.5
            pagePath.stroke()

            // From here on the page is drawn in its layout space (see PageGeometry): unrotated, and
            // turned onto the canvas by `viewRotation` in a rotated view, so the same page-to-view
            // arithmetic below serves every view. A rotated page starts on a whole pixel, as an
            // unrotated bitmap does through backingAlignedRect, so it isn't drawn blurred.
            let rotation = viewModel.viewRotationDegrees
            let alignedFrame = backingAlignedRect(canvasFrame, options: .alignAllEdgesNearest)
            let geometry = PageGeometry(frame: rotation == 0 ? canvasFrame : alignedFrame, pageBounds: pBounds, zoom: viewModel.effectiveZoom, rotation: rotation)
            let cgContext = NSGraphicsContext.current?.cgContext
            cgContext?.saveGState()
            defer { cgContext?.restoreGState() }
            if geometry.isRotated {
                cgContext?.concatenate(geometry.viewRotation)
            }
            let pFrame = geometry.layoutFrame

            // 2. Rendered Page Bitmap — inverted in dark mode (see displayImage) so pages read as
            // light-on-dark rather than a bright rectangle breaking up an otherwise dark app.
            if let image = viewModel.renderedPages[pageIdx] {
                let displayImg = displayImage(for: pageIdx, source: image)
                displayImg.draw(in: geometry.isRotated ? pFrame : alignedFrame)
                drawPageDetail(pageIdx, geometry: geometry)
            }
            if !viewModel.hasCurrentRender(of: pageIdx) && !viewModel.isLiveZooming {
                // Render on demand, or again after a zoom; the old bitmap stays meanwhile.
                Task { @MainActor [weak self] in
                    guard let viewModel = self?.liveViewModel else { return }
                    await viewModel.renderPage(pageIdx)
                    viewModel.loadPageMetadata(pageIdx)
                    self?.setNeedsDisplay(canvasFrame)
                    self?.syncFormControls()
                }
            }
            
            // Mask underlying PDF appearance behind active form widgets so underlying static text never bleeds through
            if viewModel.pageFormWidgets[pageIdx] == nil {
                // Defer loading metadata to avoid mutating published state during draw(_:).
                Task { @MainActor [weak self] in
                    self?.liveViewModel?.loadPageMetadata(pageIdx)
                    self?.setNeedsDisplay(canvasFrame)
                }
            }
            if let widgets = viewModel.pageFormWidgets[pageIdx] {
                for widget in widgets {
                    // Signature fields are not masked so stamped signature remains visible.
                    guard widget.type != .signature else { continue }
                    // Push buttons keep the PDF's own appearance; their control is transparent.
                    guard !(widget.type == .button && widget.isPushButton) else { continue }
                    let maskRect = widgetScreenFrame(for: widget, pageFrame: pFrame, pageBounds: pBounds)
                    // Match mask color to page background color.
                    pageFillColor.setFill()
                    maskRect.fill()
                }
            }

            // Annotations added in the current session are drawn over the rendered bitmap.
            do {

                // 2.5 Page Annotations (Highlights, Underlines, Strikeouts, Freehand Ink, FreeText)
                if case let annots = viewModel.shownAnnotations(onPage: pageIdx), !annots.isEmpty {
                    for annot in annots {
                        if annot.isFromFile {
                            drawFileAnnotation(annot, pFrame: pFrame, pBounds: pBounds)
                            continue
                        }
                        switch annot.type {
                        case .highlight:
                            annot.color.highlightFillColor.setFill()
                            for quad in annot.quads {
                                let r = quad.boundingRect
                                let qx = pFrame.minX + (r.minX - pBounds.minX) * viewModel.effectiveZoom
                                let qy = pFrame.minY + (r.minY - pBounds.minY) * viewModel.effectiveZoom
                                let qw = max(r.width * viewModel.effectiveZoom, 2)
                                let qh = max(r.height * viewModel.effectiveZoom, 4)
                                let quadRect = NSRect(x: qx, y: qy, width: qw, height: qh)
                                let path = NSBezierPath(roundedRect: quadRect, xRadius: 2, yRadius: 2)
                                path.fill()
                            }
                        case .underline:
                            annot.color.nsColor.setStroke()
                            let lineWidth = max(1.5 * viewModel.effectiveZoom, 1.5)
                            for quad in annot.quads {
                                let r = quad.boundingRect
                                let qx = pFrame.minX + (r.minX - pBounds.minX) * viewModel.effectiveZoom
                                let qy = pFrame.minY + (r.minY - pBounds.minY) * viewModel.effectiveZoom
                                let qw = max(r.width * viewModel.effectiveZoom, 2)
                                let qh = max(r.height * viewModel.effectiveZoom, 4)
                                let yPos = qy + qh - lineWidth * 0.5
                                let path = NSBezierPath()
                                path.lineWidth = lineWidth
                                path.move(to: NSPoint(x: qx, y: yPos))
                                path.line(to: NSPoint(x: qx + qw, y: yPos))
                                path.stroke()
                            }
                        case .strikeout:
                            annot.color.nsColor.setStroke()
                            let lineWidth = max(1.5 * viewModel.effectiveZoom, 1.5)
                            for quad in annot.quads {
                                let r = quad.boundingRect
                                let qx = pFrame.minX + (r.minX - pBounds.minX) * viewModel.effectiveZoom
                                let qy = pFrame.minY + (r.minY - pBounds.minY) * viewModel.effectiveZoom
                                let qw = max(r.width * viewModel.effectiveZoom, 2)
                                let qh = max(r.height * viewModel.effectiveZoom, 4)
                                let yPos = qy + qh * 0.55
                                let path = NSBezierPath()
                                path.lineWidth = lineWidth
                                path.move(to: NSPoint(x: qx, y: yPos))
                                path.line(to: NSPoint(x: qx + qw, y: yPos))
                                path.stroke()
                            }
                        case .ink:
                            guard !annot.inkPoints.isEmpty else { continue }
                            // Where a drag in progress carries it.
                            let inkOffset = dragAffecting(annot)?.currentDelta ?? .zero
                            let inkPoints = annot.inkPoints.map { CGPoint(x: $0.x + inkOffset.width, y: $0.y + inkOffset.height) }
                            annot.color.nsColor.setStroke()
                            annot.color.nsColor.setFill()
                            let lineWidth = max(annot.strokeWidth * viewModel.effectiveZoom, 1.0)
                            if inkPoints.count == 1 {
                                let p = inkPoints[0]
                                let cx = pFrame.minX + (p.x - pBounds.minX) * viewModel.effectiveZoom
                                let cy = pFrame.minY + (p.y - pBounds.minY) * viewModel.effectiveZoom
                                let dotRect = NSRect(x: cx - lineWidth * 0.5, y: cy - lineWidth * 0.5, width: lineWidth, height: lineWidth)
                                let dot = NSBezierPath(ovalIn: dotRect)
                                dot.fill()
                            } else {
                                let path = NSBezierPath()
                                path.lineWidth = lineWidth
                                path.lineCapStyle = .round
                                path.lineJoinStyle = .round
                                let first = inkPoints[0]
                                path.move(to: NSPoint(
                                    x: pFrame.minX + (first.x - pBounds.minX) * viewModel.effectiveZoom,
                                    y: pFrame.minY + (first.y - pBounds.minY) * viewModel.effectiveZoom
                                ))
                                for pt in inkPoints.dropFirst() {
                                    path.line(to: NSPoint(
                                        x: pFrame.minX + (pt.x - pBounds.minX) * viewModel.effectiveZoom,
                                        y: pFrame.minY + (pt.y - pBounds.minY) * viewModel.effectiveZoom
                                    ))
                                }
                                path.stroke()
                            }
                            if isAnnotationSelected(annot.id) {
                                let box = CGRect(enclosing: inkPoints).insetBy(dx: -annot.strokeWidth / 2 - 2, dy: -annot.strokeWidth / 2 - 2)
                                let selRect = NSRect(
                                    x: pFrame.minX + (box.minX - pBounds.minX) * viewModel.effectiveZoom,
                                    y: pFrame.minY + (box.minY - pBounds.minY) * viewModel.effectiveZoom,
                                    width: box.width * viewModel.effectiveZoom, height: box.height * viewModel.effectiveZoom
                                ).insetBy(dx: -2, dy: -2)
                                let selPath = NSBezierPath(roundedRect: selRect, xRadius: 3, yRadius: 3)
                                selPath.lineWidth = 1.5
                                NSColor.controlAccentColor.setStroke()
                                selPath.stroke()
                            }
                        case .freeText:
                            guard let initialRect = annot.rect, !annot.text.isEmpty else { continue }
                            var rect = initialRect
                            if let drag = dragAffecting(annot) {
                                rect = updatedRect(from: initialRect, part: drag.part, delta: drag.currentDelta)
                            }

                            let rx = pFrame.minX + (rect.minX - pBounds.minX) * viewModel.effectiveZoom
                            let ry = pFrame.minY + (rect.minY - pBounds.minY) * viewModel.effectiveZoom
                            let rw = max(rect.width * viewModel.effectiveZoom, 24)
                            let rh = max(rect.height * viewModel.effectiveZoom, 16)
                            var boxRect = NSRect(x: rx, y: ry, width: rw, height: rh)
                            if activeEditingAnnotation?.id == annot.id, let tf = activeInlineTextField {
                                boxRect = layoutRect(of: tf)
                            }

                            let effectiveColor = (activeEditingAnnotation?.id == annot.id ? viewModel.selectedAnnotationColor : annot.color)

                            // If currently editing this annotation inline, draw dashed focus outline
                            if activeEditingAnnotation?.id == annot.id {
                                let borderPath = NSBezierPath(roundedRect: boxRect, xRadius: 2, yRadius: 2)
                                borderPath.lineWidth = 1.0
                                let dashes: [CGFloat] = [3.0, 3.0]
                                borderPath.setLineDash(dashes, count: 2, phase: 0)
                                effectiveColor.nsColor.setStroke()
                                borderPath.stroke()
                                continue
                            }

                            // If selected (and not inline editing), draw selection outline and corner handles
                            if isAnnotationSelected(annot.id) {
                                let selRect = boxRect.insetBy(dx: -2.5, dy: -2.5)
                                let selPath = NSBezierPath(roundedRect: selRect, xRadius: 3, yRadius: 3)
                                selPath.lineWidth = 1.5
                                NSColor.controlAccentColor.setStroke()
                                selPath.stroke()

                                let handleSize: CGFloat = 5.0
                                let corners = [
                                    NSPoint(x: selRect.minX - handleSize/2, y: selRect.minY - handleSize/2),
                                    NSPoint(x: selRect.maxX - handleSize/2, y: selRect.minY - handleSize/2),
                                    NSPoint(x: selRect.minX - handleSize/2, y: selRect.maxY - handleSize/2),
                                    NSPoint(x: selRect.maxX - handleSize/2, y: selRect.maxY - handleSize/2)
                                ]
                                for pt in corners {
                                    let hPath = NSBezierPath(roundedRect: NSRect(origin: pt, size: CGSize(width: handleSize, height: handleSize)), xRadius: 1, yRadius: 1)
                                    NSColor.white.setFill()
                                    hPath.fill()
                                    NSColor.controlAccentColor.setStroke()
                                    hPath.lineWidth = 1.0
                                    hPath.stroke()
                                }
                            }

                            let fSize = max((annot.fontSize ?? 13.0) * viewModel.effectiveZoom, 8.0)
                            let font = NSFont.systemFont(ofSize: fSize)
                            let attrs: [NSAttributedString.Key: Any] = [
                                .font: font,
                                .foregroundColor: effectiveColor.nsColor
                            ]
                            let str = annot.text as NSString
                            str.draw(with: boxRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)

                        case .note, .cloud, .square, .circle, .line, .polygon, .polyline:
                            guard let initialRect = annot.rect else { continue }
                            var rect = initialRect
                            if let drag = dragAffecting(annot) {
                                rect = updatedRect(from: initialRect, part: drag.part, delta: drag.currentDelta)
                            }
                            let boxRect = NSRect(
                                x: pFrame.minX + (rect.minX - pBounds.minX) * viewModel.effectiveZoom,
                                y: pFrame.minY + (rect.minY - pBounds.minY) * viewModel.effectiveZoom,
                                width: rect.width * viewModel.effectiveZoom,
                                height: rect.height * viewModel.effectiveZoom
                            )
                            var pagePoints = annot.inkPoints(fittedTo: rect)
                            if annot.type == .line, let drag = dragAffecting(annot) {
                                pagePoints = updatedLineEnds(of: annot, part: drag.part, delta: drag.currentDelta)
                            }
                            let ends = pagePoints.map { canvasPoint(for: $0, pFrame: pFrame, pBounds: pBounds) }
                            switch annot.type {
                            case .note:
                                drawNoteIcon(in: boxRect, color: annot.color.nsColor)
                            case .cloud where ends.count >= 3:
                                drawRevisionCloud(around: ends, intensity: annot.cloudIntensity ?? PDFCloudArcSize.medium.rawValue, color: annot.color.nsColor)
                            case .cloud:
                                drawRevisionCloud(in: boxRect, intensity: annot.cloudIntensity ?? PDFCloudArcSize.medium.rawValue, color: annot.color.nsColor)
                            default:
                                drawShape(annot.type, box: boxRect, ends: ends, strokeWidth: annot.strokeWidth, ending: annot.lineEnding, color: annot.color.nsColor)
                            }
                            if isAnnotationSelected(annot.id) {
                                if annot.type == .line {
                                    drawEndHandles(ends)
                                } else {
                                    let selRect = boxRect.insetBy(dx: -2.5, dy: -2.5)
                                    let selPath = NSBezierPath(roundedRect: selRect, xRadius: 3, yRadius: 3)
                                    selPath.lineWidth = 1.5
                                    NSColor.controlAccentColor.setStroke()
                                    selPath.stroke()
                                    if annot.type != .note {
                                        drawResizeHandles(around: selRect)
                                    }
                                }
                            }

                        case .callout:
                            guard let initialRect = annot.rect, let initialTargetPt = annot.targetPoint, let initialKneePt = annot.kneePoint else { continue }
                            var rect = initialRect
                            var targetPt = initialTargetPt
                            var kneePt = initialKneePt

                            if let drag = dragAffecting(annot) {
                                let dx = drag.currentDelta.width
                                let dy = drag.currentDelta.height
                                switch drag.part {
                                case .calloutTargetPoint:
                                    targetPt = CGPoint(x: targetPt.x + dx, y: targetPt.y + dy)
                                case .calloutKneePoint:
                                    kneePt = CGPoint(x: kneePt.x + dx, y: kneePt.y + dy)
                                case .calloutTextBox:
                                    rect = rect.offsetBy(dx: dx, dy: dy)
                                    kneePt = CGPoint(x: kneePt.x + dx, y: kneePt.y + dy)
                                case .resizeTopLeft, .resizeTopRight, .resizeBottomLeft, .resizeBottomRight:
                                    rect = updatedRect(from: initialRect, part: drag.part, delta: drag.currentDelta)
                                case .entireAnnotation:
                                    targetPt = CGPoint(x: targetPt.x + dx, y: targetPt.y + dy)
                                    kneePt = CGPoint(x: kneePt.x + dx, y: kneePt.y + dy)
                                    rect = rect.offsetBy(dx: dx, dy: dy)
                                case .lineStart, .lineEnd, .measurementPoint, .measurementLeader:
                                    break
                                }
                            }

                            let rx = pFrame.minX + (rect.minX - pBounds.minX) * viewModel.effectiveZoom
                            let ry = pFrame.minY + (rect.minY - pBounds.minY) * viewModel.effectiveZoom
                            let rw = max(rect.width * viewModel.effectiveZoom, 24)
                            let rh = max(rect.height * viewModel.effectiveZoom, 16)
                            var boxRect = NSRect(x: rx, y: ry, width: rw, height: rh)
                            if activeEditingAnnotation?.id == annot.id, let tf = activeInlineTextField {
                                boxRect = layoutRect(of: tf)
                            }

                            let tx = pFrame.minX + (targetPt.x - pBounds.minX) * viewModel.effectiveZoom
                            let ty = pFrame.minY + (targetPt.y - pBounds.minY) * viewModel.effectiveZoom
                            let kx = pFrame.minX + (kneePt.x - pBounds.minX) * viewModel.effectiveZoom
                            let ky = pFrame.minY + (kneePt.y - pBounds.minY) * viewModel.effectiveZoom

                            let attachX = (kx <= boxRect.minX) ? boxRect.minX : ((kx >= boxRect.maxX) ? boxRect.maxX : kx)
                            let attachY = (ky <= boxRect.minY) ? boxRect.minY : ((ky >= boxRect.maxY) ? boxRect.maxY : boxRect.midY)

                            let effectiveColor = (activeEditingAnnotation?.id == annot.id ? viewModel.selectedAnnotationColor : annot.color)

                            // Leader line
                            let leaderPath = NSBezierPath()
                            leaderPath.lineWidth = 1.5
                            effectiveColor.nsColor.setStroke()
                            leaderPath.move(to: NSPoint(x: tx, y: ty))
                            leaderPath.line(to: NSPoint(x: kx, y: ky))
                            leaderPath.line(to: NSPoint(x: attachX, y: attachY))
                            leaderPath.stroke()

                            // Line ending at target point
                            if let ending = (annot.lineEnding ?? .closedArrow).path(tip: NSPoint(x: tx, y: ty), dx: kx - tx, dy: ky - ty) {
                                if ending.filled {
                                    effectiveColor.nsColor.setFill()
                                    ending.path.fill()
                                } else {
                                    effectiveColor.nsColor.setStroke()
                                    ending.path.stroke()
                                }
                            }

                            // Text box background and border
                            let borderPath = NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3)
                            (isDarkMode ? NSColor.windowBackgroundColor : NSColor.white).setFill()
                            borderPath.fill()
                            borderPath.lineWidth = 1.0
                            effectiveColor.nsColor.setStroke()
                            borderPath.stroke()

                            // If selected (and not inline editing), draw selection border and target/knee/corner handles
                            if isAnnotationSelected(annot.id) && activeEditingAnnotation == nil {
                                let selRect = boxRect.insetBy(dx: -2.5, dy: -2.5)
                                let selPath = NSBezierPath(roundedRect: selRect, xRadius: 4, yRadius: 4)
                                selPath.lineWidth = 1.5
                                NSColor.controlAccentColor.setStroke()
                                selPath.stroke()

                                // Handles on target arrow and knee elbow
                                let handles = [NSPoint(x: tx, y: ty), NSPoint(x: kx, y: ky)]
                                for pt in handles {
                                    let hPath = NSBezierPath(ovalIn: NSRect(x: pt.x - 3.5, y: pt.y - 3.5, width: 7, height: 7))
                                    NSColor.white.setFill()
                                    hPath.fill()
                                    NSColor.controlAccentColor.setStroke()
                                    hPath.lineWidth = 1.5
                                    hPath.stroke()
                                }

                                // Corner handles on text box
                                let handleSize: CGFloat = 5.0
                                let corners = [
                                    NSPoint(x: selRect.minX - handleSize/2, y: selRect.minY - handleSize/2),
                                    NSPoint(x: selRect.maxX - handleSize/2, y: selRect.minY - handleSize/2),
                                    NSPoint(x: selRect.minX - handleSize/2, y: selRect.maxY - handleSize/2),
                                    NSPoint(x: selRect.maxX - handleSize/2, y: selRect.maxY - handleSize/2)
                                ]
                                for pt in corners {
                                    let hPath = NSBezierPath(roundedRect: NSRect(origin: pt, size: CGSize(width: handleSize, height: handleSize)), xRadius: 1, yRadius: 1)
                                    NSColor.white.setFill()
                                    hPath.fill()
                                    NSColor.controlAccentColor.setStroke()
                                    hPath.lineWidth = 1.0
                                    hPath.stroke()
                                }
                            }

                            if activeEditingAnnotation?.id == annot.id {
                                continue
                            }

                            if !annot.text.isEmpty {
                                let fSize = max((annot.fontSize ?? 11.0) * viewModel.effectiveZoom, 8.0)
                                let font = NSFont.systemFont(ofSize: fSize)
                                let attrs: [NSAttributedString.Key: Any] = [
                                    .font: font,
                                    .foregroundColor: effectiveColor.nsColor
                                ]
                                let textInset = boxRect.insetBy(dx: 4, dy: 3)
                                let str = annot.text as NSString
                                str.draw(with: textInset, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
                            }

                        case .stamp:
                            guard let initialRect = annot.rect, let data = annot.stampImageData, let img = NSImage(data: data) else { continue }
                            var rect = initialRect
                            if let drag = dragAffecting(annot) {
                                rect = updatedRect(from: initialRect, part: drag.part, delta: drag.currentDelta)
                            }

                            let rx = pFrame.minX + (rect.minX - pBounds.minX) * viewModel.effectiveZoom
                            let ry = pFrame.minY + (rect.minY - pBounds.minY) * viewModel.effectiveZoom
                            let rw = max(rect.width * viewModel.effectiveZoom, 20)
                            let rh = max(rect.height * viewModel.effectiveZoom, 10)
                            let boxRect = NSRect(x: rx, y: ry, width: rw, height: rh)

                            img.draw(in: boxRect)

                            // If selected, draw selection outline and corner handles
                            if isAnnotationSelected(annot.id) {
                                let selRect = boxRect.insetBy(dx: -2.5, dy: -2.5)
                                let selPath = NSBezierPath(roundedRect: selRect, xRadius: 3, yRadius: 3)
                                selPath.lineWidth = 1.5
                                NSColor.controlAccentColor.setStroke()
                                selPath.stroke()

                                let handleSize: CGFloat = 6.0
                                let corners = [
                                    NSPoint(x: selRect.minX - handleSize/2, y: selRect.minY - handleSize/2),
                                    NSPoint(x: selRect.maxX - handleSize/2, y: selRect.minY - handleSize/2),
                                    NSPoint(x: selRect.minX - handleSize/2, y: selRect.maxY - handleSize/2),
                                    NSPoint(x: selRect.maxX - handleSize/2, y: selRect.maxY - handleSize/2)
                                ]
                                for pt in corners {
                                    let hPath = NSBezierPath(roundedRect: NSRect(origin: pt, size: CGSize(width: handleSize, height: handleSize)), xRadius: 1, yRadius: 1)
                                    NSColor.white.setFill()
                                    hPath.fill()
                                    NSColor.controlAccentColor.setStroke()
                                    hPath.lineWidth = 1.0
                                    hPath.stroke()
                                }
                            }

                        case .measureLength, .measurePerimeter, .measureArea, .measureAngle, .measureCount:
                            // As a drag in progress leaves it, with its value worked out again.
                            let shown = draggedMeasurement(annot)
                            let isSelected = isAnnotationSelected(annot.id)
                            switch annot.type {
                            case .measureLength: drawMeasureLength(annot: shown, pFrame: pFrame, pBounds: pBounds, isSelected: isSelected)
                            case .measurePerimeter: drawMeasurePerimeter(annot: shown, pFrame: pFrame, pBounds: pBounds, isSelected: isSelected)
                            case .measureArea: drawMeasureArea(annot: shown, pFrame: pFrame, pBounds: pBounds, isSelected: isSelected)
                            case .measureCount: drawCountMarker(annot: shown, pFrame: pFrame, pBounds: pBounds, isSelected: isSelected)
                            default: drawMeasureAngle(annot: shown, pFrame: pFrame, pBounds: pBounds, isSelected: isSelected)
                            }
                            if isSelected {
                                drawEndHandles(measurementHandles(of: shown).map { canvasPoint(for: $0, pFrame: pFrame, pBounds: pBounds) })
                            }
                        case .other:
                            break
                        }
                    }
                }

                // An annotation just chosen in the Comments sidebar
                if let outline = revealedAnnotationOutline, outline.pageIndex == pageIdx {
                    let origin = canvasPoint(for: outline.rect.origin, pFrame: pFrame, pBounds: pBounds)
                    let box = NSRect(origin: origin, size: CGSize(width: outline.rect.width * viewModel.effectiveZoom, height: outline.rect.height * viewModel.effectiveZoom))
                        .insetBy(dx: -4, dy: -4)
                    let ring = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
                    ring.lineWidth = 2.5
                    NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
                    ring.stroke()
                }
            }

            // 2.51 The grid and the guides
            drawGridAndGuides(onPage: pageIdx)

            // 2.52 What the Inspector shows, from the last click: the glyph and image there
            if let inspected = viewModel.inspectedContent, inspected.pageIndex == pageIdx {
                for rect in [inspected.text?.rect, inspected.image?.rect].compactMap({ $0 }) {
                    let a = canvasPoint(for: CGPoint(x: rect.minX, y: rect.minY), pFrame: pFrame, pBounds: pBounds)
                    let b = canvasPoint(for: CGPoint(x: rect.maxX, y: rect.maxY), pFrame: pFrame, pBounds: pBounds)
                    let box = NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)).insetBy(dx: -1.5, dy: -1.5)
                    let outline = NSBezierPath(rect: box)
                    outline.lineWidth = 1.5
                    outline.setLineDash([4, 3], count: 2, phase: 0)
                    NSColor.controlAccentColor.setStroke()
                    outline.stroke()
                }
            }

            // 2.55 The line a SyncTeX forward search found, fading out
            if let highlight = syncTeXHighlight, highlight.pageIndex == pageIdx {
                let opacity = Self.syncTeXHighlightOpacity(at: Date().timeIntervalSince(highlight.shownAt))
                if opacity > 0 {
                    for rect in highlight.rects {
                        let path = highlightPath(for: PDFQuad(rect: rect.insetBy(dx: -2, dy: -1.5)), minSize: CGSize(width: 6, height: 8), pFrame: pFrame, pBounds: pBounds)
                        NSColor.systemRed.withAlphaComponent(0.22 * opacity).setFill()
                        path.fill()
                        NSColor.systemRed.withAlphaComponent(0.8 * opacity).setStroke()
                        path.lineWidth = 1.5
                        path.stroke()
                    }
                }
            }

            // 2.6 Live Drawing Stroke in Progress
            if currentDrawingPageIndex == pageIdx && !currentDrawingPoints.isEmpty {
                viewModel.selectedAnnotationColor.nsColor.setStroke()
                viewModel.selectedAnnotationColor.nsColor.setFill()
                let lineWidth = max(viewModel.drawStrokeWidth * viewModel.effectiveZoom, 1.0)
                if currentDrawingPoints.count == 1 {
                    let p = currentDrawingPoints[0]
                    let cx = pFrame.minX + (p.x - pBounds.minX) * viewModel.effectiveZoom
                    let cy = pFrame.minY + (p.y - pBounds.minY) * viewModel.effectiveZoom
                    let dotRect = NSRect(x: cx - lineWidth * 0.5, y: cy - lineWidth * 0.5, width: lineWidth, height: lineWidth)
                    let dot = NSBezierPath(ovalIn: dotRect)
                    dot.fill()
                } else {
                    let path = NSBezierPath()
                    path.lineWidth = lineWidth
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    let first = currentDrawingPoints[0]
                    path.move(to: NSPoint(
                        x: pFrame.minX + (first.x - pBounds.minX) * viewModel.effectiveZoom,
                        y: pFrame.minY + (first.y - pBounds.minY) * viewModel.effectiveZoom
                    ))
                    for pt in currentDrawingPoints.dropFirst() {
                        path.line(to: NSPoint(
                            x: pFrame.minX + (pt.x - pBounds.minX) * viewModel.effectiveZoom,
                            y: pFrame.minY + (pt.y - pBounds.minY) * viewModel.effectiveZoom
                        ))
                    }
                    path.stroke()
                }
            }

            // Live shape dragging in progress
            if currentShapePage == pageIdx, let start = currentShapeStart, let end = currentShapeEnd {
                let p1 = canvasPoint(for: start, pFrame: pFrame, pBounds: pBounds)
                let p2 = canvasPoint(for: end, pFrame: pFrame, pBounds: pBounds)
                let box = NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
                let color = viewModel.selectedAnnotationColor.nsColor
                switch viewModel.selectedShape {
                case .cloud:
                    // The cloud it will make, over a faint trail of the path dragged.
                    let trail = NSBezierPath()
                    for (i, point) in currentShapePath.map({ canvasPoint(for: $0, pFrame: pFrame, pBounds: pBounds) }).enumerated() {
                        if i == 0 { trail.move(to: point) } else { trail.line(to: point) }
                    }
                    trail.lineWidth = 1
                    trail.setLineDash([3, 3], count: 2, phase: 0)
                    color.withAlphaComponent(0.5).setStroke()
                    trail.stroke()
                    let outline = CloudOutline.outline(for: currentShapePath).map { canvasPoint(for: $0, pFrame: pFrame, pBounds: pBounds) }
                    drawRevisionCloud(around: outline, intensity: viewModel.selectedCloudArcSize.rawValue, color: color)
                case .rectangle:
                    drawShape(.square, box: box, ends: [], strokeWidth: viewModel.drawStrokeWidth, ending: nil, color: color)
                case .oval:
                    drawShape(.circle, box: box, ends: [], strokeWidth: viewModel.drawStrokeWidth, ending: nil, color: color)
                case .line:
                    drawShape(.line, box: box, ends: [p1, p2], strokeWidth: viewModel.drawStrokeWidth, ending: viewModel.selectedShapeLineEnding, color: color)
                case .polygon, .polyline:
                    break
                }
            }

            // A polygon or polyline being clicked out, to where the pointer is.
            if currentPolyPage == pageIdx, !currentPolyPoints.isEmpty {
                var points = currentPolyPoints
                if let candidate = currentPolyCandidate { points.append(candidate) }
                let ends = points.map { canvasPoint(for: $0, pFrame: pFrame, pBounds: pBounds) }
                let closing = viewModel.selectedShape == .polygon && points.count >= 3
                drawShape(closing ? .polygon : .polyline, box: .zero, ends: ends, strokeWidth: viewModel.drawStrokeWidth,
                          ending: viewModel.selectedShape == .polyline ? viewModel.selectedShapeLineEnding : nil,
                          color: viewModel.selectedAnnotationColor.nsColor)
                // The corners clicked so far.
                NSColor.controlAccentColor.setFill()
                for point in ends.dropLast(currentPolyCandidate == nil ? 0 : 1) {
                    NSBezierPath(ovalIn: NSRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)).fill()
                }
            }

            // 2.7 Live Redaction Dragging in Progress
            if currentRedactionPage == pageIdx,
               let start = currentRedactionStart,
               let end = currentRedactionEnd {
                let p1 = CGPoint(
                    x: pFrame.minX + (start.x - pBounds.minX) * viewModel.effectiveZoom,
                    y: pFrame.minY + (start.y - pBounds.minY) * viewModel.effectiveZoom
                )
                let p2 = CGPoint(
                    x: pFrame.minX + (end.x - pBounds.minX) * viewModel.effectiveZoom,
                    y: pFrame.minY + (end.y - pBounds.minY) * viewModel.effectiveZoom
                )
                let liveRect = NSRect(
                    x: min(p1.x, p2.x),
                    y: min(p1.y, p2.y),
                    width: abs(p2.x - p1.x),
                    height: abs(p2.y - p1.y)
                )
                if viewModel.redactionColor == .white {
                    NSColor.white.withAlphaComponent(0.5).setFill()
                    liveRect.fill()

                    let border = NSBezierPath(rect: liveRect)
                    border.lineWidth = 1.5
                    let dashes: [CGFloat] = [4.0, 3.0]
                    border.setLineDash(dashes, count: 2, phase: 0)
                    NSColor.systemOrange.setStroke()
                    border.stroke()
                } else {
                    NSColor.black.withAlphaComponent(0.4).setFill()
                    liveRect.fill()

                    let border = NSBezierPath(rect: liveRect)
                    border.lineWidth = 1.5
                    let dashes: [CGFloat] = [4.0, 3.0]
                    border.setLineDash(dashes, count: 2, phase: 0)
                    NSColor.systemRed.setStroke()
                    border.stroke()
                }
            }

            // 2.8 Live Callout Dragging in Progress
            if currentCalloutPage == pageIdx,
               let start = currentCalloutStart,
               let end = currentCalloutEnd {
                let tx = pFrame.minX + (start.x - pBounds.minX) * viewModel.effectiveZoom
                let ty = pFrame.minY + (start.y - pBounds.minY) * viewModel.effectiveZoom
                let ex = pFrame.minX + (end.x - pBounds.minX) * viewModel.effectiveZoom
                let ey = pFrame.minY + (end.y - pBounds.minY) * viewModel.effectiveZoom
                let kx = ex
                let ky = ty

                let liveLeader = NSBezierPath()
                liveLeader.lineWidth = 1.5
                let dashes: [CGFloat] = [3.0, 2.0]
                liveLeader.setLineDash(dashes, count: 2, phase: 0)
                viewModel.selectedAnnotationColor.nsColor.setStroke()
                liveLeader.move(to: NSPoint(x: tx, y: ty))
                liveLeader.line(to: NSPoint(x: kx, y: ky))
                liveLeader.line(to: NSPoint(x: ex, y: ey))
                liveLeader.stroke()

                let previewBox = NSRect(x: ex, y: ey - 10, width: 100, height: 22)
                let boxBorder = NSBezierPath(roundedRect: previewBox, xRadius: 2, yRadius: 2)
                (isDarkMode ? NSColor.windowBackgroundColor : NSColor.white).withAlphaComponent(0.8).setFill()
                boxBorder.fill()
                viewModel.selectedAnnotationColor.nsColor.setStroke()
                boxBorder.stroke()
            }

            // Where a new signature field goes, while placing one: the box being dragged, or
            // one of the usual size under the pointer.
            let draggedSignatureBox: CGRect? = {
                guard viewModel.canvasMode == .placeSignatureField, currentMeasurePage == pageIdx,
                      let start = currentMeasurePoints.first, let end = currentMeasureCandidatePoint,
                      hypot(end.x - start.x, end.y - start.y) > 8 else { return nil }
                return CGRect(enclosing: [start, end])
            }()
            if viewModel.canvasMode == .placeSignatureField,
               let rect = draggedSignatureBox ?? currentHoverCanvasPoint.flatMap({ hoverCanvasPt -> CGRect? in
                   let hoverPt = geometry.layoutPoint(forCanvasPoint: hoverCanvasPt)
                   guard pFrame.contains(hoverPt) else { return nil }
                   let zoom = viewModel.effectiveZoom
                   let pagePoint = CGPoint(x: pBounds.minX + (hoverPt.x - pFrame.minX) / zoom, y: pBounds.minY + (hoverPt.y - pFrame.minY) / zoom)
                   return viewModel.certificateSignatureRect(page: pageIdx, at: pagePoint)
               }) {
                let zoom = viewModel.effectiveZoom
                do {
                    let box = NSRect(x: pFrame.minX + (rect.minX - pBounds.minX) * zoom, y: pFrame.minY + (rect.minY - pBounds.minY) * zoom,
                                     width: rect.width * zoom, height: rect.height * zoom)
                    let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
                    NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
                    path.fill()
                    path.lineWidth = 1
                    path.setLineDash([3, 3], count: 2, phase: 0)
                    NSColor.controlAccentColor.setStroke()
                    path.stroke()
                    let label = NSAttributedString(string: "Sign Here", attributes: [
                        .font: NSFont.systemFont(ofSize: max(9, 12 * zoom)), .foregroundColor: NSColor.controlAccentColor,
                    ])
                    let size = label.size()
                    label.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
                }
            }

            // 2.9 Live Ghost Stamp Preview in Progress
            if viewModel.canvasMode == .stamp,
               let data = viewModel.pendingSignatureData,
               let img = NSImage(data: data),
               let hoverCanvasPt = currentHoverCanvasPoint,
               case let hoverPt = geometry.layoutPoint(forCanvasPoint: hoverCanvasPt),
               pFrame.contains(hoverPt) {
                let imgSize = img.size
                let stampW: CGFloat = 140 * viewModel.effectiveZoom
                let stampH: CGFloat = stampW * (imgSize.height / max(imgSize.width, 1))
                let ghostRect = NSRect(
                    x: max(pFrame.minX, min(hoverPt.x - stampW / 2, pFrame.maxX - stampW)),
                    y: max(pFrame.minY, min(hoverPt.y - stampH / 2, pFrame.maxY - stampH)),
                    width: stampW,
                    height: stampH
                )
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.setAlpha(0.6)
                img.draw(in: ghostRect)
                NSGraphicsContext.restoreGraphicsState()
                let ghostPath = NSBezierPath(roundedRect: ghostRect, xRadius: 3, yRadius: 3)
                ghostPath.lineWidth = 1.0
                let dashes: [CGFloat] = [3.0, 3.0]
                ghostPath.setLineDash(dashes, count: 2, phase: 0)
                NSColor.controlAccentColor.setStroke()
                ghostPath.stroke()
            }

            // What a click would pick up, under the pointer (Select mode).
            if let hover = hoverOutline, hover.pageIndex == pageIdx, let geometry = pageGeometry(for: pageIdx) {
                let box = geometry.canvasRect(forPageRect: hover.rect).insetBy(dx: -3, dy: -3)
                let outline = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
                outline.lineWidth = 1
                outline.setLineDash([4, 3], count: 2, phase: 0)
                NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
                outline.stroke()
            }

            // A rectangle, circle or arc being drawn: its outline and value.
            if currentMeasurePage == pageIdx, let shape = shapeInProgress() {
                let color = viewModel.measurementColor.nsColor
                let outline = shape.outline.map { canvasPoint(for: $0, pFrame: pFrame, pBounds: pBounds) }
                let path = NSBezierPath()
                path.lineWidth = max(viewModel.measurementStrokeWidth * viewModel.effectiveZoom, 1.5)
                if let first = outline.first {
                    path.move(to: first)
                    outline.dropFirst().forEach { path.line(to: $0) }
                }
                if shape.kind != .arc {
                    path.close()
                    color.withAlphaComponent(0.18).setFill()
                    path.fill()
                }
                color.setStroke()
                path.stroke()
                for pt in shape.points.dropLast() {
                    let sp = canvasPoint(for: pt, pFrame: pFrame, pBounds: pBounds)
                    let dot = NSBezierPath(ovalIn: NSRect(x: sp.x - 3.5, y: sp.y - 3.5, width: 7, height: 7))
                    NSColor.white.setFill()
                    dot.fill()
                    color.setStroke()
                    dot.stroke()
                }
                if let candidate = currentMeasureCandidatePoint {
                    let sCand = canvasPoint(for: candidate, pFrame: pFrame, pBounds: pBounds)
                    drawMeasurementTextPill(text: shape.label(scale: viewModel.scaleConfig(for: pageIdx)),
                                            at: NSPoint(x: sCand.x + 14, y: sCand.y + 14), color: color, isSelected: false)
                }
            } else if currentMeasurePage == pageIdx, !currentMeasurePoints.isEmpty || currentMeasureCandidatePoint != nil {
            // 2.9 Live Measurement Drafting & Snapping in Progress
                let color = viewModel.measurementColor.nsColor
                let pageScale = viewModel.scaleConfig(for: pageIdx)

                // 1. Draw committed points in path
                if currentMeasurePoints.count > 1 {
                    let path = NSBezierPath()
                    path.lineWidth = max(viewModel.measurementStrokeWidth * viewModel.effectiveZoom, 1.5)
                    let p0 = canvasPoint(for: currentMeasurePoints[0], pFrame: pFrame, pBounds: pBounds)
                    path.move(to: p0)
                    for pt in currentMeasurePoints.dropFirst() {
                        path.line(to: canvasPoint(for: pt, pFrame: pFrame, pBounds: pBounds))
                    }
                    color.setStroke()
                    path.stroke()
                }

                for pt in currentMeasurePoints {
                    let sp = canvasPoint(for: pt, pFrame: pFrame, pBounds: pBounds)
                    let dotRect = NSRect(x: sp.x - 3.5, y: sp.y - 3.5, width: 7, height: 7)
                    NSColor.white.setFill()
                    NSBezierPath(ovalIn: dotRect).fill()
                    color.setStroke()
                    let b = NSBezierPath(ovalIn: dotRect)
                    b.lineWidth = 1.5
                    b.stroke()
                }

                // 2. Rubber-band line to candidate point
                if let candidate = currentMeasureCandidatePoint, let lastPt = currentMeasurePoints.last {
                    let sLast = canvasPoint(for: lastPt, pFrame: pFrame, pBounds: pBounds)
                    let sCand = canvasPoint(for: candidate, pFrame: pFrame, pBounds: pBounds)

                    // Dashed rubber-band segment
                    let rbPath = NSBezierPath()
                    rbPath.lineWidth = max(viewModel.measurementStrokeWidth * viewModel.effectiveZoom, 1.5)
                    let dashes: [CGFloat] = [4.0, 3.0]
                    rbPath.setLineDash(dashes, count: 2, phase: 0)
                    rbPath.move(to: sLast)
                    rbPath.line(to: sCand)
                    color.setStroke()
                    rbPath.stroke()

                    // Shaded area preview for polygon
                    if viewModel.canvasMode == .measureArea && currentMeasurePoints.count >= 2 {
                        let polyPath = NSBezierPath()
                        let p0 = canvasPoint(for: currentMeasurePoints[0], pFrame: pFrame, pBounds: pBounds)
                        polyPath.move(to: p0)
                        for pt in currentMeasurePoints.dropFirst() {
                            polyPath.line(to: canvasPoint(for: pt, pFrame: pFrame, pBounds: pBounds))
                        }
                        polyPath.line(to: sCand)
                        polyPath.close()
                        color.withAlphaComponent(0.18).setFill()
                        polyPath.fill()
                    }

                    // Snapping visual indicators
                    if isSnappedVertex {
                        let snapRing = NSBezierPath(ovalIn: NSRect(x: sCand.x - 6.0, y: sCand.y - 6.0, width: 12.0, height: 12.0))
                        snapRing.lineWidth = 2.0
                        NSColor.magenta.setStroke()
                        snapRing.stroke()
                    }

                    // Floating Live Measurement Badge near cursor
                    let dist = hypot(candidate.x - lastPt.x, candidate.y - lastPt.y)
                    let badgeText: String
                    switch viewModel.canvasMode {
                    case .measureLength, .calibrateScale:
                        let totalDist = hypot(candidate.x - currentMeasurePoints[0].x, candidate.y - currentMeasurePoints[0].y)
                        badgeText = pageScale.formatLength(points: totalDist)
                    case .measurePerimeter:
                        var total: Double = 0
                        for i in 1..<currentMeasurePoints.count {
                            total += hypot(currentMeasurePoints[i].x - currentMeasurePoints[i-1].x, currentMeasurePoints[i].y - currentMeasurePoints[i-1].y)
                        }
                        total += dist
                        badgeText = "Perimeter: \(pageScale.formatLength(points: total))"
                    case .measureArea:
                        if currentMeasurePoints.count >= 2 {
                            let allPts = currentMeasurePoints + [candidate]
                            let areaPts = calculateShoelaceArea(points: allPts)
                            badgeText = "Area: \(pageScale.formatArea(pointsSquared: areaPts))"
                        } else {
                            badgeText = pageScale.formatLength(points: dist)
                        }
                    case .measureAngle:
                        if currentMeasurePoints.count == 2 {
                            let apex = currentMeasurePoints[1]
                            let r1 = currentMeasurePoints[0]
                            let deg = calculateAngleDegrees(r1: r1, apex: apex, r2: candidate)
                            badgeText = String(format: "%.1f°", deg)
                        } else {
                            badgeText = pageScale.formatLength(points: dist)
                        }
                    default:
                        badgeText = ""
                    }

                    if !badgeText.isEmpty {
                        let badgePos = NSPoint(x: sCand.x + 14.0, y: sCand.y + 14.0)
                        drawMeasurementTextPill(text: badgeText, at: badgePos, color: color, isSelected: false)
                    }
                }
            }

            // 3. Search Highlights
            let matches = viewModel.matches(on: pageIdx)
            for match in matches {
                let isActive = viewModel.isActiveMatch(match)
                for quad in match.highlightQuads {
                    let path = highlightPath(for: quad, minSize: CGSize(width: 4, height: 8), pFrame: pFrame, pBounds: pBounds)

                    if isActive {
                        NSColor.systemOrange.withAlphaComponent(0.60).setFill()
                        path.fill()
                        NSColor.systemOrange.setStroke()
                        path.lineWidth = 1.5
                        path.stroke()
                    } else {
                        NSColor.systemYellow.withAlphaComponent(0.40).setFill()
                        path.fill()
                        NSColor.systemYellow.withAlphaComponent(0.70).setStroke()
                        path.lineWidth = 0.8
                        path.stroke()
                    }
                }
            }

            // 3.05 Compare Documents: what differs from the other document
            let marks = viewModel.compareMarks
            if !marks.isEmpty {
                let color = marks.color
                for rect in marks.changed[pageIdx] ?? [] {
                    let path = highlightPath(for: PDFQuad(rect: rect.insetBy(dx: -1, dy: -1)), minSize: CGSize(width: 4, height: 8), pFrame: pFrame, pBounds: pBounds)
                    color.withAlphaComponent(0.28).setFill()
                    path.fill()
                }
                for rect in marks.gaps[pageIdx] ?? [] {
                    let path = highlightPath(for: PDFQuad(rect: rect), minSize: CGSize(width: 2, height: 8), pFrame: pFrame, pBounds: pBounds)
                    color.setFill()
                    path.fill()
                }
                // Text in another place in the other document: underlined, not filled, as the text
                // itself is the same.
                let zoom = viewModel.effectiveZoom
                for rect in marks.moved[pageIdx] ?? [] {
                    let start = canvasPoint(for: CGPoint(x: rect.minX, y: rect.maxY), pFrame: pFrame, pBounds: pBounds)
                    let line = NSBezierPath()
                    line.move(to: NSPoint(x: start.x, y: start.y + 1))
                    line.line(to: NSPoint(x: start.x + rect.width * zoom, y: start.y + 1))
                    line.lineWidth = max(1, 1.5 * min(zoom, 2))
                    CompareMarks.movedColor.withAlphaComponent(0.8).setStroke()
                    line.stroke()
                }
                // The change chosen in the Changes list, or with Next or Previous Change: filled more
                // strongly (outlining each line would box in a long change line by line).
                if let active = marks.active, active.pageIndex == pageIdx {
                    for rect in active.rects {
                        let path = highlightPath(for: PDFQuad(rect: rect.insetBy(dx: -1, dy: -1)), minSize: CGSize(width: 4, height: 8), pFrame: pFrame, pBounds: pBounds)
                        color.withAlphaComponent(rect.width < 4 ? 1 : 0.32).setFill()
                        path.fill()
                    }
                }
            }

            // 3.1 Redaction Found Matches Highlights
            if viewModel.isRedactionBarVisible && viewModel.editRedactTab == .findAndRedact {
                let pageRedactMatches = viewModel.redactionMatches.filter { $0.result.pageIndex == pageIdx }
                for item in pageRedactMatches {
                    let isActive = (viewModel.activeRedactionMatchId == item.id)
                    let quads = item.result.highlightQuads.isEmpty ? [PDFQuad(rect: item.result.rect)] : item.result.highlightQuads
                    for quad in quads {
                        let r = quad.boundingRect
                        let qx = pFrame.minX + (r.minX - pBounds.minX) * viewModel.effectiveZoom
                        let qy = pFrame.minY + (r.minY - pBounds.minY) * viewModel.effectiveZoom
                        let qw = max(r.width * viewModel.effectiveZoom, 4)
                        let qh = max(r.height * viewModel.effectiveZoom, 8)
                        let quadRect = NSRect(x: qx, y: qy, width: qw, height: qh)
                        let path = NSBezierPath(roundedRect: quadRect, xRadius: 2, yRadius: 2)

                        if isActive {
                            NSColor.systemOrange.withAlphaComponent(0.65).setFill()
                            path.fill()
                            NSColor.systemOrange.setStroke()
                            path.lineWidth = 2.0
                            path.stroke()
                        } else if item.isSelected {
                            NSColor.systemYellow.withAlphaComponent(0.40).setFill()
                            path.fill()
                            NSColor.systemYellow.withAlphaComponent(0.70).setStroke()
                            path.lineWidth = 0.8
                            path.stroke()
                        } else {
                            NSColor.systemGray.withAlphaComponent(0.20).setFill()
                            path.fill()
                        }
                    }
                }
            }
            
            // 4. Text / Marquee Drag Selection Highlights
            var selectionResultsForPage: [SelectionResult] = []
            if let sel = viewModel.activeSelection, sel.pageIndex == pageIdx {
                selectionResultsForPage.append(sel.result)
            }
            if let extra = viewModel.additionalSelectionPages.first(where: { $0.pageIndex == pageIdx }) {
                selectionResultsForPage.append(extra.result)
            }
            for selResult in selectionResultsForPage {
                let isRectMode = (selResult.mode == .rectangularArea)
                for quad in selResult.highlightQuads {
                    let path = highlightPath(for: quad, minSize: CGSize(width: 2, height: 4), pFrame: pFrame, pBounds: pBounds)

                    if isRectMode {
                        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                        path.fill()
                        NSColor.controlAccentColor.setStroke()
                        path.lineWidth = 1.5
                        let pattern: [CGFloat] = [5, 3]
                        path.setLineDash(pattern, count: 2, phase: 0)
                        path.stroke()
                    } else {
                        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.40).setFill()
                        path.fill()
                    }
                }
            }
            
            // 5. Active Snapshot Focus Ring
            if let activeSnap = viewModel.activeSnapshotTarget, activeSnap.targetPage == pageIdx {
                let snapRect = focusRingRect(for: activeSnap, on: pageIdx, pageBounds: pBounds, pageFrame: pFrame)
                
                let path = NSBezierPath(roundedRect: snapRect, xRadius: 4, yRadius: 4)
                NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
                path.fill()
                NSColor.controlAccentColor.setStroke()
                path.lineWidth = 3.0
                path.stroke()
            }
            
            // 6. Hovered Link Highlight
            if let hLink = hoveredLink, hLink.sourcePage == pageIdx, let r = hLink.sourceRect {
                let lx = pFrame.minX + (r.minX - pBounds.minX) * viewModel.effectiveZoom
                let ly = pFrame.minY + (r.minY - pBounds.minY) * viewModel.effectiveZoom
                let lw = max(r.width * viewModel.effectiveZoom, 10)
                let lh = max(r.height * viewModel.effectiveZoom, 10)
                let linkRect = NSRect(x: lx, y: ly, width: lw, height: lh)
                
                let path = NSBezierPath(roundedRect: linkRect, xRadius: 2, yRadius: 2)
                NSColor.systemBlue.withAlphaComponent(0.12).setFill()
                path.fill()
            }
        }
    }
    
    /// Computes the canvas frame for an active snapshot / reference target's focus ring,
    /// ensuring it wraps the target content cleanly and never falls outside the page boundaries.
    private func focusRingRect(for activeSnap: SnapshotTarget, on pageIdx: Int, pageBounds: CGRect, pageFrame: CGRect) -> NSRect {
        let targetRect = viewModel.resolvedTargetRect(for: activeSnap)

        // Map to canvas coordinates
        let sx = pageFrame.minX + (targetRect.minX - pageBounds.minX) * viewModel.effectiveZoom
        let sy = pageFrame.minY + (targetRect.minY - pageBounds.minY) * viewModel.effectiveZoom
        let sw = max(targetRect.width * viewModel.effectiveZoom, 24)
        let sh = max(targetRect.height * viewModel.effectiveZoom, 20)

        // Ensure the focus ring stays strictly within the visible page frame
        let safeMargin: CGFloat = 4
        let safeMinX = pageFrame.minX + safeMargin
        let safeMaxX = pageFrame.maxX - safeMargin
        let safeMinY = pageFrame.minY + safeMargin
        let safeMaxY = pageFrame.maxY - safeMargin

        let finalX = max(safeMinX, min(sx, safeMaxX - 24))
        let finalY = max(safeMinY, min(sy, safeMaxY - 20))
        let finalW = min(sw, safeMaxX - finalX)
        let finalH = min(sh, safeMaxY - finalY)

        return NSRect(x: finalX, y: finalY, width: max(finalW, 24), height: max(finalH, 20))
    }
}
