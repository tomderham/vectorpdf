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
    // MARK: - Inline Text Box Editing & Resizing Helpers

    internal func hitTestResizeHandle(for rect: CGRect, on pageIndex: Int, canvasPoint: CGPoint) -> DraggingAnnotationPart? {
        guard let pFrame = pageFrame(for: pageIndex), let doc = viewModel.document else { return nil }
        let pBounds = doc.pageBounds[pageIndex]
        let rx = pFrame.minX + (rect.minX - pBounds.minX) * viewModel.effectiveZoom
        let ry = pFrame.minY + (rect.minY - pBounds.minY) * viewModel.effectiveZoom
        let rw = max(rect.width * viewModel.effectiveZoom, 24)
        let rh = max(rect.height * viewModel.effectiveZoom, 16)
        let boxRect = NSRect(x: rx, y: ry, width: rw, height: rh).insetBy(dx: -2.5, dy: -2.5)

        let handleRadius: CGFloat = 8.0
        let bl = CGPoint(x: boxRect.minX, y: boxRect.minY)
        let br = CGPoint(x: boxRect.maxX, y: boxRect.minY)
        let tl = CGPoint(x: boxRect.minX, y: boxRect.maxY)
        let tr = CGPoint(x: boxRect.maxX, y: boxRect.maxY)

        if hypot(canvasPoint.x - bl.x, canvasPoint.y - bl.y) <= handleRadius {
            return .resizeBottomLeft
        }
        if hypot(canvasPoint.x - br.x, canvasPoint.y - br.y) <= handleRadius {
            return .resizeBottomRight
        }
        if hypot(canvasPoint.x - tl.x, canvasPoint.y - tl.y) <= handleRadius {
            return .resizeTopLeft
        }
        if hypot(canvasPoint.x - tr.x, canvasPoint.y - tr.y) <= handleRadius {
            return .resizeTopRight
        }
        return nil
    }

    internal func updatedRect(from origRect: CGRect, part: DraggingAnnotationPart, delta: CGSize) -> CGRect {
        let dx = delta.width
        let dy = delta.height
        let minW: CGFloat = 24.0
        let minH: CGFloat = 16.0

        var x0 = origRect.minX
        var y0 = origRect.minY
        var x1 = origRect.maxX
        var y1 = origRect.maxY

        switch part {
        case .entireAnnotation, .calloutTextBox:
            return origRect.offsetBy(dx: dx, dy: dy)
        case .resizeBottomLeft:
            x0 = min(origRect.maxX - minW, origRect.minX + dx)
            y0 = min(origRect.maxY - minH, origRect.minY + dy)
        case .resizeBottomRight:
            x1 = max(origRect.minX + minW, origRect.maxX + dx)
            y0 = min(origRect.maxY - minH, origRect.minY + dy)
        case .resizeTopLeft:
            x0 = min(origRect.maxX - minW, origRect.minX + dx)
            y1 = max(origRect.minY + minH, origRect.maxY + dy)
        case .resizeTopRight:
            x1 = max(origRect.minX + minW, origRect.maxX + dx)
            y1 = max(origRect.minY + minH, origRect.maxY + dy)
        default:
            return origRect
        }

        return CGRect(x: x0, y: y0, width: max(x1 - x0, minW), height: max(y1 - y0, minH))
    }

    /// The ends of `line` after dragging `part` by `delta`: one end, or the whole line.
    internal func updatedLineEnds(of line: PDFAnnotation, part: DraggingAnnotationPart, delta: CGSize) -> [CGPoint] {
        let ends = line.inkPoints
        guard ends.count >= 2 else { return ends }
        func moved(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + delta.width, y: p.y + delta.height) }
        switch part {
        case .lineStart: return [moved(ends[0]), ends[1]]
        case .lineEnd: return [ends[0], moved(ends[1])]
        default: return ends.map(moved)
        }
    }

    /// Which end of `line` is under `pagePoint`, for dragging it, or the whole line.
    internal func lineDragPart(for line: PDFAnnotation, at pagePoint: CGPoint) -> DraggingAnnotationPart {
        let reach = 8.0 / max(viewModel.effectiveZoom, 0.01)
        if let end = line.inkPoints.last, hypot(pagePoint.x - end.x, pagePoint.y - end.y) <= reach { return .lineEnd }
        if let start = line.inkPoints.first, hypot(pagePoint.x - start.x, pagePoint.y - start.y) <= reach { return .lineStart }
        return .entireAnnotation
    }

    /// Applies a drag of an annotation from the file: moved, it keeps its own appearance;
    /// resized, or with a line's end moved, MuPDF draws it again.
    func commitFileAnnotationDrag(_ annot: PDFAnnotation, part: DraggingAnnotationPart, delta: CGSize) {
        let page = annot.pageIndex
        let updated: PDFAnnotation?
        switch part {
        case .lineStart, .lineEnd:
            let ends = updatedLineEnds(of: annot, part: part, delta: delta)
            updated = viewModel.editFileAnnotation(annot) { try $0.restyleAnnotation(pageIndex: page, objectNumber: $1, points: ends) }
        case .resizeTopLeft, .resizeTopRight, .resizeBottomLeft, .resizeBottomRight:
            guard annot.isResizableFromFile, let rect = annot.rect else { return }
            let resized = updatedRect(from: rect, part: part, delta: delta)
            if annot.inkPoints.count >= 3 {
                let corners = annot.inkPoints(fittedTo: resized)
                updated = viewModel.editFileAnnotation(annot) { try $0.restyleAnnotation(pageIndex: page, objectNumber: $1, points: corners) }
            } else {
                updated = viewModel.editFileAnnotation(annot) { try $0.restyleAnnotation(pageIndex: page, objectNumber: $1, rect: resized) }
            }
        default:
            updated = viewModel.editFileAnnotation(annot) { try $0.moveAnnotation(pageIndex: page, objectNumber: $1, by: delta) }
        }
        if let updated {
            selectedAnnotation = (id: updated.id, pageIndex: page)
        }
    }

    /// Gives the selected rectangle, oval or line the line width or line ending just chosen in
    /// the toolbar.
    func restyleSelectedShape(strokeWidth: CGFloat? = nil, lineEnding: PDFLineEnding? = nil) {
        guard activeInlineTextField == nil,
              let (targetId, pIdx) = selectedAnnotation,
              let annot = viewModel.pageAnnotations[pIdx]?.first(where: { $0.id == targetId }),
              annot.type == .square || annot.type == .circle || annot.type == .line || (annot.isFromFile && annot.type == .cloud) else { return }
        let widthChanges = strokeWidth.map { $0 != annot.strokeWidth } ?? false
        let endingChanges = annot.type == .line && (lineEnding.map { $0 != annot.lineEnding } ?? false)
        guard widthChanges || endingChanges else { return }
        if annot.isFromFile {
            viewModel.editFileAnnotation(annot) {
                try $0.restyleAnnotation(pageIndex: pIdx, objectNumber: $1, borderWidth: widthChanges ? strokeWidth : nil, lineEnding: endingChanges ? lineEnding : nil)
            }
            needsDisplay = true
            return
        }
        viewModel.beginReplacingAnnotation(annot)
        defer { viewModel.finishReplacingAnnotation() }
        if let updated = viewModel.addRestyledShape(annot, strokeWidth: widthChanges ? strokeWidth : nil, lineEnding: endingChanges ? lineEnding : nil) {
            selectedAnnotation = (id: updated.id, pageIndex: pIdx)
        }
        needsDisplay = true
    }

    internal func computeTextBoxSize(text: String, fontSize: CGFloat, maxWidth: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let str = (text.isEmpty ? "Note" : text) as NSString
        let bounding = str.boundingRect(
            with: CGSize(width: max(maxWidth, 60), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        // Snug padding: 4 pt each side (8 pt total), 2 pt vertical (4 pt total)
        let w = max(ceil(bounding.width) + 8.0, 24.0)
        let h = max(ceil(bounding.height) + 4.0, ceil(fontSize * 1.25))
        return CGSize(width: w, height: h)
    }

    func commitActiveInlineTextField() {
        guard !isCommittingInlineText else { return }
        isCommittingInlineText = true
        defer { isCommittingInlineText = false }

        guard let tf = activeInlineTextField,
              let pIdx = activeEditingPageIndex,
              let doc = viewModel.document,
              pIdx >= 0, pIdx < doc.pageCount else {
            if let tf = activeInlineTextField {
                tf.delegate = nil
                tf.removeFromSuperview()
            }
            activeInlineTextField = nil
            activeEditingAnnotation = nil
            activeEditingPageIndex = nil
            activeEditingPagePoint = nil
            if viewModel.canvasMode == .text {
                viewModel.canvasMode = .select
            }
            needsDisplay = true
            return
        }
        let text = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = viewModel.selectedAnnotationColor
        let fontSize = viewModel.selectedFontSize
        let pBounds = doc.pageBounds[pIdx]

        if let existing = activeEditingAnnotation {
            if text.isEmpty {
                viewModel.removeAnnotation(existing)
                if selectedAnnotation?.id == existing.id {
                    selectedAnnotation = nil
                }
            } else if text != existing.text || color != existing.color || fontSize != (existing.fontSize ?? 13.0) {
                viewModel.beginReplacingAnnotation(existing)
                defer { viewModel.finishReplacingAnnotation() }
                if existing.type == .callout {
                    let r = existing.rect ?? CGRect(x: 50, y: 50, width: 80, height: 22)
                    let tp = existing.targetPoint ?? CGPoint(x: r.minX - 30, y: r.midY)
                    let kp = existing.kneePoint ?? CGPoint(x: r.minX - 10, y: r.midY)
                    let availableW = max(pBounds.maxX - r.minX, 60)
                    let neededSize = computeTextBoxSize(text: text, fontSize: fontSize, maxWidth: availableW)
                    let updatedRect = CGRect(x: r.minX, y: r.minY, width: neededSize.width, height: neededSize.height)
                    if let updated = viewModel.addCalloutAnnotation(
                        pageIndex: pIdx,
                        targetPoint: tp,
                        kneePoint: kp,
                        textBoxRect: updatedRect,
                        text: text,
                        fontSize: fontSize,
                        color: color,
                        lineEnding: existing.lineEnding ?? .closedArrow
                    ) {
                        selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                    }
                } else {
                    let r = existing.rect ?? CGRect(x: 50, y: 50, width: 80, height: 22)
                    let availableW = max(pBounds.maxX - r.minX, 60)
                    let neededSize = computeTextBoxSize(text: text, fontSize: fontSize, maxWidth: availableW)
                    let updatedRect = CGRect(x: r.minX, y: r.minY, width: neededSize.width, height: neededSize.height)
                    if let updated = viewModel.addFreeTextAnnotation(pageIndex: pIdx, rect: updatedRect, text: text, fontSize: fontSize, color: color) {
                        selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                    }
                }
            } else {
                selectedAnnotation = (id: existing.id, pageIndex: pIdx)
            }
        } else if !text.isEmpty, let pagePt = activeEditingPagePoint {
            let availableW = max(pBounds.maxX - pagePt.x, 60)
            let neededSize = computeTextBoxSize(text: text, fontSize: fontSize, maxWidth: availableW)
            let r = CGRect(x: pagePt.x, y: pagePt.y, width: neededSize.width, height: neededSize.height)
            if let updated = viewModel.addFreeTextAnnotation(pageIndex: pIdx, rect: r, text: text, fontSize: fontSize, color: color) {
                selectedAnnotation = (id: updated.id, pageIndex: pIdx)
            }
        }

        tf.delegate = nil
        tf.removeFromSuperview()
        activeInlineTextField = nil
        activeEditingAnnotation = nil
        activeEditingPageIndex = nil
        activeEditingPagePoint = nil

        // Automatically revert to select mode so dragging doesn't create duplicate boxes
        if viewModel.canvasMode == .text {
            viewModel.canvasMode = .select
        }

        needsDisplay = true
    }

    private func cancelActiveInlineTextField() {
        if activeEditingAnnotation == nil {
            selectedAnnotation = nil
        }
        if let tf = activeInlineTextField {
            tf.delegate = nil
            tf.removeFromSuperview()
        }
        activeInlineTextField = nil
        activeEditingAnnotation = nil
        activeEditingPageIndex = nil
        activeEditingPagePoint = nil
        if viewModel.canvasMode == .text {
            viewModel.canvasMode = .select
        }
        needsDisplay = true
    }

    func calloutDragPart(for annotation: PDFAnnotation, at pagePoint: CGPoint) -> DraggingAnnotationPart {
        guard annotation.type == .callout else { return .entireAnnotation }
        if let tp = annotation.targetPoint, hypot(tp.x - pagePoint.x, tp.y - pagePoint.y) <= 12 {
            return .calloutTargetPoint
        }
        if let kp = annotation.kneePoint, hypot(kp.x - pagePoint.x, kp.y - pagePoint.y) <= 10 {
            return .calloutKneePoint
        }
        if let r = annotation.rect, r.insetBy(dx: -4, dy: -4).contains(pagePoint) {
            return .calloutTextBox
        }
        return .entireAnnotation
    }

    func deleteSelectedAnnotation() {
        guard let sel = selectedAnnotation,
              let list = viewModel.pageAnnotations[sel.pageIndex],
              let annot = list.first(where: { $0.id == sel.id }) else {
            selectedAnnotation = nil
            return
        }
        viewModel.removeAnnotation(annot)
        selectedAnnotation = nil
        needsDisplay = true
    }

    func nudgeSelectedAnnotation(dx: CGFloat, dy: CGFloat) {
        guard let sel = selectedAnnotation,
              let list = viewModel.pageAnnotations[sel.pageIndex],
              let orig = list.first(where: { $0.id == sel.id }) else { return }
        // Only kinds that can be re-created below may be removed — anything else (a measurement,
        // ink, a text markup) would simply be deleted by an arrow key.
        if orig.isFromFile {
            viewModel.editFileAnnotation(orig) { try $0.moveAnnotation(pageIndex: sel.pageIndex, objectNumber: $1, by: CGSize(width: dx, height: dy)) }
            needsDisplay = true
            return
        }
        guard orig.type == .callout || orig.type == .freeText || orig.type == .note || orig.isShape || (orig.type == .stamp && orig.stampImageData != nil) else { return }
        viewModel.beginReplacingAnnotation(orig)
        defer { viewModel.finishReplacingAnnotation() }
        if orig.type == .callout {
            let targetPt = orig.targetPoint.map { CGPoint(x: $0.x + dx, y: $0.y + dy) } ?? .zero
            let kneePt = orig.kneePoint.map { CGPoint(x: $0.x + dx, y: $0.y + dy) } ?? .zero
            let rect = (orig.rect ?? .zero).offsetBy(dx: dx, dy: dy)
            if let updated = viewModel.addCalloutAnnotation(
                pageIndex: sel.pageIndex,
                targetPoint: targetPt,
                kneePoint: kneePt,
                textBoxRect: rect,
                text: orig.text,
                fontSize: orig.fontSize ?? viewModel.selectedFontSize,
                color: orig.color,
                lineEnding: orig.lineEnding ?? .closedArrow
            ) {
                selectedAnnotation = (id: updated.id, pageIndex: sel.pageIndex)
            }
        } else if orig.type == .note || orig.isShape {
            let rect = (orig.rect ?? .zero).offsetBy(dx: dx, dy: dy)
            if let updated = viewModel.addRestyled(orig, rect: rect, color: orig.color) {
                selectedAnnotation = (id: updated.id, pageIndex: sel.pageIndex)
            }
        } else if orig.type == .freeText {
            let rect = (orig.rect ?? .zero).offsetBy(dx: dx, dy: dy)
            if let updated = viewModel.addFreeTextAnnotation(
                pageIndex: sel.pageIndex,
                rect: rect,
                text: orig.text,
                fontSize: orig.fontSize ?? viewModel.selectedFontSize,
                color: orig.color
            ) {
                selectedAnnotation = (id: updated.id, pageIndex: sel.pageIndex)
            }
        } else if orig.type == .stamp {
            let rect = (orig.rect ?? .zero).offsetBy(dx: dx, dy: dy)
            if let data = orig.stampImageData, let updated = viewModel.addStampAnnotation(pageIndex: sel.pageIndex, rect: rect, imageData: data, color: orig.color) {
                selectedAnnotation = (id: updated.id, pageIndex: sel.pageIndex)
            }
        }
        needsDisplay = true
    }

    func startInlineEditing(annotation: PDFAnnotation, pageIndex: Int) {
        commitActiveInlineTextField()
        guard let pFrame = pageFrame(for: pageIndex),
              let doc = viewModel.document,
              let rect = annotation.rect else { return }

        selectedAnnotation = (id: annotation.id, pageIndex: pageIndex)
        if let fs = annotation.fontSize {
            viewModel.selectedFontSize = fs
        }
        if annotation.color != viewModel.selectedAnnotationColor {
            viewModel.selectedAnnotationColor = annotation.color
        }

        let pBounds = doc.pageBounds[pageIndex]
        let canvasX = pFrame.minX + (rect.minX - pBounds.minX) * viewModel.effectiveZoom
        let canvasY = pFrame.minY + (rect.minY - pBounds.minY) * viewModel.effectiveZoom
        let canvasW = max(rect.width * viewModel.effectiveZoom, 60)
        let canvasH = max(rect.height * viewModel.effectiveZoom, 22)

        let tf = NSTextField(frame: NSRect(x: canvasX, y: canvasY, width: canvasW, height: canvasH))
        tf.stringValue = annotation.text
        let fSize = max((annotation.fontSize ?? viewModel.selectedFontSize) * viewModel.effectiveZoom, 10.0)
        tf.font = NSFont.systemFont(ofSize: fSize)
        tf.textColor = annotation.color.nsColor
        tf.backgroundColor = isDarkMode ? NSColor.windowBackgroundColor : NSColor.white
        tf.drawsBackground = true
        tf.isBordered = true
        tf.focusRingType = .exterior
        tf.isEditable = true
        tf.isSelectable = true
        tf.cell?.wraps = true
        tf.cell?.isScrollable = false
        tf.maximumNumberOfLines = 0
        tf.delegate = self
        addSubview(tf)
        window?.makeFirstResponder(tf)
        tf.selectText(nil)

        activeInlineTextField = tf
        activeEditingAnnotation = annotation
        activeEditingPageIndex = pageIndex
        activeEditingPagePoint = rect.origin
        needsDisplay = true
    }

    func startInlineEditing(newAt pagePoint: CGPoint, pageIndex: Int) {
        commitActiveInlineTextField()
        guard let pFrame = pageFrame(for: pageIndex),
              let doc = viewModel.document else { return }

        let pBounds = doc.pageBounds[pageIndex]
        let canvasX = pFrame.minX + (pagePoint.x - pBounds.minX) * viewModel.effectiveZoom
        let canvasY = pFrame.minY + (pagePoint.y - pBounds.minY) * viewModel.effectiveZoom
        let canvasW: CGFloat = 120
        let canvasH = max(viewModel.selectedFontSize * viewModel.effectiveZoom * 1.3 + 8, 24)

        let tf = NSTextField(frame: NSRect(x: canvasX, y: canvasY, width: canvasW, height: canvasH))
        tf.placeholderString = "Type text..."
        tf.font = NSFont.systemFont(ofSize: max(viewModel.selectedFontSize * viewModel.effectiveZoom, 10.0))
        tf.textColor = viewModel.selectedAnnotationColor.nsColor
        tf.backgroundColor = isDarkMode ? NSColor.windowBackgroundColor : NSColor.white
        tf.drawsBackground = true
        tf.isBordered = true
        tf.focusRingType = .exterior
        tf.isEditable = true
        tf.isSelectable = true
        tf.cell?.wraps = true
        tf.cell?.isScrollable = false
        tf.maximumNumberOfLines = 0
        tf.delegate = self
        addSubview(tf)
        window?.makeFirstResponder(tf)
        tf.selectText(nil)

        activeInlineTextField = tf
        activeEditingAnnotation = nil
        activeEditingPageIndex = pageIndex
        activeEditingPagePoint = pagePoint
        needsDisplay = true
    }

    func handleFontSizeChanged(_ newSize: CGFloat) {
        guard let doc = viewModel.document else { return }

        // 1. If an active inline text field is currently open and editing, resize it live in real time
        if let tf = activeInlineTextField, let pIdx = activeEditingPageIndex {
            let fSize = max(newSize * viewModel.effectiveZoom, 10.0)
            tf.font = NSFont.systemFont(ofSize: fSize)

            let str = tf.stringValue.isEmpty ? (tf.placeholderString ?? "Note") : tf.stringValue
            let pBounds = doc.pageBounds[pIdx]
            let availableWidth = max((pBounds.maxX - (activeEditingPagePoint?.x ?? pBounds.minX)) * viewModel.effectiveZoom, 80)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fSize)]
            let bounding = (str as NSString).boundingRect(
                with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            let approxW = max(ceil(bounding.width) + 16, 60)
            let approxH = max(ceil(bounding.height) + 10, 24)
            tf.frame = NSRect(x: tf.frame.minX, y: tf.frame.minY, width: approxW, height: approxH)

            needsDisplay = true
        }

        // 2. If an annotation was recently edited/selected (and no active inline text field is open),
        // update its font size and bounding geometry immediately without waiting for click-away
        if activeInlineTextField == nil,
           let (targetId, pIdx) = selectedAnnotation,
           pIdx >= 0, pIdx < doc.pageCount,
           let list = viewModel.pageAnnotations[pIdx],
           let annot = list.first(where: { $0.id == targetId }),
           (annot.type == .callout || annot.type == .freeText), !annot.isFromFile,
           annot.fontSize != newSize {

            viewModel.beginReplacingAnnotation(annot)
            defer { viewModel.finishReplacingAnnotation() }
            let text = annot.text
            let color = annot.color
            let fontSize = newSize
            let pBounds = doc.pageBounds[pIdx]

            if annot.type == .callout {
                let r = annot.rect ?? CGRect(x: 50, y: 50, width: 80, height: 22)
                let tp = annot.targetPoint ?? CGPoint(x: r.minX - 30, y: r.midY)
                let kp = annot.kneePoint ?? CGPoint(x: r.minX - 10, y: r.midY)
                let availableW = max(pBounds.maxX - r.minX, 60)
                let neededSize = computeTextBoxSize(text: text, fontSize: fontSize, maxWidth: availableW)
                let updatedRect = CGRect(x: r.minX, y: r.minY, width: neededSize.width, height: neededSize.height)
                if let updated = viewModel.addCalloutAnnotation(
                    pageIndex: pIdx,
                    targetPoint: tp,
                    kneePoint: kp,
                    textBoxRect: updatedRect,
                    text: text,
                    fontSize: fontSize,
                    color: color,
                    lineEnding: annot.lineEnding ?? .closedArrow
                ) {
                    selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                }
            } else {
                let r = annot.rect ?? CGRect(x: 50, y: 50, width: 80, height: 22)
                let availableW = max(pBounds.maxX - r.minX, 60)
                let neededSize = computeTextBoxSize(text: text, fontSize: fontSize, maxWidth: availableW)
                let updatedRect = CGRect(x: r.minX, y: r.minY, width: neededSize.width, height: neededSize.height)
                if let updated = viewModel.addFreeTextAnnotation(pageIndex: pIdx, rect: updatedRect, text: text, fontSize: fontSize, color: color) {
                    selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                }
            }
            needsDisplay = true
        }
    }

    func handleAnnotationColorChanged(_ newColor: AnnotationColor) {
        guard let doc = viewModel.document else { return }

        if let tf = activeInlineTextField {
            tf.textColor = newColor.nsColor
            needsDisplay = true
        }

        if activeInlineTextField == nil,
           let (targetId, pIdx) = selectedAnnotation,
           pIdx >= 0, pIdx < doc.pageCount,
           let list = viewModel.pageAnnotations[pIdx],
           let annot = list.first(where: { $0.id == targetId }),
           (annot.type == .callout || annot.type == .freeText || annot.type == .stamp || annot.type == .note || annot.isShape || annot.isFromFile) {

            guard annot.color != newColor else { return }
            if annot.isFromFile {
                // Text boxes and stamps keep the colors their app drew them in.
                if annot.type != .freeText && annot.type != .stamp {
                    viewModel.editFileAnnotation(annot) { try $0.restyleAnnotation(pageIndex: pIdx, objectNumber: $1, color: newColor) }
                    needsDisplay = true
                }
                return
            }
            viewModel.beginReplacingAnnotation(annot)
            defer { viewModel.finishReplacingAnnotation() }
            let text = annot.text
            let fontSize = annot.fontSize ?? viewModel.selectedFontSize

            if annot.type == .callout {
                let r = annot.rect ?? CGRect(x: 50, y: 50, width: 80, height: 22)
                let tp = annot.targetPoint ?? CGPoint(x: r.minX - 30, y: r.midY)
                let kp = annot.kneePoint ?? CGPoint(x: r.minX - 10, y: r.midY)
                if let updated = viewModel.addCalloutAnnotation(
                    pageIndex: pIdx,
                    targetPoint: tp,
                    kneePoint: kp,
                    textBoxRect: r,
                    text: text,
                    fontSize: fontSize,
                    color: newColor,
                    lineEnding: annot.lineEnding ?? .closedArrow
                ) {
                    selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                }
            } else if annot.type == .note || annot.isShape, let r = annot.rect {
                if let updated = viewModel.addRestyled(annot, rect: r, color: newColor) {
                    selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                }
            } else if annot.type == .freeText {
                let r = annot.rect ?? CGRect(x: 50, y: 50, width: 80, height: 22)
                if let updated = viewModel.addFreeTextAnnotation(pageIndex: pIdx, rect: r, text: text, fontSize: fontSize, color: newColor) {
                    selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                }
            } else if annot.type == .stamp, let origData = annot.stampImageData, let origImg = NSImage(data: origData), let r = annot.rect {
                let tintedImg = origImg.tinted(with: newColor.nsColor)
                if let tintedData = tintedImg.pdfStampPNGData,
                   let updated = viewModel.addStampAnnotation(pageIndex: pIdx, rect: r, imageData: tintedData, color: newColor) {
                    selectedAnnotation = (id: updated.id, pageIndex: pIdx)
                }
            }
            needsDisplay = true
        }
    }

    // MARK: - NSTextFieldDelegate

    public func controlTextDidChange(_ obj: Notification) {
        guard let tf = activeInlineTextField,
              let pIdx = activeEditingPageIndex,
              let doc = viewModel.document else { return }
        let pBounds = doc.pageBounds[pIdx]
        let font = tf.font ?? NSFont.systemFont(ofSize: 13.0)
        let str = tf.stringValue.isEmpty ? (tf.placeholderString ?? "Note") : tf.stringValue
        let availableWidth = max((pBounds.maxX - (activeEditingPagePoint?.x ?? pBounds.minX)) * viewModel.effectiveZoom, 80)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let bounding = (str as NSString).boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let approxW = max(ceil(bounding.width) + 16, 60)
        let approxH = max(ceil(bounding.height) + 10, 24)
        tf.frame = NSRect(x: tf.frame.minX, y: tf.frame.minY, width: approxW, height: approxH)
        needsDisplay = true
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        commitActiveInlineTextField()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            if flags.contains(.shift) || flags.contains(.option) {
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            } else {
                commitActiveInlineTextField()
                return true
            }
        } else if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            textView.insertText("\n", replacementRange: textView.selectedRange())
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelActiveInlineTextField()
            return true
        }
        return false
    }
}
