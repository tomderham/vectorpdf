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
    // MARK: - Mouse & Gesture Interaction
    
    public override func mouseDown(with event: NSEvent) {
        PDFViewerViewModel.active = viewModel
        PDFViewerAppCoordinator.shared.registerActive(viewModel)
        window?.makeFirstResponder(self)
        // Interaction is only supported in interactive single-column, unrotated mode.
        guard viewModel.isInteractiveViewingMode else { return }
        let point = convert(event.locationInWindow, from: nil)

        // Handle clicks on or outside the active inline text field
        if let tf = activeInlineTextField {
            if tf.frame.contains(point) {
                return
            } else {
                commitActiveInlineTextField()
            }
        }

        // In redact mode: capture start point for draft redaction box
        if viewModel.canvasMode == .redact {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                currentRedactionPage = pageIdx
                currentRedactionStart = pagePoint
                currentRedactionEnd = pagePoint
                needsDisplay = true
            }
            return
        }

        // In draw mode: capture start point for freehand ink stroke
        if viewModel.canvasMode == .draw {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                currentDrawingPageIndex = pageIdx
                currentDrawingPoints = [pagePoint]
                needsDisplay = true
            }
            return
        }

        // In stamp mode: place signature at clicked location
        if viewModel.canvasMode == .stamp {
            if let data = viewModel.pendingSignatureData,
               let (pageIdx, _, pagePoint) = pageInfo(at: point),
               let doc = viewModel.document {
                let pBounds = doc.pageBounds[pageIdx]
                let img = NSImage(data: data)
                let imgSize = img?.size ?? CGSize(width: 360, height: 140)
                let stampW: CGFloat = 140
                let stampH: CGFloat = stampW * (imgSize.height / max(imgSize.width, 1))
                let stampRect = CGRect(
                    x: max(pBounds.minX, min(pagePoint.x - stampW / 2, pBounds.maxX - stampW)),
                    y: max(pBounds.minY, min(pagePoint.y - stampH / 2, pBounds.maxY - stampH)),
                    width: stampW,
                    height: stampH
                )
                if let annot = viewModel.addStampAnnotation(pageIndex: pageIdx, rect: stampRect, imageData: data) {
                    selectedAnnotation = (id: annot.id, pageIndex: pageIdx)
                }
                viewModel.canvasMode = .select
                viewModel.pendingSignatureData = nil
                currentHoverCanvasPoint = nil
                needsDisplay = true
            }
            return
        }

        // In eraser mode: remove annotation at clicked point
        if viewModel.canvasMode == .eraser {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                viewModel.removeAnnotation(at: pagePoint, pageIndex: pageIdx)
                needsDisplay = true
            }
            return
        }

        // For .select, .text, and .callout modes: Check if clicked on an existing freeText, callout, or stamp annotation
        if viewModel.canvasMode == .select || viewModel.canvasMode == .text || viewModel.canvasMode == .callout {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point),
               let list = viewModel.pageAnnotations[pageIdx] {

                // 1. If an annotation is already selected on this page, check if clicking on its corner resize handles
                if let sel = selectedAnnotation, sel.pageIndex == pageIdx,
                   let selAnnot = list.first(where: { $0.id == sel.id }),
                   let r = selAnnot.rect,
                   let resizePart = hitTestResizeHandle(for: r, on: pageIdx, canvasPoint: point) {
                    activeAnnotationDrag = (
                        id: selAnnot.id,
                        pageIndex: pageIdx,
                        part: resizePart,
                        initialAnnotation: selAnnot,
                        startPagePoint: pagePoint,
                        currentDelta: .zero
                    )
                    needsDisplay = true
                    return
                }

                // 2. Check if clicked on an annotation body or callout target/knee
                if let hit = list.reversed().first(where: { ($0.type == .callout || $0.type == .freeText || $0.type == .stamp) && $0.contains(pagePoint: pagePoint, tolerance: 6.0) }) {
                    if event.clickCount == 2 && hit.type != .stamp {
                        startInlineEditing(annotation: hit, pageIndex: pageIdx)
                        return
                    } else {
                        selectedAnnotation = (id: hit.id, pageIndex: pageIdx)
                        if let fs = hit.fontSize {
                            viewModel.selectedFontSize = fs
                        }
                        viewModel.selectedAnnotationColor = hit.color

                        let part = hit.type == .callout ? calloutDragPart(for: hit, at: pagePoint) : .entireAnnotation
                        activeAnnotationDrag = (
                            id: hit.id,
                            pageIndex: pageIdx,
                            part: part,
                            initialAnnotation: hit,
                            startPagePoint: pagePoint,
                            currentDelta: .zero
                        )
                        needsDisplay = true
                        return
                    }
                }
            }
        }

        // If clicking outside any selected annotation, deselect it
        if selectedAnnotation != nil {
            selectedAnnotation = nil
            needsDisplay = true
        }

        // In measurement or calibration modes:
        if viewModel.canvasMode == .measureLength ||
           viewModel.canvasMode == .measurePerimeter ||
           viewModel.canvasMode == .measureArea ||
           viewModel.canvasMode == .measureAngle ||
           viewModel.canvasMode == .calibrateScale {

            if let (pageIdx, _, rawPagePoint) = pageInfo(at: point) {
                let prevPt = (currentMeasurePage == pageIdx) ? currentMeasurePoints.last : nil
                let snappedPoint = applySnapping(to: rawPagePoint, fromPoint: prevPt, inPage: pageIdx, modifierFlags: event.modifierFlags)

                switch viewModel.canvasMode {
                case .measureLength:
                    currentMeasurePage = pageIdx
                    currentMeasurePoints = [snappedPoint]
                    currentMeasureCandidatePoint = snappedPoint
                    needsDisplay = true

                case .measurePerimeter:
                    if currentMeasurePage != pageIdx {
                        currentMeasurePage = pageIdx
                        currentMeasurePoints = [snappedPoint]
                    } else {
                        if event.clickCount == 2 && currentMeasurePoints.count >= 2 {
                            commitCurrentPerimeter()
                        } else {
                            currentMeasurePoints.append(snappedPoint)
                        }
                    }
                    currentMeasureCandidatePoint = snappedPoint
                    needsDisplay = true

                case .measureArea:
                    if currentMeasurePage != pageIdx {
                        currentMeasurePage = pageIdx
                        currentMeasurePoints = [snappedPoint]
                    } else {
                        let isCloseToFirst = currentMeasurePoints.count >= 3 && hypot(snappedPoint.x - currentMeasurePoints[0].x, snappedPoint.y - currentMeasurePoints[0].y) <= 12.0
                        if event.clickCount == 2 || isCloseToFirst {
                            commitCurrentArea()
                        } else {
                            currentMeasurePoints.append(snappedPoint)
                        }
                    }
                    currentMeasureCandidatePoint = snappedPoint
                    needsDisplay = true

                case .measureAngle:
                    if currentMeasurePage != pageIdx {
                        currentMeasurePage = pageIdx
                        currentMeasurePoints = [snappedPoint]
                    } else {
                        currentMeasurePoints.append(snappedPoint)
                        if currentMeasurePoints.count == 3 {
                            commitCurrentAngle()
                        }
                    }
                    currentMeasureCandidatePoint = snappedPoint
                    needsDisplay = true

                case .calibrateScale:
                    if currentMeasurePoints.isEmpty {
                        currentMeasurePage = pageIdx
                        currentMeasurePoints = [snappedPoint]
                        currentMeasureCandidatePoint = snappedPoint
                        needsDisplay = true
                    } else {
                        let p0 = currentMeasurePoints[0]
                        let p1 = snappedPoint
                        let dist = hypot(p1.x - p0.x, p1.y - p0.y)
                        currentMeasurePoints = []
                        currentMeasureCandidatePoint = nil
                        currentMeasurePage = nil
                        needsDisplay = true

                        viewModel.calibrationMeasuredPoints = dist
                        viewModel.calibrationPageIndex = pageIdx
                        viewModel.isShowingCalibrationSheet = true
                        viewModel.canvasMode = .measureLength
                    }

                default:
                    break
                }
            }
            return
        }

        // In callout mode: start new callout note
        if viewModel.canvasMode == .callout {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                currentCalloutPage = pageIdx
                currentCalloutStart = pagePoint
                currentCalloutEnd = pagePoint
                needsDisplay = true
            }
            return
        }

        // In text mode: start new text box
        if viewModel.canvasMode == .text {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                startInlineEditing(newAt: pagePoint, pageIndex: pageIdx)
                return
            }
        }

        // Double-click to select word, triple-click to select line
        if event.clickCount == 2 {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                viewModel.selectWord(at: pagePoint, pageIndex: pageIdx)
                isDraggingSelection = false
                needsDisplay = true
                return
            }
        } else if event.clickCount >= 3 {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                viewModel.selectLine(at: pagePoint, pageIndex: pageIdx)
                isDraggingSelection = false
                needsDisplay = true
                return
            }
        }

        // Check clickable links / cross-references
        if let (pageIdx, _, pagePoint) = pageInfo(at: point),
           let links = viewModel.pageLinks[pageIdx],
           let clickedLink = links.first(where: { $0.sourceRect?.contains(pagePoint) == true }) {
            pendingLinkTarget = (target: clickedLink, opensInNewWindow: event.modifierFlags.contains(.command), didPeek: false)
            dragStartCanvasPoint = point
            activeDragPage = pageIdx
            isDraggingSelection = true
            hasDraggedPastThreshold = false
            return
        }
        
        // Otherwise begin drag selection
        if let (pageIdx, _, _) = pageInfo(at: point) {
            dragStartCanvasPoint = point
            activeDragPage = pageIdx
            isDraggingSelection = true
            hasDraggedPastThreshold = false
            viewModel.clearSelection()
            needsDisplay = true
        }
    }
    
    public override func mouseDragged(with event: NSEvent) {
        if currentMeasurePage != nil {
            let point = convert(event.locationInWindow, from: nil)
            if let (pageIdx, _, rawPagePoint) = pageInfo(at: point), pageIdx == currentMeasurePage {
                let prevPt = currentMeasurePoints.last
                currentMeasureCandidatePoint = applySnapping(to: rawPagePoint, fromPoint: prevPt, inPage: pageIdx, modifierFlags: event.modifierFlags)
                needsDisplay = true
            }
            return
        }

        if let drag = activeAnnotationDrag {
            guard let pFrame = pageFrame(for: drag.pageIndex),
                  let doc = viewModel.document else { return }
            let currentCanvas = convert(event.locationInWindow, from: nil)
            let pBounds = doc.pageBounds[drag.pageIndex]
            let currentPagePoint = CGPoint(
                x: pBounds.minX + ((currentCanvas.x - pFrame.minX) / viewModel.effectiveZoom),
                y: pBounds.minY + ((currentCanvas.y - pFrame.minY) / viewModel.effectiveZoom)
            )
            let dx = currentPagePoint.x - drag.startPagePoint.x
            let dy = currentPagePoint.y - drag.startPagePoint.y
            activeAnnotationDrag?.currentDelta = CGSize(width: dx, height: dy)
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .redact {
            guard let dragPageIdx = currentRedactionPage,
                  let pFrame = pageFrame(for: dragPageIdx),
                  let doc = viewModel.document else { return }
            let currentCanvas = convert(event.locationInWindow, from: nil)
            let pBounds = doc.pageBounds[dragPageIdx]
            currentRedactionEnd = CGPoint(
                x: pBounds.minX + ((currentCanvas.x - pFrame.minX) / viewModel.effectiveZoom),
                y: pBounds.minY + ((currentCanvas.y - pFrame.minY) / viewModel.effectiveZoom)
            )
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .callout {
            guard let dragPageIdx = currentCalloutPage,
                  let pFrame = pageFrame(for: dragPageIdx),
                  let doc = viewModel.document else { return }
            let currentCanvas = convert(event.locationInWindow, from: nil)
            let pBounds = doc.pageBounds[dragPageIdx]
            currentCalloutEnd = CGPoint(
                x: pBounds.minX + ((currentCanvas.x - pFrame.minX) / viewModel.effectiveZoom),
                y: pBounds.minY + ((currentCanvas.y - pFrame.minY) / viewModel.effectiveZoom)
            )
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .draw {
            guard let dragPageIdx = currentDrawingPageIndex,
                  let pFrame = pageFrame(for: dragPageIdx),
                  let doc = viewModel.document else { return }
            let currentCanvas = convert(event.locationInWindow, from: nil)
            let pBounds = doc.pageBounds[dragPageIdx]
            let currentPagePoint = CGPoint(
                x: pBounds.minX + ((currentCanvas.x - pFrame.minX) / viewModel.effectiveZoom),
                y: pBounds.minY + ((currentCanvas.y - pFrame.minY) / viewModel.effectiveZoom)
            )
            currentDrawingPoints.append(currentPagePoint)
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .eraser {
            let currentCanvas = convert(event.locationInWindow, from: nil)
            if let (pageIdx, _, pagePoint) = pageInfo(at: currentCanvas) {
                viewModel.removeAnnotation(at: pagePoint, pageIndex: pageIdx)
                needsDisplay = true
            }
            return
        }

        guard isDraggingSelection,
              let startCanvas = dragStartCanvasPoint,
              let dragPageIdx = activeDragPage,
              let pFrame = pageFrame(for: dragPageIdx),
              let doc = viewModel.document else { return }

        let currentCanvas = convert(event.locationInWindow, from: nil)
        let dragDistance = hypot(currentCanvas.x - startCanvas.x, currentCanvas.y - startCanvas.y)

        if !hasDraggedPastThreshold {
            if dragDistance > 3.0 {
                hasDraggedPastThreshold = true
                if pendingLinkTarget != nil {
                    pendingLinkTarget = nil
                    linkPeek.dismiss()
                    viewModel.clearSelection()
                    hoveredLink = nil
                }
                let isOption = event.modifierFlags.contains(.option)
                if isOption {
                    NSCursor.crosshair.set()
                } else {
                    NSCursor.iBeam.set()
                }
            } else {
                return
            }
        }

        let pBounds = doc.pageBounds[dragPageIdx]

        let startPagePoint = CGPoint(
            x: pBounds.minX + ((startCanvas.x - pFrame.minX) / viewModel.effectiveZoom),
            y: pBounds.minY + ((startCanvas.y - pFrame.minY) / viewModel.effectiveZoom)
        )

        let isOptionPressed = event.modifierFlags.contains(.option)
        let mode: SelectionMode = isOptionPressed ? .rectangularArea : viewModel.selectionMode

        // Text selection can span across page boundaries; marquee selection is constrained to a single page.
        if mode == .readingOrder,
           let (currentPageIdx, _, currentPagePoint) = pageInfo(at: currentCanvas),
           currentPageIdx != dragPageIdx {
            viewModel.handleCrossPageDragSelect(pageA: dragPageIdx, pointA: startPagePoint, pageB: currentPageIdx, pointB: currentPagePoint)
            needsDisplay = true
            return
        }

        let currentPagePoint = CGPoint(
            x: pBounds.minX + ((currentCanvas.x - pFrame.minX) / viewModel.effectiveZoom),
            y: pBounds.minY + ((currentCanvas.y - pFrame.minY) / viewModel.effectiveZoom)
        )

        viewModel.handleDragSelect(
            pageIndex: dragPageIdx,
            startPagePoint: startPagePoint,
            currentPagePoint: currentPagePoint,
            forceMode: mode
        )
        needsDisplay = true
    }
    
    public override func mouseUp(with event: NSEvent) {
        if let drag = activeAnnotationDrag {
            activeAnnotationDrag = nil
            let dx = drag.currentDelta.width
            let dy = drag.currentDelta.height
            let dist = hypot(dx, dy)
            if dist > 2.0 {
                let orig = drag.initialAnnotation
                let pIdx = drag.pageIndex
                viewModel.removeAnnotation(orig)

                if orig.type == .callout {
                    var targetPt = orig.targetPoint ?? CGPoint(x: (orig.rect?.minX ?? 50) - 30, y: orig.rect?.midY ?? 50)
                    var kneePt = orig.kneePoint ?? CGPoint(x: (orig.rect?.minX ?? 50) - 10, y: orig.rect?.midY ?? 50)
                    var rect = orig.rect ?? CGRect(x: 50, y: 50, width: 80, height: 22)

                    switch drag.part {
                    case .calloutTargetPoint:
                        targetPt = CGPoint(x: targetPt.x + dx, y: targetPt.y + dy)
                    case .calloutKneePoint:
                        kneePt = CGPoint(x: kneePt.x + dx, y: kneePt.y + dy)
                    case .calloutTextBox:
                        rect = rect.offsetBy(dx: dx, dy: dy)
                        kneePt = CGPoint(x: kneePt.x + dx, y: kneePt.y + dy)
                    case .resizeTopLeft, .resizeTopRight, .resizeBottomLeft, .resizeBottomRight:
                        rect = updatedRect(from: rect, part: drag.part, delta: drag.currentDelta)
                    case .entireAnnotation:
                        targetPt = CGPoint(x: targetPt.x + dx, y: targetPt.y + dy)
                        kneePt = CGPoint(x: kneePt.x + dx, y: kneePt.y + dy)
                        rect = rect.offsetBy(dx: dx, dy: dy)
                    }

                    if let updated = viewModel.addCalloutAnnotation(
                        pageIndex: pIdx,
                        targetPoint: targetPt,
                        kneePoint: kneePt,
                        textBoxRect: rect,
                        text: orig.text,
                        fontSize: orig.fontSize ?? viewModel.selectedFontSize,
                        color: orig.color
                    ) {
                        selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                    }
                } else if orig.type == .freeText {
                    let rect = updatedRect(from: orig.rect ?? CGRect(x: 50, y: 50, width: 80, height: 22), part: drag.part, delta: drag.currentDelta)
                    if let updated = viewModel.addFreeTextAnnotation(
                        pageIndex: pIdx,
                        rect: rect,
                        text: orig.text,
                        fontSize: orig.fontSize ?? viewModel.selectedFontSize,
                        color: orig.color
                    ) {
                        selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                    }
                } else if orig.type == .stamp {
                    let rect = updatedRect(from: orig.rect ?? CGRect(x: 50, y: 50, width: 140, height: 50), part: drag.part, delta: drag.currentDelta)
                    if let data = orig.stampImageData, let updated = viewModel.addStampAnnotation(pageIndex: pIdx, rect: rect, imageData: data, color: orig.color) {
                        selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                    }
                }
            }
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .redact {
            if let pIdx = currentRedactionPage,
               let start = currentRedactionStart,
               let end = currentRedactionEnd {
                let minX = min(start.x, end.x)
                let maxX = max(start.x, end.x)
                let minY = min(start.y, end.y)
                let maxY = max(start.y, end.y)
                if (maxX - minX) > 4 && (maxY - minY) > 4 {
                    let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                    viewModel.applyRedactionRegion(pageIndex: pIdx, rect: rect)
                }
            }
            currentRedactionPage = nil
            currentRedactionStart = nil
            currentRedactionEnd = nil
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .callout {
            if let pIdx = currentCalloutPage,
               let start = currentCalloutStart,
               let end = currentCalloutEnd {
                let dist = hypot(end.x - start.x, end.y - start.y)
                if dist > 8 {
                    let target = start
                    let knee = CGPoint(x: end.x, y: start.y)
                    let boxRect = CGRect(x: end.x, y: end.y - 12, width: 140, height: 26)
                    let annot = viewModel.addCalloutAnnotation(
                        pageIndex: pIdx,
                        targetPoint: target,
                        kneePoint: knee,
                        textBoxRect: boxRect,
                        text: "Note",
                        fontSize: viewModel.selectedFontSize,
                        color: viewModel.selectedAnnotationColor
                    )
                    if let a = annot {
                        startInlineEditing(annotation: a, pageIndex: pIdx)
                    }
                }
            }
            currentCalloutPage = nil
            currentCalloutStart = nil
            currentCalloutEnd = nil
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .measureLength {
            if let pIdx = currentMeasurePage,
               let p0 = currentMeasurePoints.first,
               let p1 = currentMeasureCandidatePoint {
                let dist = hypot(p1.x - p0.x, p1.y - p0.y)
                if dist > 4.0 {
                    let pageScale = viewModel.scaleConfig(for: pIdx)
                    let text = pageScale.formatLength(points: dist)
                    if let annot = viewModel.addMeasurementAnnotation(
                        pageIndex: pIdx,
                        type: .measureLength,
                        points: [p0, p1],
                        value: dist,
                        formattedText: text,
                        leaderOffset: 0.0,
                        color: viewModel.selectedAnnotationColor,
                        strokeWidth: viewModel.drawStrokeWidth
                    ) {
                        selectedAnnotation = (id: annot.id, pageIndex: pIdx)
                    }
                }
            }
            currentMeasurePage = nil
            currentMeasurePoints = []
            currentMeasureCandidatePoint = nil
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .draw {
            if let pIdx = currentDrawingPageIndex, !currentDrawingPoints.isEmpty {
                viewModel.addInkAnnotation(
                    pageIndex: pIdx,
                    points: currentDrawingPoints,
                    strokeWidth: viewModel.drawStrokeWidth,
                    color: viewModel.selectedAnnotationColor
                )
            }
            currentDrawingPoints = []
            currentDrawingPageIndex = nil
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .eraser {
            needsDisplay = true
            return
        }

        let pending = pendingLinkTarget
        pendingLinkTarget = nil
        let wasDragged = hasDraggedPastThreshold
        hasDraggedPastThreshold = false
        isDraggingSelection = false
        dragStartCanvasPoint = nil
        activeDragPage = nil

        if let pending = pending, !wasDragged {
            hoveredLink = nil
            needsDisplay = true

            // Releasing a Force Click peek doesn't also follow the link.
            if pending.didPeek {
                linkPeek.dismiss()
                return
            }

            // Confirm release point is still within or immediately adjacent to link source rectangle
            let releasePoint = convert(event.locationInWindow, from: nil)
            if let (upPageIdx, _, upPagePoint) = pageInfo(at: releasePoint) {
                if upPageIdx != pending.target.sourcePage ||
                   (pending.target.sourceRect != nil && !pending.target.sourceRect!.insetBy(dx: -4, dy: -4).contains(upPagePoint)) {
                    return
                }
            } else {
                return
            }

            if let uri = pending.target.uri, (uri.hasPrefix("http://") || uri.hasPrefix("https://") || uri.hasPrefix("mailto:")), let url = URL(string: uri) {
                PDFViewerAppCoordinator.shared.openExternalURL(url)
                return
            } else if pending.target.targetPage >= 0 {
                // Command-click opens the link target in a snapshot window.
                if pending.opensInNewWindow {
                    viewModel.openSnapshotInNewWindow(pending.target)
                } else {
                    viewModel.clearSelection()
                    viewModel.jumpToSnapshot(pending.target)
                }
                return
            }
        }
    }
    
    public override func magnify(with event: NSEvent) {
        if let sv = enclosingScrollView as? PDFScrollView {
            sv.magnify(with: event)
        } else {
            super.magnify(with: event)
        }
    }
    
    public override func smartMagnify(with event: NSEvent) {
        if let sv = enclosingScrollView as? PDFScrollView {
            sv.smartMagnify(with: event)
        } else {
            super.smartMagnify(with: event)
        }
    }
    
    public override func mouseMoved(with event: NSEvent) {
        updateLinkPeek(modifierFlags: event.modifierFlags)
        // Same rationale as mouseDown: link targets aren't meaningful outside the plain
        // single-column, unrotated layout, so don't hint at a clickable link (cursor/highlight)
        // that clicking wouldn't actually do anything about.
        guard viewModel.isInteractiveViewingMode else {
            if hoveredLink != nil {
                hoveredLink = nil
                needsDisplay = true
            }
            NSCursor.arrow.set()
            return
        }
        if viewModel.canvasMode == .draw || viewModel.canvasMode == .eraser {
            if hoveredLink != nil {
                hoveredLink = nil
                needsDisplay = true
            }
            NSCursor.crosshair.set()
            return
        }
        if viewModel.canvasMode == .stamp {
            if hoveredLink != nil {
                hoveredLink = nil
            }
            currentHoverCanvasPoint = convert(event.locationInWindow, from: nil)
            NSCursor.crosshair.set()
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .measureLength ||
           viewModel.canvasMode == .measurePerimeter ||
           viewModel.canvasMode == .measureArea ||
           viewModel.canvasMode == .measureAngle ||
           viewModel.canvasMode == .calibrateScale {

            if hoveredLink != nil {
                hoveredLink = nil
            }
            NSCursor.crosshair.set()

            if currentMeasurePage != nil {
                let point = convert(event.locationInWindow, from: nil)
                if let (pageIdx, _, rawPagePoint) = pageInfo(at: point), pageIdx == currentMeasurePage {
                    let prevPt = currentMeasurePoints.last
                    currentMeasureCandidatePoint = applySnapping(to: rawPagePoint, fromPoint: prevPt, inPage: pageIdx, modifierFlags: event.modifierFlags)
                    needsDisplay = true
                }
            }
            return
        }
        let point = convert(event.locationInWindow, from: nil)

        // Hover feedback over annotations or callout handles in interactive modes
        if viewModel.canvasMode == .select || viewModel.canvasMode == .text || viewModel.canvasMode == .callout {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point),
               let list = viewModel.pageAnnotations[pageIdx] {
                // If an annotation is selected on this page, check if hovering over its corner handles
                if let sel = selectedAnnotation, sel.pageIndex == pageIdx,
                   let selAnnot = list.first(where: { $0.id == sel.id }),
                   let r = selAnnot.rect,
                   hitTestResizeHandle(for: r, on: pageIdx, canvasPoint: point) != nil {
                    if hoveredLink != nil { hoveredLink = nil; needsDisplay = true }
                    NSCursor.crosshair.set()
                    return
                }

                if let sel = selectedAnnotation, sel.pageIndex == pageIdx,
                   let annot = list.first(where: { $0.id == sel.id }), annot.type == .callout {
                    let part = calloutDragPart(for: annot, at: pagePoint)
                    switch part {
                    case .calloutTargetPoint, .calloutKneePoint:
                        if hoveredLink != nil { hoveredLink = nil; needsDisplay = true }
                        NSCursor.crosshair.set()
                        return
                    default:
                        break
                    }
                }
                if list.contains(where: { ($0.type == .freeText || $0.type == .callout || $0.type == .stamp) && $0.contains(pagePoint: pagePoint, tolerance: 4.0) }) {
                    if hoveredLink != nil { hoveredLink = nil; needsDisplay = true }
                    NSCursor.openHand.set()
                    return
                }
            }
        }

        if let (pageIdx, _, pagePoint) = pageInfo(at: point),
           let links = viewModel.pageLinks[pageIdx],
           let link = links.first(where: { $0.sourceRect?.contains(pagePoint) == true }) {
            if hoveredLink?.id != link.id {
                hoveredLink = link
                needsDisplay = true
            }
            NSCursor.pointingHand.set()
        } else {
            if hoveredLink != nil {
                hoveredLink = nil
                needsDisplay = true
            }
            NSCursor.arrow.set()
        }
    }

    public override func cursorUpdate(with event: NSEvent) {
        if hoveredLink != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
    
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        linkPeek.dismiss()
        if currentHoverCanvasPoint != nil {
            currentHoverCanvasPoint = nil
            needsDisplay = true
        }
        if hoveredLink != nil {
            hoveredLink = nil
            needsDisplay = true
        }
        NSCursor.arrow.set()
    }
}
