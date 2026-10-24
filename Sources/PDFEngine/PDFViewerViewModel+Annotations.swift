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
        pageAnnotations[annot.pageIndex, default: []].append(stored)
        return stored
    }

    public func removeAnnotation(_ annotation: PDFAnnotation) {
        let pIdx = annotation.pageIndex
        if let idx = pageAnnotations[pIdx]?.firstIndex(where: { $0.id == annotation.id }) {
            pageAnnotations[pIdx]?.remove(at: idx)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
        }
        guard let doc = document else { return }
        // Delete exactly the PDF object this annotation was written as. Finding it by position
        // instead deletes whichever annotation happens to come first near that point — often one
        // that was already in the file underneath it.
        if let objectNumber = annotation.documentObjectNumber {
            _ = try? doc.deleteAnnotation(pageIndex: pIdx, objectNumber: objectNumber)
            return
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

    public func removeAnnotation(at pagePoint: CGPoint, pageIndex: Int) {
        if let list = pageAnnotations[pageIndex], let annot = list.first(where: { $0.contains(pagePoint: pagePoint) }) {
            removeAnnotation(annot)
        } else if let doc = document {
            // An annotation that came with the file isn't in `pageAnnotations`. Deleting it from the
            // document alone changes nothing on screen (rendering reads the file through its own
            // actor) and nothing flags the document as edited — so push the change through the
            // same working-copy refresh the other edits use.
            if (try? doc.deleteAnnotation(pageIndex: pageIndex, at: pagePoint)) == true {
                finalizeRedactionChanges(affectedPages: [pageIndex])
            }
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
        color: AnnotationColor = .red
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
            text: text
        )
        do {
            try doc.addCallout(
                pageIndex: pageIndex,
                targetPoint: targetPoint,
                kneePoint: kneePoint,
                textBoxRect: textBoxRect,
                text: text,
                fontSize: fontSize,
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
