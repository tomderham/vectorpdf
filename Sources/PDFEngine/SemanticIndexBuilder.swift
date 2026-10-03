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

import Foundation
import CoreGraphics
import MuPDFBridge

/// Manages background extraction of document plain text for semantic indexing using a dedicated context.
final class SemanticExtractionResource: @unchecked Sendable {
    let ctx: FZContext
    var doc: FZDocument?

    init() {
        self.ctx = PDFContextManager.shared.makeClonedContext()
    }

    deinit {
        if let d = doc {
            mupdf_document_drop(ctx, d)
        }
        PDFContextManager.shared.dropContext(ctx)
    }
}

public actor SemanticIndexBuilder {
    private let resource: SemanticExtractionResource

    public init() {
        self.resource = SemanticExtractionResource()
    }

    public func openDocument(filePath: String, password: String? = nil) throws {
        var docPtr: FZDocument?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_document_open(resource.ctx, filePath, &docPtr, &errorMsg)
        guard ret == 0, let d = docPtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to open document for indexing"
            throw PDFError.openFailed(msg)
        }

        // Authenticate password-protected documents.
        var needsPassword: Int32 = 0
        mupdf_document_needs_password(resource.ctx, d, &needsPassword, &errorMsg)
        if needsPassword != 0 {
            guard let password else {
                mupdf_document_drop(resource.ctx, d)
                throw PDFError.passwordRequired
            }
            var authenticated: Int32 = 0
            mupdf_document_authenticate_password(resource.ctx, d, password, &authenticated, &errorMsg)
            guard authenticated != 0 else {
                mupdf_document_drop(resource.ctx, d)
                throw PDFError.incorrectPassword
            }
        }

        self.resource.doc = d
    }

    public func pageCount() -> Int {
        guard let doc = resource.doc else { return 0 }
        var count: Int32 = 0
        mupdf_document_count_pages(resource.ctx, doc, &count, nil)
        return Int(count)
    }

    /// Streams prose text page-by-page, yielding `(pageIndex, text)`.
    public func extractPageTexts() -> AsyncStream<(pageIndex: Int, text: String)> {
        AsyncStream { continuation in
            let task = Task {
                guard let doc = self.resource.doc else {
                    continuation.finish()
                    return
                }
                let ctx = self.resource.ctx
                var count: Int32 = 0
                mupdf_document_count_pages(ctx, doc, &count, nil)
                let totalPages = Int(count)

                for pageIdx in 0..<totalPages {
                    if Task.isCancelled { break }
                    if pageIdx % 5 == 0 {
                        await Task.yield()
                    }

                    autoreleasepool {
                        var pagePtr: FZPage?
                        guard mupdf_page_load(ctx, doc, Int32(pageIdx), &pagePtr, nil) == 0, let page = pagePtr else {
                            return
                        }
                        defer { mupdf_page_drop(ctx, page) }

                        var stextPtr: FZStextPage?
                        guard mupdf_stext_page_load(ctx, page, &stextPtr, nil) == 0, let stext = stextPtr else {
                            return
                        }
                        defer { mupdf_stext_page_drop(ctx, stext) }

                        // Extract structured prose text, excluding non-prose elements.
                        var rect = fz_rect()
                        mupdf_page_bounds(ctx, page, &rect, nil)
                        let pageBounds = CGRect(x: CGFloat(rect.x0), y: CGFloat(rect.y0), width: CGFloat(rect.x1 - rect.x0), height: CGFloat(rect.y1 - rect.y0))
                        let structuredPage = StructuredPage.load(fromStext: stext, pageIndex: pageIdx, pageBounds: pageBounds)

                        continuation.yield((pageIndex: pageIdx, text: structuredPage.proseText))
                    }

                    // Periodically empty store to keep memory usage bounded.
                    if pageIdx % 15 == 0 {
                        mupdf_context_empty_store(ctx)
                    }
                }

                mupdf_context_empty_store(ctx)
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
