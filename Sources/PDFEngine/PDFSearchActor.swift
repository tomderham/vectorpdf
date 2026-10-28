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
        // Keep existing document open until replacement is opened and authenticated.
        var docPtr: FZDocument?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_document_open(resource.ctx, filePath, &docPtr, &errorMsg)
        guard ret == 0, let d = docPtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to open document for search"
            throw PDFError.openFailed(msg)
        }

        // Authenticate the actor's independent document instance.
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

        if let old = resource.doc {
            mupdf_document_drop(resource.ctx, old)
        }
        self.resource.doc = d
        self.currentPath = filePath
    }
    
    /// Streams search results page-by-page as they are discovered in real time,
    /// prioritizing a local ±50 page window around `nearPage` first for instant (<30ms) nearby hits.
    public func searchStream(query: String, nearPage: Int = 0, options: SearchOptions = SearchOptions(), ocrPages: [Int: PDFOCRPageResult] = [:]) -> AsyncStream<SearchResult> {
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
                
                var pattern: String
                if options.isRegex {
                    pattern = options.wholeWord ? SmartRegexBuilder.applyWholeWord(query) : query
                } else if options.smartSearch {
                    pattern = SmartRegexBuilder.buildPattern(from: query)
                    if options.wholeWord {
                        pattern = SmartRegexBuilder.applyWholeWord(pattern)
                    }
                } else {
                    pattern = SmartRegexBuilder.buildLiteralPattern(from: query)
                    if options.wholeWord {
                        pattern = SmartRegexBuilder.applyWholeWord(pattern)
                    }
                }
                let regexOptions: NSRegularExpression.Options = options.matchCase ? [] : [.caseInsensitive]
                guard !pattern.isEmpty,
                      let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else {
                    continuation.finish()
                    return
                }
                let ignored = options.smartSearch && !options.isRegex ? IgnoredSearchPattern.combinedRegex(options.ignoredPatterns) : nil
                
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
                        // openDocument can run while this task is suspended and drops the document
                        // captured above — stop rather than touch freed memory.
                        guard self.resource.doc == doc else { break }
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
                        let pageText: String
                        if let cText = mupdf_stext_page_text(ctx, stext) {
                            pageText = String(cString: cText)
                            mupdf_free(ctx, cText)
                        } else {
                            pageText = ""
                        }
                        
                        func matches(_ text: String) -> Bool {
                            regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) != nil
                        }
                        // A phrase wrapping onto the next line can have a margin line number
                        // between its halves in the plain text, or a hyphen splitting a word; the
                        // index below moves the numbers aside and joins the word.
                        // Ignored patterns can split a phrase too ("Header(#6820) field").
                        func withoutIgnored(_ text: String) -> String {
                            ignored.map { $0.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "") } ?? text
                        }
                        let joined = Self.joiningWrappedLines(pageText)
                        let hasStextMatch = matches(pageText) || matches(joined)
                            || (ignored != nil && matches(withoutIgnored(joined)))

                        if !hasStextMatch {
                            if let ocr = ocrPages[pageIdx] {
                                for line in ocr.lines {
                                    if Task.isCancelled { break }
                                    let lineString = line.text as NSString
                                    guard lineString.length > 0 else { continue }
                                    let lineMatches = regex.matches(in: line.text, options: [], range: NSRange(location: 0, length: lineString.length))
                                    for match in lineMatches {
                                        if Task.isCancelled { break }
                                        let matchedStr = lineString.substring(with: match.range)
                                        let start = max(0, match.range.location - 30)
                                        let end = min(lineString.length, match.range.location + match.range.length + 30)
                                        var snippet = lineString.substring(with: NSRange(location: start, length: end - start))
                                        if start > 0 { snippet = "..." + snippet }
                                        if end < lineString.length { snippet = snippet + "..." }

                                        let totalLen = CGFloat(max(1, lineString.length))
                                        let startRatio = CGFloat(match.range.location) / totalLen
                                        let lenRatio = CGFloat(match.range.length) / totalLen

                                        // Slice of the line's outline (min 6pt), following any slant.
                                        let lineLength = hypot(line.quad.ur.x - line.quad.ul.x, line.quad.ur.y - line.quad.ul.y)
                                        let minFraction = lineLength > 0 ? 6.0 / lineLength : 0
                                        let endRatio = min(1, startRatio + max(lenRatio, minFraction))
                                        let matchQuad = line.quad.slice(from: startRatio, to: endRatio)

                                        continuation.yield(SearchResult(
                                            pageIndex: pageIdx,
                                            matchedText: matchedStr,
                                            snippet: snippet,
                                            highlightQuads: [matchQuad]
                                        ))
                                    }
                                }
                            }
                            return
                        }
                        
                        var rect = fz_rect()
                        mupdf_page_bounds(ctx, page, &rect, nil)
                        let pageBounds = CGRect(x: CGFloat(rect.x0), y: CGFloat(rect.y0), width: CGFloat(rect.x1 - rect.x0), height: CGFloat(rect.y1 - rect.y0))
                        
                        let structuredPage = StructuredPage.load(fromStext: stext, pageIndex: pageIdx, pageBounds: pageBounds)
                        let (indexedText, charQuads) = structuredPage.searchableIndex
                        let nsIndexed = indexedText as NSString
                        // Each match: its range in the index, its text, and the index units it
                        // covers — all of them, or all but an ignored pattern's in the middle.
                        var found = regex.matches(in: indexedText, options: [], range: NSRange(location: 0, length: nsIndexed.length)).map {
                            (range: $0.range, text: nsIndexed.substring(with: $0.range), units: Array($0.range.location..<NSMaxRange($0.range)))
                        }
                        if let ignored, let stripped = TextWithoutIgnored(indexedText, ignoring: ignored) {
                            let strippedNS = stripped.text as NSString
                            let starts = Set(found.map(\.range.location))
                            for match in regex.matches(in: stripped.text, range: NSRange(location: 0, length: strippedNS.length)) where match.range.length > 0 {
                                let range = stripped.originalRange(of: match.range)
                                guard !starts.contains(range.location) else { continue }
                                found.append((range, strippedNS.substring(with: match.range), stripped.originalOffsets(of: match.range)))
                            }
                            found.sort { $0.range.location < $1.range.location }
                        }

                        for match in found {
                            if Task.isCancelled { break }
                            let matchedStr = match.text
                            
                            let start = max(0, match.range.location - 35)
                            let end = min(nsIndexed.length, match.range.location + match.range.length + 35)
                            let snippet = "..." + nsIndexed.substring(with: NSRange(location: start, length: end - start)).replacingOccurrences(of: "\n", with: " ") + "..."
                            
                            // One highlight per unbroken run of characters, so one doesn't
                            // stretch over an ignored tag in the middle of the match.
                            var runs: [[Int]] = []
                            for unit in match.units {
                                if let last = runs.last?.last, unit == last + 1 { runs[runs.count - 1].append(unit) } else { runs.append([unit]) }
                            }
                            let finalQuads = runs.flatMap { run -> [PDFQuad] in
                                let rawQuads = run.compactMap { $0 < charQuads.count ? charQuads[$0] : nil }
                                let merged = rawQuads.mergedLineQuads()
                                return merged.isEmpty ? rawQuads : merged
                            }
                            
                            continuation.yield(SearchResult(
                                pageIndex: pageIdx,
                                matchedText: matchedStr,
                                snippet: snippet,
                                highlightQuads: finalQuads
                            ))
                        }
                    }
                }
                // MuPDF's store is shared by every context and bounded by its own limit, which
                // evicts only what nothing is using; emptying it would free items other
                // threads are using (see Vendor/README.md, Backported patches).
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    /// `text` without the lines that hold only a number, such as margin line numbers, and with
    /// words hyphenated across lines joined up, as `LineJoin` joins them in the index.
    static func joiningWrappedLines(_ text: String) -> String {
        text.replacingOccurrences(of: "(?m)^[ \\t]*\\d{1,4}[ \\t]*\\n", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(\\p{L})[-\u{2010}][ \\t]*\\n[ \\t]*(\\p{Ll})", with: "$1$2", options: .regularExpression)
            .replacingOccurrences(of: "\u{00AD}[ \\t]*\\n[ \\t]*", with: "", options: .regularExpression)
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
