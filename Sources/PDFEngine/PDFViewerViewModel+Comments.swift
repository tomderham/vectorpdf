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

/// Which page's annotations last changed, so the Comments sidebar rereads only that page.
public struct AnnotationChange: Equatable, Sendable {
    public var revision = 0
    /// Nil when any page may have changed, such as when a document opens.
    public var page: Int?
}

/// A request to scroll to an annotation, from the Comments sidebar.
public struct AnnotationReveal: Equatable, Sendable {
    /// Changes with every request, so asking for the same annotation twice scrolls again.
    public let token: Int
    public let pageIndex: Int
    public let objectNumber: Int
    public let rect: CGRect
    public let opensComments: Bool
}

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

    /// The annotations on one page.
    public func annotationThreads(pageIndex: Int) -> [PDFAnnotationThread] {
        document?.annotationThreads(pageIndex: pageIndex) ?? []
    }

    public func annotationThread(pageIndex: Int, objectNumber: Int) -> PDFAnnotationThread? {
        document?.annotationThreads(pageIndex: pageIndex).first { $0.root.objectNumber == objectNumber }
    }

    /// The topmost annotation under a point, whichever app made it. Ones with smaller bounds win,
    /// so a note on a large drawing can still be reached.
    public func annotationThread(pageIndex: Int, at point: CGPoint) -> PDFAnnotationThread? {
        document?.annotationThreads(pageIndex: pageIndex)
            .filter { $0.root.rect.insetBy(dx: -3, dy: -3).contains(point) && !isOnHiddenLayer($0.root) }
            .min { $0.root.rect.width * $0.root.rect.height < $1.root.rect.width * $1.root.rect.height }
    }

    private func markAnnotationsEdited(onPage page: Int) {
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
        noteAnnotationsChanged(onPage: page)
    }

    /// Reads `page`'s annotations again for the Comments sidebar, or every page's for nil.
    func noteAnnotationsChanged(onPage page: Int?) {
        annotationChange = AnnotationChange(revision: annotationChange.revision &+ 1, page: page)
        // While every page is being read, that read may already have passed this page.
        if let page, annotationThreadsTask == nil, annotationThreadsByPage != nil {
            // Callers note the change before they finish writing it (removeAnnotation deletes
            // the object afterwards), so read the page once they're done.
            Task { @MainActor [weak self] in
                guard let self, self.annotationThreadsTask == nil, self.annotationThreadsByPage != nil else { return }
                let threads = self.annotationThreads(pageIndex: page)
                self.annotationThreadsByPage?[page] = threads.isEmpty ? nil : threads
            }
        } else {
            reloadAllAnnotationThreads()
        }
    }

    /// Reads every page's annotations off the main thread, which takes a while in a long document.
    private func reloadAllAnnotationThreads() {
        annotationThreadsTask?.cancel()
        annotationThreadsByPage = nil
        guard let doc = document else {
            annotationThreadsTask = nil
            annotationThreadsByPage = [:]
            return
        }
        annotationThreadsTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { () -> [Int: [PDFAnnotationThread]]? in
                var found: [Int: [PDFAnnotationThread]] = [:]
                for page in 0..<doc.pageCount {
                    if Task.isCancelled { return nil }
                    let threads = doc.annotationThreads(pageIndex: page)
                    if !threads.isEmpty { found[page] = threads }
                }
                return found
            }.value
            guard let self, !Task.isCancelled, let found, self.document === doc else { return }
            self.annotationThreadsByPage = found
            self.annotationThreadsTask = nil
        }
    }

    /// Scrolls to an annotation, selects it if it was made in this session and briefly
    /// outlines it; with `opensComments`, opens its comments beside it.
    public func revealAnnotation(_ thread: PDFAnnotationThread, opensComments: Bool = false) {
        let page = thread.root.pageIndex
        guard let doc = document, page >= 0, page < doc.pageCount else { return }
        loadPageMetadata(page)
        recordNavigationLocation(page)
        currentPageIndex = page
        pruneCaches(around: page)
        annotationReveal = AnnotationReveal(
            token: (annotationReveal?.token ?? 0) &+ 1,
            pageIndex: page,
            objectNumber: thread.root.objectNumber,
            rect: thread.root.rect,
            opensComments: opensComments
        )
        Task { await renderPage(page) }
    }

    public func addReply(to thread: PDFAnnotationThread, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let doc = document else { return }
        do {
            try doc.addAnnotationReply(pageIndex: thread.root.pageIndex, parentObjectNumber: thread.root.objectNumber, text: text, author: Self.annotationAuthor)
            markAnnotationsEdited(onPage: thread.root.pageIndex)
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
            markAnnotationsEdited(onPage: thread.root.pageIndex)
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
            markAnnotationsEdited(onPage: page)
        } catch {
            print("Failed to change comment on page \(page): \(error)")
        }
    }

    /// Deletes an annotation and its replies, whether added this session or already in the file.
    public func deleteThread(_ thread: PDFAnnotationThread) {
        let page = thread.root.pageIndex
        if let annot = pageAnnotations[page]?.first(where: { $0.documentObjectNumber == thread.root.objectNumber }) {
            removeAnnotation(annot)
        } else {
            deleteFileAnnotation(pageIndex: page, objectNumber: thread.root.objectNumber)
        }
    }
}
