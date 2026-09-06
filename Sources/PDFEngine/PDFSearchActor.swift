import Foundation
import CoreGraphics
import MuPDFBridge

final class SearchResource: @unchecked Sendable {
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

public actor PDFSearchActor {
    private let resource: SearchResource
    private var currentPath: String?
    
    public init() {
        self.resource = SearchResource()
    }
    
    public func openDocument(filePath: String, password: String? = nil) throws {
        // No same-path short-circuit — see PDFRenderActor.openDocument.
        if let d = resource.doc {
            mupdf_document_drop(resource.ctx, d)
            resource.doc = nil
        }

        var docPtr: FZDocument?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_document_open(resource.ctx, filePath, &docPtr, &errorMsg)
        guard ret == 0, let d = docPtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to open document for search"
            throw PDFError.openFailed(msg)
        }

        // This actor holds its own separate fz_document instance in its own cloned context, so
        // it needs its own authentication too — see the identical note in PDFRenderActor.
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
        self.currentPath = filePath
    }
    
    /// Streams search results page-by-page as they are discovered in real time,
    /// prioritizing a local ±50 page window around `nearPage` first for instant (<30ms) nearby hits.
    public func searchStream(query: String, nearPage: Int = 0, options: SearchOptions = SearchOptions()) -> AsyncStream<SearchResult> {
        AsyncStream<SearchResult> { continuation in
            let task = Task {
                guard let doc = self.resource.doc else {
                    continuation.finish()
                    return
                }
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    continuation.finish()
                    return
                }
                
                let ctx = self.resource.ctx
                var count: Int32 = 0
                mupdf_document_count_pages(ctx, doc, &count, nil)
                let totalPages = Int(count)
                guard totalPages > 0 else {
                    continuation.finish()
                    return
                }
                
                var pattern = options.smartSearch
                    ? SmartRegexBuilder.buildPattern(from: query)
                    : SmartRegexBuilder.buildLiteralPattern(from: query)
                if options.wholeWord {
                    pattern = SmartRegexBuilder.applyWholeWord(pattern)
                }
                let regexOptions: NSRegularExpression.Options = options.matchCase ? [] : [.caseInsensitive]
                guard !pattern.isEmpty,
                      let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else {
                    continuation.finish()
                    return
                }
                
                // Build 3-slice prioritized search sequence:
                // 1. Local ±50 page window around nearPage (immediate ~30ms hits)
                // 2. Forward from localEnd+1 to totalPages
                // 3. Backward from 0 to localStart-1
                let clampedNear = min(max(nearPage, 0), totalPages - 1)
                let localStart = max(0, clampedNear - 50)
                let localEnd = min(totalPages - 1, clampedNear + 50)
                let localSlice = Array(localStart...localEnd)
                let forwardSlice = (localEnd + 1 < totalPages) ? Array((localEnd + 1)..<totalPages) : []
                let backwardSlice = (localStart > 0) ? Array(0..<localStart) : []
                let searchSequence = localSlice + forwardSlice + backwardSlice
                
                for (stepCount, pageIdx) in searchSequence.enumerated() {
                    if Task.isCancelled { break }
                    
                    // Yield every 5 pages for smooth UI responsiveness
                    if stepCount % 5 == 0 {
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
                        
                        // Fast plain text extraction in C to filter non-matching pages
                        guard let cText = mupdf_stext_page_text(ctx, stext) else { return }
                        let pageText = String(cString: cText)
                        mupdf_free(ctx, cText)
                        
                        let nsString = pageText as NSString
                        guard regex.firstMatch(in: pageText, options: [], range: NSRange(location: 0, length: nsString.length)) != nil else {
                            return
                        }
                        
                        var rect = fz_rect()
                        mupdf_page_bounds(ctx, page, &rect, nil)
                        let pageBounds = CGRect(x: CGFloat(rect.x0), y: CGFloat(rect.y0), width: CGFloat(rect.x1 - rect.x0), height: CGFloat(rect.y1 - rect.y0))
                        
                        let structuredPage = StructuredPage.load(fromStext: stext, pageIndex: pageIdx, pageBounds: pageBounds)
                        let (indexedText, charQuads) = structuredPage.searchableIndex
                        let nsIndexed = indexedText as NSString
                        let exactMatches = regex.matches(in: indexedText, options: [], range: NSRange(location: 0, length: nsIndexed.length))
                        
                        for match in exactMatches {
                            if Task.isCancelled { break }
                            let matchedStr = nsIndexed.substring(with: match.range)
                            
                            let start = max(0, match.range.location - 35)
                            let end = min(nsIndexed.length, match.range.location + match.range.length + 35)
                            let snippet = "..." + nsIndexed.substring(with: NSRange(location: start, length: end - start)).replacingOccurrences(of: "\n", with: " ") + "..."
                            
                            var rawQuads: [PDFQuad] = []
                            let matchEnd = min(charQuads.count, match.range.location + match.range.length)
                            if match.range.location < matchEnd {
                                for i in match.range.location..<matchEnd {
                                    if let q = charQuads[i] {
                                        rawQuads.append(q)
                                    }
                                }
                            }
                            
                            let merged = rawQuads.mergedLineQuads()
                            let finalQuads = merged.isEmpty ? rawQuads : merged
                            
                            continuation.yield(SearchResult(
                                pageIndex: pageIdx,
                                matchedText: matchedStr,
                                snippet: snippet,
                                highlightQuads: finalQuads
                            ))
                        }
                    }
                    
                    // Periodically empty store to keep MuPDF memory strictly bounded during long searches
                    if pageIdx % 15 == 0 {
                        mupdf_context_empty_store(ctx)
                    }
                }
                
                // Final clean-up of search context store
                mupdf_context_empty_store(ctx)
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    /// Searches the entire document and returns aggregated results
    public func search(query: String, options: SearchOptions = SearchOptions()) async throws -> [SearchResult] {
        var results: [SearchResult] = []
        let stream = searchStream(query: query, options: options)
        for await res in stream {
            results.append(res)
        }
        return results
    }
}
