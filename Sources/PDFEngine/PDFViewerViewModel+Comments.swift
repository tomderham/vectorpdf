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
import Foundation

extension PDFViewerViewModel {
    // MARK: - Annotation Comments

    static let annotationAuthorDefaultsKey = "annotationAuthorName"

    /// The name written on new annotations and replies: the Annotation Author setting, or the
    /// name of the Mac's user until one is chosen.
    public static var annotationAuthor: String {
        let name = UserDefaults.standard.string(forKey: annotationAuthorDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? NSFullUserName() : name
    }

    /// Every annotation in the document, in page order.
    public func annotationThreads() -> [PDFAnnotationThread] {
        guard let doc = document else { return [] }
        return (0..<doc.pageCount).flatMap { doc.annotationThreads(pageIndex: $0) }
    }

    public func annotationThread(pageIndex: Int, objectNumber: Int) -> PDFAnnotationThread? {
        document?.annotationThreads(pageIndex: pageIndex).first { $0.root.objectNumber == objectNumber }
    }

    /// The topmost annotation under a point, whichever app made it. Ones with smaller bounds win,
    /// so a note on a large drawing can still be reached.
    public func annotationThread(pageIndex: Int, at point: CGPoint) -> PDFAnnotationThread? {
        document?.annotationThreads(pageIndex: pageIndex)
            .filter { $0.root.rect.insetBy(dx: -3, dy: -3).contains(point) }
            .min { $0.root.rect.width * $0.root.rect.height < $1.root.rect.width * $1.root.rect.height }
    }

    private func markAnnotationsEdited() {
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
    }

    public func addReply(to thread: PDFAnnotationThread, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let doc = document else { return }
        do {
            try doc.addAnnotationReply(pageIndex: thread.root.pageIndex, parentObjectNumber: thread.root.objectNumber, text: text, author: Self.annotationAuthor)
            markAnnotationsEdited()
        } catch {
            print("Failed to add reply on page \(thread.root.pageIndex): \(error)")
        }
    }

    public func setStatus(_ status: PDFReviewStatus, of thread: PDFAnnotationThread) {
        guard status != thread.status, let doc = document else { return }
        let author = Self.annotationAuthor
        do {
            try doc.addAnnotationReply(
                pageIndex: thread.root.pageIndex,
                parentObjectNumber: thread.root.objectNumber,
                text: "\(status.rawValue) set by \(author)",
                author: author,
                status: status
            )
            markAnnotationsEdited()
        } catch {
            print("Failed to set status on page \(thread.root.pageIndex): \(error)")
        }
    }

    public func setComment(_ text: String, of thread: PDFAnnotationThread) {
        guard text != thread.root.text, let doc = document else { return }
        let page = thread.root.pageIndex
        do {
            try doc.setAnnotationComment(pageIndex: page, objectNumber: thread.root.objectNumber, text: text)
            if let index = pageAnnotations[page]?.firstIndex(where: { $0.documentObjectNumber == thread.root.objectNumber }) {
                pageAnnotations[page]?[index].text = text
            }
            markAnnotationsEdited()
        } catch {
            print("Failed to change comment on page \(page): \(error)")
        }
    }

    /// Deletes an annotation and its replies, whether added this session or already in the file.
    public func deleteThread(_ thread: PDFAnnotationThread) {
        let page = thread.root.pageIndex
        if let annot = pageAnnotations[page]?.first(where: { $0.documentObjectNumber == thread.root.objectNumber }) {
            removeAnnotation(annot)
        } else if (try? document?.deleteAnnotation(pageIndex: page, objectNumber: thread.root.objectNumber)) == true {
            finalizeRedactionChanges(affectedPages: [page])
        }
    }
}
