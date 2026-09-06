import Foundation
import CoreGraphics
import MuPDFBridge

/// Dedicated background actor with its own cloned context & document, whose only job is walking
/// every page of a document and handing back its plain text — the raw material the Agent tab's
/// semantic index is built from. Mirrors PDFSearchActor's resource/authentication pattern exactly
/// (see the architectural note in PDFContextManager.swift): this needs its own fz_context/
/// fz_document because it runs concurrently with rendering/searching on the same document, and
/// MuPDF contexts/documents aren't safe to share across threads.
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

        // Own document instance, own context — needs its own authentication too, same as every
        // other independent MuPDF document handle in this app (see PDFRenderActor/PDFSearchActor).
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

    /// Streams each page's prose text (see StructuredPage.proseText — figure/table fragments
    /// excluded) page-by-page, yielding `(pageIndex, text)`. Callers drive chunking/embedding off
    /// this — kept separate so this actor's only concern is MuPDF extraction.
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

                        // Structured (block/line geometry), not the flat mupdf_stext_page_text
                        // string — see StructuredPage.proseText for why: it excludes figure/table
                        // fragments that plain-text extraction can't distinguish from real prose.
                        var rect = fz_rect()
                        mupdf_page_bounds(ctx, page, &rect, nil)
                        let pageBounds = CGRect(x: CGFloat(rect.x0), y: CGFloat(rect.y0), width: CGFloat(rect.x1 - rect.x0), height: CGFloat(rect.y1 - rect.y0))
                        let structuredPage = StructuredPage.load(fromStext: stext, pageIndex: pageIdx, pageBounds: pageBounds)

                        continuation.yield((pageIndex: pageIdx, text: structuredPage.proseText))
                    }

                    // Same periodic store-clearing as PDFSearchActor — this walks every page of
                    // potentially thousands, so keeping MuPDF's internal cache bounded matters here
                    // even more than during an interactive search.
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
