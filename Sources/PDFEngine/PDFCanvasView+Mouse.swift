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
        hoverWorkItem?.cancel()
        if hoverOutline != nil { hoverOutline = nil; needsDisplay = true }
        PDFViewerViewModel.active = viewModel
        PDFViewerAppCoordinator.shared.registerActive(viewModel)
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        // Handle clicks on or outside the active inline text field
        if let tf = activeInlineTextField {
            if inlineTextFieldContains(tf, canvasPoint: point) {
                return
            } else {
                commitActiveInlineTextField()
            }
        }

        // ⇧⌘-click: open the source line under the pointer in the LaTeX editor (SyncTeX).
        if handleSyncTeXClick(event, at: point) {
            return
        }

        // A guide on the page is picked up to move it, or to drag it off the page to remove it.
        if beginGuideDrag(at: point) {
            return
        }

        // With the Inspector open, a click in Select mode shows what the page draws there.
        if viewModel.isInspectorVisible, viewModel.canvasMode == .select, let (pageIdx, _, pagePoint) = pageInfo(at: point) {
            viewModel.inspectContent(pageIndex: pageIdx, at: pagePoint)
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

        // Placing a signature field: dragged out, or clicked for one of the usual size; the
        // sheet to sign it opens on mouse up.
        if viewModel.canvasMode == .placeSignatureField {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                currentHoverCanvasPoint = nil
                currentMeasurePage = pageIdx
                currentMeasurePoints = [pagePoint]
                currentMeasureCandidatePoint = pagePoint
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

        // In note mode: place a note at the clicked location and open it for typing
        if viewModel.canvasMode == .note {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point),
               let annot = viewModel.addNoteAnnotation(pageIndex: pageIdx, at: pagePoint, color: viewModel.selectedAnnotationColor) {
                selectedAnnotation = (id: annot.id, pageIndex: pageIdx)
                viewModel.canvasMode = .select
                if let number = annot.documentObjectNumber {
                    showComments(pageIndex: pageIdx, objectNumber: number, isNewNote: true)
                }
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

        // For .select, .text, .callout and .shape modes: Check if clicked on an existing annotation that can move
        if !viewModel.isComparePane, viewModel.canvasMode == .select || viewModel.canvasMode == .text || viewModel.canvasMode == .callout || viewModel.canvasMode == .shape {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                let list = viewModel.shownAnnotations(onPage: pageIdx)

                // 1. If an annotation is already selected on this page, check if clicking on its corner resize handles
                if let sel = selectedAnnotation, sel.pageIndex == pageIdx,
                   let selAnnot = list.first(where: { $0.id == sel.id }),
                   selAnnot.type != .note, selAnnot.type != .line,
                   !selAnnot.isFromFile || selAnnot.isResizableFromFile,
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

                // 2. Check if clicked on an annotation body or callout target/knee. One that came
                // with the file is found as precisely as the document allows, and picked up.
                if let hit = annotationHit(pageIndex: pageIdx, at: pagePoint, list: list, pickingUp: true) {
                    if event.clickCount == 2, hit.isFromFile || (hit.type != .freeText && hit.type != .callout), let number = hit.documentObjectNumber {
                        showComments(pageIndex: pageIdx, objectNumber: number)
                        return
                    } else if event.clickCount == 2 && hit.type != .stamp {
                        startInlineEditing(annotation: hit, pageIndex: pageIdx)
                        return
                    } else if event.modifierFlags.contains(.shift), viewModel.canvasMode == .select {
                        // ⇧-click adds it to the selection, or takes it out.
                        toggleInSelection(hit, pageIndex: pageIdx)
                        return
                    } else {
                        // Clicking one of several selected keeps them all, to drag together.
                        if isAnnotationSelected(hit.id), !groupSelection.isEmpty {
                            groupSelection = allSelectedAnnotationIDs.filter { $0 != hit.id }
                        } else {
                            groupSelection = []
                        }
                        selectedAnnotation = (id: hit.id, pageIndex: pageIdx)
                        // The toolbar shows its style, to change it; not for several at once, whose
                        // styles differ, since changing the toolbar changes them all.
                        if groupSelection.isEmpty {
                            if let fs = hit.fontSize {
                                viewModel.selectedFontSize = fs
                            }
                            // The toolbar for its kind shows its color, to change it.
                            if hit.isMeasurement {
                                viewModel.measurementColor = hit.color
                                viewModel.measurementStrokeWidth = hit.strokeWidth
                            } else {
                                viewModel.selectedAnnotationColor = hit.color
                            }
                            // The toolbar shows the shape's own width and ending, to change them.
                            if hit.type == .square || hit.type == .circle || hit.type == .line || hit.isPolyShape || hit.type == .ink {
                                viewModel.drawStrokeWidth = hit.strokeWidth
                            }
                            if hit.type == .line || hit.type == .polyline, let ending = hit.lineEnding {
                                viewModel.selectedShapeLineEnding = ending
                            }

                        }

                        let part: DraggingAnnotationPart
                        switch hit.type {
                        case .callout where !hit.isFromFile: part = calloutDragPart(for: hit, at: pagePoint)
                        case .line: part = lineDragPart(for: hit, at: pagePoint)
                        case _ where hit.isMeasurement: part = measurementDragPart(for: hit, at: pagePoint)
                        default: part = .entireAnnotation
                        }
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

        // Double-clicking any other annotation opens its comments, as in Acrobat: a highlight,
        // drawing or measurement made here, or one that came with the file.
        if viewModel.canvasMode == .select, event.clickCount == 2,
           let (pageIdx, _, pagePoint) = pageInfo(at: point),
           let number = commentsTarget(at: pagePoint, pageIndex: pageIdx) {
            showComments(pageIndex: pageIdx, objectNumber: number)
            return
        }

        // If clicking outside any selected annotation, deselect it
        if selectedAnnotation != nil {
            selectedAnnotation = nil
            needsDisplay = true
        }

        // In measurement or calibration modes:
        if viewModel.canvasMode.isMeasuring {

            if let (pageIdx, _, rawPagePoint) = pageInfo(at: point) {
                let prevPt = (currentMeasurePage == pageIdx) ? currentMeasurePoints.last : nil
                let snappedPoint = applySnapping(to: rawPagePoint, fromPoint: prevPt, inPage: pageIdx, modifierFlags: event.modifierFlags)

                switch viewModel.canvasMode {
                case .measureLength, .measureRectangle, .measureCircle:
                    currentMeasurePage = pageIdx
                    currentMeasurePoints = [snappedPoint]
                    currentMeasureCandidatePoint = snappedPoint
                    needsDisplay = true

                case .measureArc:
                    if currentMeasurePage != pageIdx {
                        currentMeasurePage = pageIdx
                        currentMeasurePoints = [snappedPoint]
                    } else {
                        currentMeasurePoints.append(snappedPoint)
                        if currentMeasurePoints.count == 3 {
                            commitCurrentShape(.arc)
                        }
                    }
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

                case .measureCount:
                    // Each click counts one; nothing is selected, so the next can follow at once.
                    viewModel.addCountMarker(pageIndex: pageIdx, at: snappedPoint)
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

        // A polygon or polyline: each click adds a point; a double-click, or for a polygon a
        // click on its first point, finishes it.
        if viewModel.canvasMode == .shape, viewModel.selectedShape == .polygon || viewModel.selectedShape == .polyline {
            if let (pageIdx, _, rawPagePoint) = pageInfo(at: point) {
                let pagePoint = applySnapping(to: rawPagePoint, fromPoint: currentPolyPage == pageIdx ? currentPolyPoints.last : nil, inPage: pageIdx, modifierFlags: event.modifierFlags)
                if currentPolyPage != pageIdx {
                    currentPolyPage = pageIdx
                    currentPolyPoints = [pagePoint]
                } else {
                    // Near the first point as clicked, or as snapping moved the click.
                    let reach = 8 / max(viewModel.effectiveZoom, 0.01)
                    let first = currentPolyPoints[0]
                    let closesPolygon = viewModel.selectedShape == .polygon && currentPolyPoints.count >= 3
                        && min(hypot(pagePoint.x - first.x, pagePoint.y - first.y), hypot(rawPagePoint.x - first.x, rawPagePoint.y - first.y)) <= reach
                    if event.clickCount >= 2 || closesPolygon {
                        commitCurrentPolyShape()
                        return
                    }
                    currentPolyPoints.append(pagePoint)
                }
                currentPolyCandidate = pagePoint
                needsDisplay = true
            }
            return
        }

        // In shape mode: start a new shape
        if viewModel.canvasMode == .shape {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                currentShapePage = pageIdx
                currentShapeStart = pagePoint
                currentShapeEnd = pagePoint
                currentShapePath = [pagePoint]
                needsDisplay = true
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
                viewModel.selectionAnchor = (pageIndex: pageIdx, point: pagePoint)
                isDraggingSelection = false
                needsDisplay = true
                return
            }
        } else if event.clickCount >= 3 {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                viewModel.selectLine(at: pagePoint, pageIndex: pageIdx)
                viewModel.selectionAnchor = (pageIndex: pageIdx, point: pagePoint)
                isDraggingSelection = false
                needsDisplay = true
                return
            }
        }

        // ⇧-click extends the selection from where it started to here, across pages too, and
        // dragging on from there keeps extending it.
        if event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.option),
           let anchor = viewModel.selectionAnchor, viewModel.activeSelection != nil,
           let anchorGeometry = pageGeometry(for: anchor.pageIndex),
           let (pageIdx, _, pagePoint) = pageInfo(at: point) {
            viewModel.handleCrossPageDragSelect(pageA: anchor.pageIndex, pointA: anchor.point, pageB: pageIdx, pointB: pagePoint)
            dragStartCanvasPoint = anchorGeometry.canvasPoint(forPagePoint: anchor.point)
            activeDragPage = anchor.pageIndex
            isDraggingSelection = true
            hasDraggedPastThreshold = true
            needsDisplay = true
            return
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
            viewModel.selectionAnchor = (pageIndex: pageIdx, point: pageGeometry(for: pageIdx)?.pagePoint(forCanvasPoint: point) ?? point)
            needsDisplay = true
        }
    }
    
    public override func mouseDragged(with event: NSEvent) {
        updatePointerReadout(event)
        if continueGuideDrag(event) {
            return
        }
        updateAutoscroll(for: event)
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
            guard let geometry = pageGeometry(for: drag.pageIndex) else { return }
            let currentCanvas = convert(event.locationInWindow, from: nil)
            let currentPagePoint = geometry.pagePoint(forCanvasPoint: currentCanvas)
            var dx = currentPagePoint.x - drag.startPagePoint.x
            var dy = currentPagePoint.y - drag.startPagePoint.y
            // A measurement's point snaps, and keeps to Ortho Lock, as when it was drawn. A shape's
            // points are those that define it.
            let points = drag.initialAnnotation.measuredShape?.points ?? drag.initialAnnotation.measurementPoints
            if case .measurementPoint(let index) = drag.part, points.indices.contains(index) {
                let moved = CGPoint(x: points[index].x + dx, y: points[index].y + dy)
                let neighbour = points.count > 1 ? points[index == 0 ? 1 : index - 1] : nil
                let snapped = applySnapping(to: moved, fromPoint: neighbour, inPage: drag.pageIndex, modifierFlags: event.modifierFlags, excluding: drag.id)
                dx = snapped.x - points[index].x
                dy = snapped.y - points[index].y
            }
            activeAnnotationDrag?.currentDelta = CGSize(width: dx, height: dy)
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .redact {
            guard let dragPageIdx = currentRedactionPage,
                  let geometry = pageGeometry(for: dragPageIdx) else { return }
            let currentCanvas = convert(event.locationInWindow, from: nil)
            currentRedactionEnd = geometry.pagePoint(forCanvasPoint: currentCanvas)
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .shape {
            guard let dragPageIdx = currentShapePage,
                  let start = currentShapeStart,
                  let geometry = pageGeometry(for: dragPageIdx) else { return }
            let currentCanvas = convert(event.locationInWindow, from: nil)
            var end = geometry.pagePoint(forCanvasPoint: currentCanvas)
            // A cloud follows the path dragged.
            if viewModel.selectedShape == .cloud {
                currentShapePath.append(end)
            }
            // Shift makes a square or circle, or keeps a line to a multiple of 45°.
            if event.modifierFlags.contains(.shift), viewModel.selectedShape != .cloud {
                let dx = end.x - start.x
                let dy = end.y - start.y
                if viewModel.selectedShape.isBoxed {
                    let side = max(abs(dx), abs(dy))
                    end = CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
                } else {
                    let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
                    let length = hypot(dx, dy)
                    end = CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
                }
            }
            currentShapeEnd = end
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .callout {
            guard let dragPageIdx = currentCalloutPage,
                  let geometry = pageGeometry(for: dragPageIdx) else { return }
            let currentCanvas = convert(event.locationInWindow, from: nil)
            currentCalloutEnd = geometry.pagePoint(forCanvasPoint: currentCanvas)
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .draw {
            guard let dragPageIdx = currentDrawingPageIndex,
                  let geometry = pageGeometry(for: dragPageIdx) else { return }
            let currentCanvas = convert(event.locationInWindow, from: nil)
            let currentPagePoint = geometry.pagePoint(forCanvasPoint: currentCanvas)
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
              let geometry = pageGeometry(for: dragPageIdx) else { return }

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

        let startPagePoint = geometry.pagePoint(forCanvasPoint: startCanvas)

        let isOptionPressed = event.modifierFlags.contains(.option)
        let mode: SelectionMode = isOptionPressed ? .rectangularArea : viewModel.selectionMode

        // Text selection can span across page boundaries; marquee selection is constrained to a single page.
        if mode == .readingOrder,
           let (currentPageIdx, currentPagePoint) = nearestPageInfo(at: currentCanvas),
           currentPageIdx != dragPageIdx {
            viewModel.handleCrossPageDragSelect(pageA: dragPageIdx, pointA: startPagePoint, pageB: currentPageIdx, pointB: currentPagePoint)
            needsDisplay = true
            return
        }

        let currentPagePoint = geometry.pagePoint(forCanvasPoint: currentCanvas)

        viewModel.handleDragSelect(
            pageIndex: dragPageIdx,
            startPagePoint: startPagePoint,
            currentPagePoint: currentPagePoint,
            forceMode: mode
        )
        needsDisplay = true
    }
    
    public override func mouseUp(with event: NSEvent) {
        stopAutoscroll()
        if endGuideDrag(event) {
            return
        }
        if let drag = activeAnnotationDrag {
            activeAnnotationDrag = nil
            if drag.part == .entireAnnotation, !groupSelection.isEmpty, drag.currentDelta != .zero {
                // The rest of the group moves with it.
                let delta = drag.currentDelta
                forEachSelectedAnnotation { [self] in
                    guard let sel = selectedAnnotation,
                          let annot = viewModel.pageAnnotations[sel.pageIndex]?.first(where: { $0.id == sel.id }) else { return }
                    commitAnnotationEdit(annot, pageIndex: sel.pageIndex, part: .entireAnnotation, delta: delta)
                }
            } else {
                commitAnnotationEdit(drag.initialAnnotation, pageIndex: drag.pageIndex, part: drag.part, delta: drag.currentDelta)
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

        if viewModel.canvasMode == .shape {
            if let pIdx = currentShapePage, let start = currentShapeStart, let end = currentShapeEnd {
                let shape = viewModel.selectedShape
                let (width, height) = (abs(end.x - start.x), abs(end.y - start.y))
                let annot: PDFAnnotation?
                if shape == .cloud {
                    // Round the path dragged, or an oval across a straight drag; not a click.
                    let box = CGRect(enclosing: currentShapePath)
                    annot = box.width > 8 && box.height > 8
                        ? viewModel.addCloudAnnotation(pageIndex: pIdx, outline: CloudOutline.outline(for: currentShapePath), intensity: viewModel.selectedCloudArcSize.rawValue, color: viewModel.selectedAnnotationColor)
                        : nil
                } else {
                    // Big enough to have been meant, rather than a click.
                    let isBigEnough = shape.isBoxed ? width > 4 && height > 4 : hypot(width, height) > 4
                    annot = isBigEnough
                        ? viewModel.addShapeAnnotation(pageIndex: pIdx, shape: shape, from: start, to: end, strokeWidth: viewModel.drawStrokeWidth, lineEnding: viewModel.selectedShapeLineEnding, color: viewModel.selectedAnnotationColor)
                        : nil
                }
                if let annot {
                    selectedAnnotation = (id: annot.id, pageIndex: pIdx)
                }
            }
            currentShapePage = nil
            currentShapeStart = nil
            currentShapeEnd = nil
            currentShapePath = []
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
                        color: viewModel.selectedAnnotationColor,
                        lineEnding: viewModel.selectedLineEnding
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

        if viewModel.canvasMode == .placeSignatureField {
            if let page = currentMeasurePage, let start = currentMeasurePoints.first {
                let end = currentMeasureCandidatePoint ?? start
                if hypot(end.x - start.x, end.y - start.y) > 8 {
                    viewModel.placeCertificateSignature(page: page, in: CGRect(enclosing: [start, end]))
                } else {
                    viewModel.placeCertificateSignature(page: page, at: start)
                }
            }
            currentMeasurePage = nil
            currentMeasurePoints = []
            currentMeasureCandidatePoint = nil
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .measureRectangle || viewModel.canvasMode == .measureCircle {
            if let p0 = currentMeasurePoints.first, let p1 = currentMeasureCandidatePoint, hypot(p1.x - p0.x, p1.y - p0.y) > 4 {
                currentMeasurePoints = [p0, p1]
                commitCurrentShape(viewModel.canvasMode == .measureCircle ? .circle : .rectangle)
            }
            currentMeasurePage = nil
            currentMeasurePoints = []
            currentMeasureCandidatePoint = nil
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
                        color: viewModel.measurementColor,
                        strokeWidth: viewModel.measurementStrokeWidth
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

        // An area (⌥-drag) also selects the annotations entirely inside it.
        if wasDragged, viewModel.canvasMode == .select, let area = viewModel.activeSelection, area.result.mode == .rectangularArea {
            selectAnnotations(in: area.result.boundingRect, pageIndex: area.pageIndex)
        }

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
        updatePointerReadout(event)
        if viewModel.canvasMode == .select, guide(at: convert(event.locationInWindow, from: nil)) != nil {
            NSCursor.openHand.set()
            return
        }
        updateLinkPeek(modifierFlags: event.modifierFlags)
        if viewModel.canvasMode == .draw || viewModel.canvasMode == .eraser {
            if hoveredLink != nil {
                hoveredLink = nil
                needsDisplay = true
            }
            NSCursor.crosshair.set()
            return
        }
        if viewModel.canvasMode == .stamp || viewModel.canvasMode == .placeSignatureField {
            if hoveredLink != nil {
                hoveredLink = nil
            }
            currentHoverCanvasPoint = convert(event.locationInWindow, from: nil)
            NSCursor.crosshair.set()
            needsDisplay = true
            return
        }

        if let page = currentPolyPage, viewModel.canvasMode == .shape {
            let point = convert(event.locationInWindow, from: nil)
            if let (pageIdx, _, rawPagePoint) = pageInfo(at: point), pageIdx == page {
                currentPolyCandidate = applySnapping(to: rawPagePoint, fromPoint: currentPolyPoints.last, inPage: pageIdx, modifierFlags: event.modifierFlags)
                needsDisplay = true
            }
        }

        if viewModel.canvasMode.isMeasuring {

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

        // Select mode outlines what a click would pick up, once the pointer pauses.
        if viewModel.canvasMode == .select {
            scheduleHoverOutline(at: point)
            if let hover = hoverOutline, let (pageIdx, _, pagePoint) = pageInfo(at: point), hover.pageIndex == pageIdx,
               hover.rect.insetBy(dx: -6, dy: -6).contains(pagePoint), activeAnnotationDrag == nil {
                if hoveredLink != nil { hoveredLink = nil; needsDisplay = true }
                NSCursor.openHand.set()
                return
            }
        } else if hoverOutline != nil {
            hoverOutline = nil
            needsDisplay = true
        }

        // Hover feedback over annotations or callout handles in interactive modes
        if viewModel.canvasMode == .select || viewModel.canvasMode == .text || viewModel.canvasMode == .callout {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point),
               case let list = viewModel.shownAnnotations(onPage: pageIdx), !list.isEmpty {
                // If an annotation is selected on this page, check if hovering over its corner handles
                if let sel = selectedAnnotation, sel.pageIndex == pageIdx,
                   let selAnnot = list.first(where: { $0.id == sel.id }), selAnnot.isMeasurement,
                   case .measurementPoint = measurementDragPart(for: selAnnot, at: pagePoint) {
                    if hoveredLink != nil { hoveredLink = nil; needsDisplay = true }
                    NSCursor.crosshair.set()
                    return
                }
                if viewModel.canvasMode == .select, list.contains(where: { $0.isMeasurement && measurementHit($0, at: pagePoint) }) {
                    if hoveredLink != nil { hoveredLink = nil; needsDisplay = true }
                    NSCursor.openHand.set()
                    return
                }

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
        hoverWorkItem?.cancel()
        if hoverOutline != nil {
            hoverOutline = nil
            needsDisplay = true
        }
        updatePointerReadout(nil)
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

extension PDFCanvasView {
    /// Moves, resizes or reshapes an annotation as a drag of `part` by `delta` (in page
    /// coordinates) does, for a drag that ended and for an edit in the Inspector. Moves shorter
    /// than `minimumDistance` are taken as a click and change nothing.
    func commitAnnotationEdit(_ orig: PDFAnnotation, pageIndex pIdx: Int, part: DraggingAnnotationPart, delta: CGSize, minimumDistance: (measurement: CGFloat, other: CGFloat) = (0.5, 2.0)) {
        let dx = delta.width
        let dy = delta.height
        let dist = hypot(dx, dy)
        if dist > minimumDistance.measurement, orig.isMeasurement {
            let edited = editedMeasurement(orig, part: part, delta: delta)
            if let updated = viewModel.replaceMeasurement(orig, with: edited) {
                selectedAnnotation = (id: updated.id, pageIndex: pIdx)
            }
        } else if dist > minimumDistance.other, orig.isFromFile {
            commitFileAnnotationDrag(orig, part: part, delta: delta)
        } else if dist > minimumDistance.other {
            viewModel.beginReplacingAnnotation(orig)
            defer { viewModel.finishReplacingAnnotation() }

            if orig.type == .callout {
                var targetPt = orig.targetPoint ?? CGPoint(x: (orig.rect?.minX ?? 50) - 30, y: orig.rect?.midY ?? 50)
                var kneePt = orig.kneePoint ?? CGPoint(x: (orig.rect?.minX ?? 50) - 10, y: orig.rect?.midY ?? 50)
                var rect = orig.rect ?? CGRect(x: 50, y: 50, width: 80, height: 22)

                switch part {
                case .calloutTargetPoint:
                    targetPt = CGPoint(x: targetPt.x + dx, y: targetPt.y + dy)
                case .calloutKneePoint:
                    kneePt = CGPoint(x: kneePt.x + dx, y: kneePt.y + dy)
                case .calloutTextBox:
                    rect = rect.offsetBy(dx: dx, dy: dy)
                    kneePt = CGPoint(x: kneePt.x + dx, y: kneePt.y + dy)
                case .resizeTopLeft, .resizeTopRight, .resizeBottomLeft, .resizeBottomRight:
                    rect = updatedRect(from: rect, part: part, delta: delta)
                case .entireAnnotation:
                    targetPt = CGPoint(x: targetPt.x + dx, y: targetPt.y + dy)
                    kneePt = CGPoint(x: kneePt.x + dx, y: kneePt.y + dy)
                    rect = rect.offsetBy(dx: dx, dy: dy)
                case .lineStart, .lineEnd, .measurementPoint, .measurementLeader:
                    break
                }

                if let updated = viewModel.addCalloutAnnotation(
                    pageIndex: pIdx,
                    targetPoint: targetPt,
                    kneePoint: kneePt,
                    textBoxRect: rect,
                    text: orig.text,
                    fontSize: orig.fontSize ?? viewModel.selectedFontSize,
                    color: orig.color,
                    lineEnding: orig.lineEnding ?? .closedArrow
                ) {
                    selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                }
            } else if orig.type == .line {
                if let updated = viewModel.addRestyledShape(orig, ends: updatedLineEnds(of: orig, part: part, delta: delta)) {
                    selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                }
            } else if orig.type == .note || orig.isShape {
                let rect = updatedRect(from: orig.rect ?? .zero, part: part, delta: delta)
                if let updated = viewModel.addRestyled(orig, rect: rect, color: orig.color) {
                    selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                }
            } else if orig.type == .freeText {
                let rect = updatedRect(from: orig.rect ?? CGRect(x: 50, y: 50, width: 80, height: 22), part: part, delta: delta)
                if let updated = viewModel.addFreeTextAnnotation(
                    pageIndex: pIdx,
                    rect: rect,
                    text: orig.text,
                    fontSize: orig.fontSize ?? viewModel.selectedFontSize,
                    color: orig.color
                ) {
                    selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                }
            } else if orig.type == .ink {
                // A drawing moves as a whole.
                let moved = orig.inkPoints.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                if let updated = viewModel.addInkAnnotation(pageIndex: pIdx, points: moved, strokeWidth: orig.strokeWidth, color: orig.color) {
                    selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                }
            } else if orig.type == .stamp {
                let rect = updatedRect(from: orig.rect ?? CGRect(x: 50, y: 50, width: 140, height: 50), part: part, delta: delta)
                if let data = orig.stampImageData, let updated = viewModel.addStampAnnotation(pageIndex: pIdx, rect: rect, imageData: data, color: orig.color) {
                    selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                }
            }
        }
    }
}

extension PDFCanvasView {
    /// What a click at `pagePoint` picks up: an annotation made here (by its outline, for a shape),
    /// or one from the file, found as precisely as the document allows. With `pickingUp`, one
    /// from the file is picked up to be moved and changed; without, it's only described, for
    /// hover feedback.
    func annotationHit(pageIndex pageIdx: Int, at pagePoint: CGPoint, list: [PDFAnnotation]? = nil, pickingUp: Bool) -> PDFAnnotation? {
        let list = list ?? viewModel.shownAnnotations(onPage: pageIdx)
        let fileHit = viewModel.document?.annotationObjectNumber(pageIndex: pageIdx, at: pagePoint)
        if let shown = list.reversed().first(where: { annot in
            if annot.isFromFile { return annot.documentObjectNumber == fileHit }
            if annot.isMeasurement { return viewModel.canvasMode == .select && measurementHit(annot, at: pagePoint) }
            // A drawing only with Select: in the other tools a click on one starts something new.
            if annot.type == .ink { return viewModel.canvasMode == .select && annot.contains(pagePoint: pagePoint, tolerance: 6.0) }
            return (annot.type == .callout || annot.type == .freeText || annot.type == .stamp || annot.type == .note || annot.isShape) && annot.contains(pagePoint: pagePoint, tolerance: 6.0)
        }) {
            return shown
        }
        guard let fileHit, list.contains(where: { $0.documentObjectNumber == fileHit }) == false else { return nil }
        // A measurement that was in the file when it was opened is picked up to change it.
        if viewModel.canvasMode == .select, let measurement = viewModel.fileMeasurement(pageIndex: pageIdx, objectNumber: fileHit) {
            guard measurementHit(measurement, at: pagePoint) else { return nil }
            return pickingUp ? viewModel.pickUpMeasurement(measurement) : measurement
        }
        return pickingUp ? viewModel.pickUpFileAnnotation(pageIndex: pageIdx, objectNumber: fileHit) : viewModel.describedFileAnnotation(pageIndex: pageIdx, objectNumber: fileHit)
    }

    /// Works out, 60 ms after the pointer stops, what a click there would pick up, and outlines it.
    /// Annotations from the file are found by asking the document, so not on every move.
    func scheduleHoverOutline(at canvasPoint: CGPoint) {
        hoverWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.hasLiveViewModel, self.viewModel.canvasMode == .select,
                  self.activeAnnotationDrag == nil, !self.isDraggingSelection else { return }
            var outline: (pageIndex: Int, rect: CGRect)?
            if let (pageIdx, _, pagePoint) = self.pageInfo(at: canvasPoint),
               let hit = self.annotationHit(pageIndex: pageIdx, at: pagePoint, pickingUp: false) {
                let box = hit.type == .measureCount || !hit.isMeasurement ? hit.boundingRect : CGRect(enclosing: hit.measurementPoints).insetBy(dx: -4, dy: -4)
                outline = (pageIdx, box)
            }
            let changed = outline?.pageIndex != self.hoverOutline?.pageIndex || outline?.rect != self.hoverOutline?.rect
            self.hoverOutline = outline
            if changed {
                if outline != nil { NSCursor.openHand.set() }
                self.needsDisplay = true
            }
        }
        hoverWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: item)
    }
}

