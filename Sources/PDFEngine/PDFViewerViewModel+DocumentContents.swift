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

extension PDFViewerViewModel {
    /// The parts of the Document tab this document has, in the order its menu lists them. The
    /// tab shows only when there's at least one.
    /// Form fields, links and destinations only with the setting that lists them on.
    public var documentSidebarSections: [DocumentSidebarSection] {
        let listsStructure = PDFViewerAppCoordinator.shared.showsDocumentStructureInSidebar
        return DocumentSidebarSection.allCases.filter { section in
            switch section {
            case .layers: return !layers.isEmpty
            case .attachments: return !attachments.isEmpty
            case .fields: return listsStructure && documentContentsSummary.hasFormFields
            case .links: return listsStructure && documentContentsSummary.hasLinks
            case .destinations: return listsStructure && documentContentsSummary.hasNamedDestinations
            }
        }
    }

    /// The part of the Document tab to show: the one chosen, or the first there is.
    public var shownDocumentSidebarSection: DocumentSidebarSection? {
        let sections = documentSidebarSections
        return sections.contains(documentSidebarSection) ? documentSidebarSection : sections.first
    }

    /// Forgets the lists read for the last document.
    func resetDocumentContents(summary: DocumentContentsSummary) {
        for task in documentContentsTasks.values { task.cancel() }
        documentContentsTasks = [:]
        documentContentsSummary = summary
        formFieldEntries = nil
        documentLinks = nil
        documentLinksProgress = nil
        linkTextPages = []
        documentLinkTexts = [:]
        namedDestinations = nil
        documentContentsReader = nil
    }

    /// After pages were edited (deleted, moved, inserted): what the document has may have
    /// changed, and the lists' page numbers with it.
    func refreshDocumentContents() {
        guard let doc = document else { return }
        let wasLoaded = (fields: formFieldEntries != nil, links: documentLinks != nil, destinations: namedDestinations != nil)
        resetDocumentContents(summary: doc.contentsSummary())
        if wasLoaded.fields { loadDocumentSection(.fields) }
        if wasLoaded.links { loadDocumentSection(.links) }
        if wasLoaded.destinations { loadDocumentSection(.destinations) }
    }

    /// The document to read the lists from: a copy of the file opened for them, so reading a
    /// long document doesn't hold up the window's own (rendering, selecting and editing all
    /// wait on its lock); or the window's own once it has unsaved changes the file doesn't.
    private func contentsReader(for doc: PDFDocumentCore) async -> PDFDocumentCore {
        if isDocumentEdited { return doc }
        if let reader = documentContentsReader, reader.filePath == doc.filePath { return reader }
        let path = doc.filePath, password = currentDocumentPassword
        let reader = await Task.detached(priority: .utility) { try? PDFDocumentCore(filePath: path, password: password) }.value
        guard let reader, reader.pageCount == doc.pageCount, self.document === doc else { return doc }
        documentContentsReader = reader
        return reader
    }

    /// Reads the list for `section` off the main thread, if it hasn't been read.
    public func loadDocumentSection(_ section: DocumentSidebarSection) {
        guard let doc = document, documentContentsTasks[section] == nil else { return }
        switch section {
        case .layers, .attachments:
            return
        case .fields:
            guard formFieldEntries == nil else { return }
            documentContentsTasks[section] = Task { [weak self] in
                guard let reader = await self?.contentsReader(for: doc) else { return }
                let found = await Task.detached(priority: .utility) { () -> [PDFFormFieldEntry]? in
                    var found: [PDFFormFieldEntry] = []
                    for page in 0..<reader.pageCount {
                        if Task.isCancelled { return nil }
                        found += reader.formFieldEntries(pageIndex: page)
                    }
                    return found
                }.value
                guard let self, !Task.isCancelled, let found, self.document === doc else { return }
                self.formFieldEntries = found
                self.documentContentsTasks[section] = nil
            }
        case .links:
            guard documentLinks == nil else { return }
            documentLinksProgress = 0
            documentContentsTasks[section] = Task { [weak self] in
                guard let reader = await self?.contentsReader(for: doc) else { return }
                let pageCount = reader.pageCount
                var found: [PDFDocumentLink] = []
                var page = 0
                var lastShown = Date.distantPast
                // In batches, shown as they come, so a long document lists its first links at once.
                while page < pageCount {
                    let range = page..<min(pageCount, page + 50)
                    let batch = await Task.detached(priority: .utility) { () -> [PDFDocumentLink]? in
                        var batch: [PDFDocumentLink] = []
                        for index in range {
                            if Task.isCancelled { return nil }
                            batch += reader.documentLinks(pageIndex: index)
                        }
                        return batch
                    }.value
                    guard let self, !Task.isCancelled, let batch, self.document === doc else { return }
                    found += batch
                    page = range.upperBound
                    // Shown at most twice a second: each time, the list's rows are made again.
                    if self.documentLinks == nil || (!batch.isEmpty && Date().timeIntervalSince(lastShown) > 0.5) {
                        self.documentLinks = found
                        lastShown = Date()
                    }
                    let progress = page < pageCount ? Double(page) / Double(max(pageCount, 1)) : nil
                    if progress == nil || abs((self.documentLinksProgress ?? 0) - (progress ?? 0)) > 0.01 { self.documentLinksProgress = progress }
                }
                guard let self, !Task.isCancelled, self.document === doc else { return }
                self.documentLinks = found
                self.documentLinksProgress = nil
                self.documentContentsTasks[section] = nil
            }
        case .destinations:
            guard namedDestinations == nil else { return }
            documentContentsTasks[section] = Task { [weak self] in
                guard let reader = await self?.contentsReader(for: doc) else { return }
                let found = await Task.detached(priority: .utility) { reader.namedDestinations() }.value
                guard let self, !Task.isCancelled, self.document === doc else { return }
                self.namedDestinations = found
                self.documentContentsTasks[section] = nil
            }
        }
    }

    /// Reads the text under the links on `page`, when the list first shows them: that needs the
    /// page's text, too slow to read for every page up front.
    public func loadLinkTexts(onPage page: Int) {
        guard let doc = document, let links = documentLinks, !linkTextPages.contains(page) else { return }
        let onPage = links.filter { $0.pageIndex == page }
        let rects = onPage.map(\.rect), ids = onPage.map(\.id)
        // Not yet read while the list is still being made: asked again when it's shown.
        guard !rects.isEmpty else { return }
        linkTextPages.insert(page)
        Task { [weak self] in
            guard let reader = await self?.contentsReader(for: doc) else { return }
            let texts = await Task.detached(priority: .utility) { reader.linkTexts(pageIndex: page, rects: rects) }.value
            guard let self, self.document === doc else { return }
            let read = zip(ids, texts).filter { !$0.1.isEmpty }
            if !read.isEmpty { self.documentLinkTexts.merge(read, uniquingKeysWith: { _, new in new }) }
        }
    }

    /// After a form field's value changed: reads the pages with fields again, for their values
    /// (a calculation may have changed fields on other pages).
    func refreshFormFieldValues() {
        guard let doc = document, let entries = formFieldEntries, documentContentsTasks[.fields] == nil else { return }
        let pages = Set(entries.map(\.pageIndex)).sorted()
        formFieldEntries = pages.flatMap { doc.formFieldEntries(pageIndex: $0) }
    }

    /// Scrolls to `rect` on a page and outlines it for a moment, as for an annotation chosen in
    /// the Comments tab.
    public func revealPageRect(_ rect: CGRect, onPage page: Int) {
        guard let doc = document, page >= 0, page < doc.pageCount else { return }
        loadPageMetadata(page)
        recordNavigationLocation(page)
        currentPageIndex = page
        pruneCaches(around: page)
        annotationReveal = AnnotationReveal(
            token: (annotationReveal?.token ?? 0) &+ 1,
            pageIndex: page,
            objectNumber: -1,
            rect: rect,
            opensComments: false
        )
        Task { await renderPage(page) }
    }

    /// Goes where a link in the Document tab points: its page, or its address in the browser.
    public func followDocumentLink(_ link: PDFDocumentLink) {
        if let page = link.targetPage {
            revealDestination(page: page, point: link.targetPoint)
        } else if let uri = link.uri, let url = URL(string: uri) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Goes to a named destination.
    public func goToNamedDestination(_ destination: PDFNamedDestination) {
        guard let page = destination.pageIndex else { return }
        revealDestination(page: page, point: destination.point)
    }

    /// Scrolls to a place on a page a link or destination points to, outlining a strip there.
    private func revealDestination(page: Int, point: CGPoint?) {
        guard let doc = document, page >= 0, page < doc.pageCount else { return }
        let bounds = doc.pageBounds[page]
        guard let point, point.y.isFinite, point.y > bounds.minY + 1 else {
            jumpToPage(page)
            return
        }
        let y = min(max(point.y, bounds.minY), bounds.maxY - 20)
        revealPageRect(CGRect(x: bounds.minX, y: y, width: bounds.width, height: 20), onPage: page)
    }
}
