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
    // MARK: - Annotations

    @discardableResult
    public func addTextMarkupSelection(type: PDFAnnotationType, color: AnnotationColor = .yellow) -> [PDFAnnotation] {
        guard let sel = activeSelection, !sel.result.highlightQuads.isEmpty, let doc = document else { return [] }
        var created: [PDFAnnotation] = []

        let pIdx = sel.pageIndex
        let quads = sel.result.highlightQuads
        let text = sel.result.text
        let annot = PDFAnnotation(pageIndex: pIdx, type: type, quads: quads, color: color, text: text)
        do {
            try doc.addTextMarkup(pageIndex: pIdx, type: type, quads: quads, red: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue)
            created.append(recordAddedAnnotation(annot))
        } catch {
            print("Failed to add \(type) on page \(pIdx): \(error)")
        }

        for extra in additionalSelectionPages {
            let epIdx = extra.pageIndex
            let eQuads = extra.result.highlightQuads
            guard !eQuads.isEmpty else { continue }
            let eText = extra.result.text
            let eAnnot = PDFAnnotation(pageIndex: epIdx, type: type, quads: eQuads, color: color, text: eText)
            do {
                try doc.addTextMarkup(pageIndex: epIdx, type: type, quads: eQuads, red: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue)
                created.append(recordAddedAnnotation(eAnnot))
            } catch {
                print("Failed to add \(type) on page \(epIdx): \(error)")
            }
        }

        if !created.isEmpty {
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            clearSelection()
        }
        return created
    }

    @discardableResult
    public func highlightSelection(color: AnnotationColor = .yellow) -> [PDFAnnotation] {
        return addTextMarkupSelection(type: .highlight, color: color)
    }

    @discardableResult
    public func underlineSelection(color: AnnotationColor = .yellow) -> [PDFAnnotation] {
        return addTextMarkupSelection(type: .underline, color: color)
    }

    @discardableResult
    public func strikethroughSelection(color: AnnotationColor = .yellow) -> [PDFAnnotation] {
        return addTextMarkupSelection(type: .strikeout, color: color)
    }

    @discardableResult
    public func addInkAnnotation(pageIndex: Int, points: [CGPoint], strokeWidth: CGFloat = 2.5, color: AnnotationColor = .yellow) -> PDFAnnotation? {
        guard !points.isEmpty, let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return nil }
        let annot = PDFAnnotation(pageIndex: pageIndex, type: .ink, inkPoints: points, strokeWidth: strokeWidth, color: color)
        do {
            try doc.addInkStroke(pageIndex: pageIndex, points: points, strokeWidth: strokeWidth, red: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue)
            let stored = recordAddedAnnotation(annot)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            return stored
        } catch {
            print("Failed to add ink annotation on page \(pageIndex): \(error)")
            return nil
        }
    }

    @discardableResult
    public func addFreeTextAnnotation(pageIndex: Int, rect: CGRect, text: String, fontSize: CGFloat = 13.0, color: AnnotationColor = .black) -> PDFAnnotation? {
        guard !text.isEmpty, let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return nil }
        let annot = PDFAnnotation(pageIndex: pageIndex, type: .freeText, rect: rect, fontSize: fontSize, color: color, text: text)
        do {
            try doc.addFreeText(pageIndex: pageIndex, rect: rect, text: text, fontSize: fontSize, red: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue)
            let stored = recordAddedAnnotation(annot)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            return stored
        } catch {
            print("Failed to add free text annotation on page \(pageIndex): \(error)")
            return nil
        }
    }

    @discardableResult
    public func addStampAnnotation(pageIndex: Int, rect: CGRect, imageData: Data, color: AnnotationColor = .black) -> PDFAnnotation? {
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return nil }
        let pageTopY = doc.pageBounds[pageIndex].maxY
        let nativeRect = CGRect(x: rect.minX, y: pageTopY - rect.maxY, width: rect.width, height: rect.height)
        let annot = PDFAnnotation(pageIndex: pageIndex, type: .stamp, rect: rect, color: color, stampImageData: imageData)
        do {
            try doc.stampImage(pageIndex: pageIndex, rect: nativeRect, imageData: imageData)
            let stored = recordAddedAnnotation(annot)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            return stored
        } catch {
            print("Failed to add stamp annotation on page \(pageIndex): \(error)")
            return nil
        }
    }

    /// Adds an annotation that was just written to the document to the on-screen overlay, tagged
    /// with the PDF object it became so later edits and deletes touch only that annotation.
    func recordAddedAnnotation(_ annot: PDFAnnotation) -> PDFAnnotation {
        var stored = annot
        stored.documentObjectNumber = document?.lastAnnotationObjectNumber(pageIndex: annot.pageIndex)
        if let objectNumber = stored.documentObjectNumber {
            try? document?.setAnnotationAuthor(pageIndex: annot.pageIndex, objectNumber: objectNumber, author: Self.annotationAuthor)
            if let old = annotationBeingReplaced?.documentObjectNumber {
                try? document?.moveAnnotationThread(pageIndex: annot.pageIndex, from: old, to: objectNumber)
            }
        }
        pageAnnotations[annot.pageIndex, default: []].append(stored)
        noteAnnotationsChanged(onPage: annot.pageIndex)
        if annotationBeingReplaced != nil {
            // finishReplacingAnnotation registers the undo for the whole change.
            annotationReplacement = stored
        } else {
            undoManager.registerUndo(withTarget: self) { $0.removeAnnotation(stored) }
            nameUndoAction("Add Annotation")
        }
        return stored
    }

    /// Editing, moving or restyling an annotation writes a new PDF object. Call this instead of
    /// `removeAnnotation` before adding the replacement, then `finishReplacingAnnotation` after: the
    /// old object stays until then so its author, date and replies can move to the new one.
    func beginReplacingAnnotation(_ annotation: PDFAnnotation) {
        // Without an object number the old one can only be found by position, where the
        // replacement would be too, so it has to go first.
        guard annotation.documentObjectNumber != nil else {
            removeAnnotation(annotation)
            return
        }
        annotationBeingReplaced = annotation
        annotationReplacement = nil
        pageAnnotations[annotation.pageIndex]?.removeAll { $0.id == annotation.id }
    }

    func finishReplacingAnnotation() {
        guard let old = annotationBeingReplaced else { return }
        annotationBeingReplaced = nil
        let replacement = annotationReplacement
        annotationReplacement = nil
        removeAnnotation(old)
        // Undo replaces it back the same way, so its replies move back too.
        if let replacement {
            undoManager.registerUndo(withTarget: self) { vm in
                vm.beginReplacingAnnotation(replacement)
                defer { vm.finishReplacingAnnotation() }
                vm.restoreAnnotation(old)
            }
            nameUndoAction("Change Annotation")
        } else {
            registerUndoRemoving(old)
        }
    }

    public func removeAnnotation(_ annotation: PDFAnnotation) {
        let pIdx = annotation.pageIndex
        let wasShown = pageAnnotations[pIdx]?.contains { $0.id == annotation.id } == true
        if wasShown {
            pageAnnotations[pIdx]?.removeAll { $0.id == annotation.id }
            noteAnnotationsChanged(onPage: pIdx)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
        }
        guard let doc = document else { return }
        // Delete exactly the PDF object this annotation was written as. Finding it by position
        // instead deletes whichever annotation happens to come first near that point — often one
        // that was already in the file underneath it.
        if let objectNumber = annotation.documentObjectNumber {
            if annotation.isFromFile {
                removedAnnotationNumbers[pIdx, default: []].insert(objectNumber)
                syncHiddenAnnotations(pageAnnotations)
            }
            // A copy is kept, with replies, author and dates, for Undo to put back. Not when an
            // edit replaced it, whose own Undo puts it back.
            guard wasShown else {
                _ = try? doc.deleteAnnotation(pageIndex: pIdx, objectNumber: objectNumber)
                return
            }
            if let copy = try? doc.deleteAnnotationKeepingCopy(pageIndex: pIdx, objectNumber: objectNumber) {
                undoManager.registerUndo(withTarget: self) { $0.restoreDeletedAnnotation(annotation, copy: copy) }
                nameUndoAction("Delete Annotation")
            }
            return
        }
        if wasShown {
            registerUndoRemoving(annotation)
        }
        let testPoint: CGPoint
        if annotation.type == .ink, let firstPt = annotation.inkPoints.first {
            testPoint = firstPt
        } else if annotation.type == .freeText, let r = annotation.rect {
            testPoint = CGPoint(x: r.midX, y: r.midY)
        } else if annotation.type == .callout, let tp = annotation.targetPoint {
            testPoint = tp
        } else if annotation.type == .stamp, let r = annotation.rect {
            let pageTopY = (pIdx >= 0 && pIdx < doc.pageBounds.count) ? doc.pageBounds[pIdx].maxY : 0
            testPoint = CGPoint(x: r.midX, y: pageTopY - r.midY)
        } else {
            testPoint = CGPoint(x: annotation.boundingRect.midX, y: annotation.boundingRect.midY)
        }
        _ = try? doc.deleteAnnotation(pageIndex: pIdx, at: testPoint)
        if annotation.type == .stamp, let r = annotation.rect {
            // Also try top-down center in case annot rect was recorded top-down
            _ = try? doc.deleteAnnotation(pageIndex: pIdx, at: CGPoint(x: r.midX, y: r.midY))
        }
        if annotation.type == .callout, let r = annotation.rect {
            _ = try? doc.deleteAnnotation(pageIndex: pIdx, at: CGPoint(x: r.midX, y: r.midY))
        }
    }

    /// Puts back an annotation `removeAnnotation` deleted, with its replies, as it was.
    func restoreDeletedAnnotation(_ annotation: PDFAnnotation, copy: Int) {
        let page = annotation.pageIndex
        guard let number = try? document?.restoreDeletedAnnotation(pageIndex: page, copy: copy) else { return }
        var restored = annotation
        restored.documentObjectNumber = number
        restored.appearanceRevision += 1
        pageAnnotations[page, default: []].append(restored)
        noteAnnotationsChanged(onPage: page)
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
        undoManager.registerUndo(withTarget: self) { $0.removeAnnotation(restored) }
        nameUndoAction("Delete Annotation")
    }

    /// Erases the topmost annotation at a point: one shown on the canvas, or one that came with
    /// the file, chosen as precisely as the document allows.
    public func removeAnnotation(at pagePoint: CGPoint, pageIndex: Int) {
        let fileHit = document?.annotationObjectNumber(pageIndex: pageIndex, at: pagePoint)
        if let annot = pageAnnotations[pageIndex]?.last(where: { $0.isFromFile ? $0.documentObjectNumber == fileHit : $0.contains(pagePoint: pagePoint) }) {
            removeAnnotation(annot)
        } else if let fileHit {
            deleteFileAnnotation(pageIndex: pageIndex, objectNumber: fileHit)
        }
    }

    /// Deletes an annotation that came with the file and isn't on the canvas, with its replies,
    /// keeping a copy for Undo. The renderer's copy of the file still has it, so it's left out.
    @discardableResult
    func deleteFileAnnotation(pageIndex: Int, objectNumber: Int) -> Bool {
        guard let copy = try? document?.deleteAnnotationKeepingCopy(pageIndex: pageIndex, objectNumber: objectNumber) else { return false }
        removedAnnotationNumbers[pageIndex, default: []].insert(objectNumber)
        syncHiddenAnnotations(pageAnnotations)
        noteAnnotationsChanged(onPage: pageIndex)
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
        undoManager.registerUndo(withTarget: self) { $0.restoreDeletedFileAnnotation(pageIndex: pageIndex, copy: copy) }
        nameUndoAction("Delete Annotation")
        return true
    }

    /// Puts back an annotation `deleteFileAnnotation` deleted. It comes back as a new object the
    /// renderer's copy doesn't have, so that copy is brought up to date.
    func restoreDeletedFileAnnotation(pageIndex: Int, copy: Int) {
        guard let number = try? document?.restoreDeletedAnnotation(pageIndex: pageIndex, copy: copy) else { return }
        finalizeRedactionChanges(affectedPages: [pageIndex])
        noteAnnotationsChanged(onPage: pageIndex)
        undoManager.registerUndo(withTarget: self) { $0.deleteFileAnnotation(pageIndex: pageIndex, objectNumber: number) }
        nameUndoAction("Delete Annotation")
    }

    // MARK: - What the renderer leaves out

    /// The annotations made or picked up this session, which the canvas draws itself: not ones
    /// from the file that it's only drawing while they're edited.
    public var sessionAnnotations: [Int: [PDFAnnotation]] {
        pageAnnotations.mapValues { $0.filter { !$0.isFromFile } }.filter { !$0.value.isEmpty }
    }

    /// Tells the renderer to leave out what the canvas draws itself, and anything deleted, so
    /// nothing is drawn twice or lingers after a save, and redraws the pages that changed.
    func syncHiddenAnnotations(_ annotations: [Int: [PDFAnnotation]]) {
        var hidden = removedAnnotationNumbers
        for (page, list) in annotations {
            hidden[page, default: []].formUnion(list.compactMap(\.documentObjectNumber))
        }
        hidden = hidden.filter { !$0.value.isEmpty }
        let changed = Set(hidden.keys).union(hiddenAnnotationNumbers.keys).filter { hidden[$0] != hiddenAnnotationNumbers[$0] }
        guard !changed.isEmpty else { return }
        hiddenAnnotationNumbers = hidden
        Task {
            await renderActor.setHiddenAnnotations(hidden)
            for page in changed {
                thumbnailImages.removeValue(forKey: page)
                if renderedPages[page] != nil {
                    await renderPage(page, replacing: true)
                }
            }
        }
    }

    /// Forgets Undo and what's been deleted, when page numbers change or a document opens:
    /// both refer to pages by number.
    func forgetAnnotationEdits() {
        undoManager.removeAllActions()
        removedAnnotationNumbers = [:]
    }

    // MARK: - Undo

    private func registerUndoRemoving(_ annotation: PDFAnnotation) {
        undoManager.registerUndo(withTarget: self) { $0.restoreAnnotation(annotation) }
        nameUndoAction("Delete Annotation")
    }

    /// Names the change for Edit > Undo. Not while undoing or redoing it, which would rename
    /// Redo after the step that reverses it ("Redo Delete Annotation" for an undone add).
    private func nameUndoAction(_ name: String) {
        guard !undoManager.isUndoing, !undoManager.isRedoing else { return }
        undoManager.setActionName(name)
    }

    /// Writes `annot` to the document again after it was removed, for Undo. Its replies aren't
    /// brought back.
    @discardableResult
    func restoreAnnotation(_ annot: PDFAnnotation) -> PDFAnnotation? {
        let page = annot.pageIndex
        switch annot.type {
        case .highlight, .underline, .strikeout:
            guard let doc = document, !annot.quads.isEmpty else { return nil }
            do {
                try doc.addTextMarkup(pageIndex: page, type: annot.type, quads: annot.quads, red: annot.color.rgb.red, green: annot.color.rgb.green, blue: annot.color.rgb.blue)
            } catch {
                print("Failed to restore \(annot.type) on page \(page): \(error)")
                return nil
            }
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            return recordAddedAnnotation(PDFAnnotation(pageIndex: page, type: annot.type, quads: annot.quads, color: annot.color, text: annot.text))
        case .ink:
            return addInkAnnotation(pageIndex: page, points: annot.inkPoints, strokeWidth: annot.strokeWidth, color: annot.color)
        case .freeText:
            return addFreeTextAnnotation(pageIndex: page, rect: annot.rect ?? .zero, text: annot.text, fontSize: annot.fontSize ?? 13.0, color: annot.color)
        case .callout:
            guard let rect = annot.rect, let target = annot.targetPoint, let knee = annot.kneePoint else { return nil }
            return addCalloutAnnotation(pageIndex: page, targetPoint: target, kneePoint: knee, textBoxRect: rect, text: annot.text, fontSize: annot.fontSize ?? 11.0, color: annot.color, lineEnding: annot.lineEnding ?? .closedArrow)
        case .stamp:
            guard let rect = annot.rect, let data = annot.stampImageData else { return nil }
            return addStampAnnotation(pageIndex: page, rect: rect, imageData: data, color: annot.color)
        case .note, .cloud, .square, .circle, .line:
            guard let rect = annot.rect else { return nil }
            return addRestyled(annot, rect: rect, color: annot.color)
        case .other:
            return nil
        case .measureLength, .measurePerimeter, .measureArea, .measureAngle:
            return addMeasurementAnnotation(pageIndex: page, type: annot.type, points: annot.measurementPoints, value: annot.measurementValue, formattedText: annot.measurementText, leaderOffset: annot.leaderOffset, color: annot.color, strokeWidth: annot.strokeWidth, label: annot.text)
        }
    }

    // MARK: - Notes and Revision Clouds

    /// The size of a note's icon, in page points.
    public static let noteSize: CGFloat = 20.0

    @discardableResult
    public func addNoteAnnotation(pageIndex: Int, at point: CGPoint, text: String = "", color: AnnotationColor = .yellow) -> PDFAnnotation? {
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return nil }
        let rect = CGRect(x: point.x, y: point.y, width: Self.noteSize, height: Self.noteSize)
        let annot = PDFAnnotation(pageIndex: pageIndex, type: .note, rect: rect, color: color, text: text)
        do {
            try doc.addNote(pageIndex: pageIndex, rect: rect, text: text, red: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue)
            let stored = recordAddedAnnotation(annot)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            return stored
        } catch {
            print("Failed to add note on page \(pageIndex): \(error)")
            return nil
        }
    }

    @discardableResult
    public func addCloudAnnotation(pageIndex: Int, rect: CGRect, arcSize: PDFCloudArcSize = .medium, color: AnnotationColor = .red) -> PDFAnnotation? {
        return addCloudAnnotation(pageIndex: pageIndex, rect: rect, intensity: arcSize.rawValue, color: color)
    }

    @discardableResult
    func addCloudAnnotation(pageIndex: Int, rect: CGRect, intensity: CGFloat, color: AnnotationColor) -> PDFAnnotation? {
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount, rect.width > 0, rect.height > 0 else { return nil }
        let annot = PDFAnnotation(pageIndex: pageIndex, type: .cloud, rect: rect, strokeWidth: 1.5, color: color, cloudIntensity: intensity)
        do {
            try doc.addCloud(pageIndex: pageIndex, rect: rect, intensity: intensity, red: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue)
            let stored = recordAddedAnnotation(annot)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            return stored
        } catch {
            print("Failed to add revision cloud on page \(pageIndex): \(error)")
            return nil
        }
    }

    /// Adds a revision cloud round the polygon `outline`.
    @discardableResult
    public func addCloudAnnotation(pageIndex: Int, outline: [CGPoint], intensity: CGFloat = PDFCloudArcSize.large.rawValue, color: AnnotationColor = .red) -> PDFAnnotation? {
        let rect = CGRect(enclosing: outline)
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount, outline.count >= 3, rect.width > 0, rect.height > 0 else { return nil }
        let annot = PDFAnnotation(pageIndex: pageIndex, type: .cloud, inkPoints: outline, rect: rect, strokeWidth: 1.5, color: color, cloudIntensity: intensity)
        do {
            try doc.addCloud(pageIndex: pageIndex, vertices: outline, intensity: intensity, red: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue)
            let stored = recordAddedAnnotation(annot)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            return stored
        } catch {
            print("Failed to add revision cloud on page \(pageIndex): \(error)")
            return nil
        }
    }

    /// Re-creates a note or shape with a new position, size or color, for the edits shared by the
    /// canvas. A line's ends, and a cloud's corners, move with its `rect`.
    func addRestyled(_ annot: PDFAnnotation, rect: CGRect, color: AnnotationColor) -> PDFAnnotation? {
        switch annot.type {
        case .note:
            return addNoteAnnotation(pageIndex: annot.pageIndex, at: rect.origin, text: annot.text, color: color)
        case .square, .circle, .line:
            return addShape(PDFAnnotation(pageIndex: annot.pageIndex, type: annot.type, inkPoints: annot.inkPoints(fittedTo: rect), rect: rect, strokeWidth: annot.strokeWidth, color: color, lineEnding: annot.lineEnding))
        default:
            let intensity = annot.cloudIntensity ?? PDFCloudArcSize.medium.rawValue
            if annot.inkPoints.count >= 3 {
                return addCloudAnnotation(pageIndex: annot.pageIndex, outline: annot.inkPoints(fittedTo: rect), intensity: intensity, color: color)
            }
            return addCloudAnnotation(pageIndex: annot.pageIndex, rect: rect, intensity: intensity, color: color)
        }
    }

    /// Re-creates a rectangle, oval or line with new ends, line width or line ending; nil keeps
    /// what it has.
    func addRestyledShape(_ annot: PDFAnnotation, ends: [CGPoint]? = nil, strokeWidth: CGFloat? = nil, lineEnding: PDFLineEnding? = nil) -> PDFAnnotation? {
        let ends = ends ?? annot.inkPoints
        return addShape(PDFAnnotation(
            pageIndex: annot.pageIndex, type: annot.type, inkPoints: ends,
            rect: annot.type == .line ? CGRect(enclosing: ends) : annot.rect,
            strokeWidth: strokeWidth ?? annot.strokeWidth, color: annot.color, lineEnding: lineEnding ?? annot.lineEnding
        ))
    }

    // MARK: - Shapes

    /// Adds the shape dragged out from `start` to `end`: a rectangle or oval filling the box
    /// they are corners of, a cloud ringing it, or a line from one to the other ending in
    /// `lineEnding`.
    @discardableResult
    public func addShapeAnnotation(pageIndex: Int, shape: PDFShapeKind, from start: CGPoint, to end: CGPoint, strokeWidth: CGFloat = 2.5, lineEnding: PDFLineEnding = .openArrow, color: AnnotationColor = .red) -> PDFAnnotation? {
        let rect = CGRect(enclosing: [start, end])
        switch shape {
        case .cloud:
            return addCloudAnnotation(pageIndex: pageIndex, outline: CloudOutline.outline(for: [start, end]), intensity: selectedCloudArcSize.rawValue, color: color)
        case .rectangle, .oval:
            return addShape(PDFAnnotation(pageIndex: pageIndex, type: shape == .rectangle ? .square : .circle, rect: rect, strokeWidth: strokeWidth, color: color))
        case .line:
            return addShape(PDFAnnotation(pageIndex: pageIndex, type: .line, inkPoints: [start, end], rect: rect, strokeWidth: strokeWidth, color: color, lineEnding: lineEnding))
        }
    }

    /// Writes the rectangle, oval or line `annot` describes to the document.
    private func addShape(_ annot: PDFAnnotation) -> PDFAnnotation? {
        let page = annot.pageIndex
        guard let doc = document, page >= 0, page < doc.pageCount, let rect = annot.rect else { return nil }
        guard annot.type == .line ? annot.inkPoints.count >= 2 : rect.width > 0 && rect.height > 0 else { return nil }
        do {
            try doc.addShape(pageIndex: page, type: annot.type, rect: rect, points: annot.inkPoints, strokeWidth: annot.strokeWidth, lineEnding: annot.lineEnding ?? PDFLineEnding.none, red: annot.color.rgb.red, green: annot.color.rgb.green, blue: annot.color.rgb.blue)
            let stored = recordAddedAnnotation(annot)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            return stored
        } catch {
            print("Failed to add \(annot.type) on page \(page): \(error)")
            return nil
        }
    }

    // MARK: - Technical Callout Annotations

    @discardableResult
    public func addCalloutAnnotation(
        pageIndex: Int,
        targetPoint: CGPoint,
        kneePoint: CGPoint,
        textBoxRect: CGRect,
        text: String,
        fontSize: CGFloat = 11.0,
        color: AnnotationColor = .red,
        lineEnding: PDFLineEnding = .closedArrow
    ) -> PDFAnnotation? {
        guard !text.isEmpty, let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return nil }
        let annot = PDFAnnotation(
            pageIndex: pageIndex,
            type: .callout,
            rect: textBoxRect,
            targetPoint: targetPoint,
            kneePoint: kneePoint,
            fontSize: fontSize,
            color: color,
            text: text,
            lineEnding: lineEnding
        )
        do {
            try doc.addCallout(
                pageIndex: pageIndex,
                targetPoint: targetPoint,
                kneePoint: kneePoint,
                textBoxRect: textBoxRect,
                text: text,
                fontSize: fontSize,
                lineEnding: lineEnding,
                red: color.rgb.red,
                green: color.rgb.green,
                blue: color.rgb.blue
            )
            let stored = recordAddedAnnotation(annot)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            return stored
        } catch {
            print("Failed to add callout annotation on page \(pageIndex): \(error)")
            return nil
        }
    }
}

// MARK: - Annotations that came with the file

extension PDFViewerViewModel {
    /// The kinds of annotation from the file that can be picked up and moved on the canvas. Text
    /// markup and freehand drawings stay put, as ones made here do, and measurements belong to
    /// the takeoff.
    static let movableFileSubtypes: Set<String> = ["Square", "Circle", "Line", "Polygon", "PolyLine", "Text", "FreeText", "Stamp", "FileAttachment", "Caret", "Sound"]

    /// Picks up an annotation that came with the file so it can be moved and restyled. From now
    /// on the canvas draws it, as the document does, and the renderer leaves it out.
    func pickUpFileAnnotation(pageIndex: Int, objectNumber: Int) -> PDFAnnotation? {
        // One made here is handled as such, or, like a highlight, isn't picked up at all.
        if let existing = pageAnnotations[pageIndex]?.first(where: { $0.documentObjectNumber == objectNumber }) {
            return existing.isFromFile ? existing : nil
        }
        guard let annot = fileAnnotation(pageIndex: pageIndex, objectNumber: objectNumber, id: UUID(), revision: 0),
              Self.movableFileSubtypes.contains(annot.fileSubtype ?? "") else { return nil }
        pageAnnotations[pageIndex, default: []].append(annot)
        return annot
    }

    /// An annotation from the file as the canvas handles it: what it is and where, enough to
    /// select it, drag it and hit it, while the document says how it looks.
    private func fileAnnotation(pageIndex: Int, objectNumber: Int, id: UUID, revision: Int) -> PDFAnnotation? {
        guard let found = document?.describeAnnotation(pageIndex: pageIndex, objectNumber: objectNumber), !found.isMeasurement else { return nil }
        let type: PDFAnnotationType
        switch found.subtype {
        case "Square": type = found.isCloud ? .cloud : .square
        case "Circle": type = .circle
        case "Line": type = .line
        case "Polygon" where found.isCloud: type = .cloud
        case "Text": type = .note
        case "FreeText": type = .freeText
        case "Stamp": type = .stamp
        default: type = .other
        }
        // A line's or polygon's box is the one its points are corners of, as for ones made here.
        let rect = found.points.count >= 2 ? CGRect(enclosing: found.points) : found.rect
        var annot = PDFAnnotation(
            id: id,
            pageIndex: pageIndex,
            type: type,
            inkPoints: found.points,
            rect: rect,
            strokeWidth: found.borderWidth,
            color: found.color ?? .black,
            text: annotationThread(pageIndex: pageIndex, objectNumber: objectNumber)?.root.text ?? "",
            lineEnding: type == .line ? found.lineEnding ?? PDFLineEnding.none : nil,
            cloudIntensity: found.isCloud ? 1 : nil
        )
        annot.documentObjectNumber = objectNumber
        annot.fileSubtype = found.subtype
        annot.appearanceRevision = revision
        return annot
    }

    /// Moves, resizes or restyles an annotation that came with the file, in place: it keeps its
    /// object number and replies and, when it's only moved, the appearance its app gave it.
    /// Undo puts it back as it was.
    @discardableResult
    func editFileAnnotation(_ annot: PDFAnnotation, _ edit: (PDFDocumentCore, Int) throws -> Void) -> PDFAnnotation? {
        guard let doc = document, let number = annot.documentObjectNumber,
              let copy = try? doc.copyAnnotation(pageIndex: annot.pageIndex, objectNumber: number) else { return nil }
        do {
            try edit(doc, number)
        } catch {
            print("Failed to change annotation on page \(annot.pageIndex): \(error)")
            return nil
        }
        let updated = refreshFileAnnotation(annot)
        undoManager.registerUndo(withTarget: self) { $0.restoreFileAnnotation(updated ?? annot, copy: copy) }
        nameUndoAction("Change Annotation")
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
        noteAnnotationsChanged(onPage: annot.pageIndex)
        return updated
    }

    private func restoreFileAnnotation(_ annot: PDFAnnotation, copy: Int) {
        guard let doc = document, let number = annot.documentObjectNumber,
              let redo = try? doc.copyAnnotation(pageIndex: annot.pageIndex, objectNumber: number),
              (try? doc.restoreAnnotation(pageIndex: annot.pageIndex, objectNumber: number, from: copy)) != nil else { return }
        let restored = refreshFileAnnotation(annot)
        undoManager.registerUndo(withTarget: self) { $0.restoreFileAnnotation(restored ?? annot, copy: redo) }
        nameUndoAction("Change Annotation")
        noteAnnotationsChanged(onPage: annot.pageIndex)
    }

    /// Reads an annotation from the file again after it changed, in place of the old one.
    private func refreshFileAnnotation(_ annot: PDFAnnotation) -> PDFAnnotation? {
        guard let number = annot.documentObjectNumber,
              let index = pageAnnotations[annot.pageIndex]?.firstIndex(where: { $0.id == annot.id }),
              let fresh = fileAnnotation(pageIndex: annot.pageIndex, objectNumber: number, id: annot.id, revision: annot.appearanceRevision + 1) else { return nil }
        pageAnnotations[annot.pageIndex]?[index] = fresh
        return fresh
    }
}
