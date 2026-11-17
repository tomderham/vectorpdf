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
    private static let lastPageMarksKey = "com.thomasderham.vectorpdf.lastPageMarkSettings"

    public func showPageMarks() {
        guard document?.isPDF == true, !isReadOnlyDocument else { return }
        isShowingPageMarks = true
    }

    /// What the sheet starts with: the document's own marks, else the ones used last (without
    /// their text, which belongs to that document), else the defaults.
    public func initialPageMarkSettings() -> PageMarkSettings {
        if let own = document?.pageMarkSettings() { return own }
        guard let data = UserDefaults.standard.data(forKey: Self.lastPageMarksKey),
              var last = try? JSONDecoder().decode(PageMarkSettings.self, from: data) else { return PageMarkSettings() }
        last.pages = PageMarkSettings.PageChoice()
        return last
    }

    /// Whether the document has headers, footers or a watermark VectorPDF added.
    public var hasPageMarks: Bool {
        guard let kinds = document?.pageMarkKinds() else { return false }
        return kinds.headerFooter || kinds.watermark
    }

    /// Puts these headers, footers and watermark on the pages, in place of any VectorPDF added
    /// before; with empty settings, takes them off.
    public func applyPageMarks(_ settings: PageMarkSettings) {
        guard let doc = document, !isReadOnlyDocument else { return }
        flushPendingFormEdits()
        let changed: Set<Int>
        do {
            changed = try doc.applyPageMarks(settings)
        } catch {
            showErrorAlert(title: "Couldn't Change the Headers and Footers", message: error.localizedDescription)
            return
        }
        if !settings.isEmpty, let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.lastPageMarksKey)
        }
        guard !changed.isEmpty else { return }
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
        // The pages' text changed: selection, search and the Agent read it again.
        for page in changed { pageStructuredData.removeValue(forKey: page) }
        invalidateAgentIndex(deleteCache: false)
        thumbnailVersion = UUID()
        refreshRendererCopy(pages: changed)
    }
}
