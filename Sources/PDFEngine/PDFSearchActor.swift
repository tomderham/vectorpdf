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
import Synchronization
import MuPDFBridge

/// One search worker: its own copy of the document on an independent context (one search uses it
/// at a time). Cloned contexts share MuPDF's allocation lock, taken for every allocation and
/// reference count, so workers on clones extract text no faster than one; with their own store and
/// locks they don't wait on each other.
final class SearchResource: @unchecked Sendable {
    let ctx: FZContext
    let doc: FZDocument

    init(filePath: String, password: String?) throws {
        guard let ctx = mupdf_context_create_independent(16 * 1024 * 1024) else {
            throw PDFError.openFailed("Failed to create a context for search")
        }
        var docPtr: FZDocument?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_document_open(ctx, filePath, &docPtr, &errorMsg)
        guard ret == 0, let d = docPtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to open document for search"
            mupdf_context_drop_independent(ctx)
            throw PDFError.openFailed(msg)
        }

        // Authenticate this worker's independent document instance.
        var needsPassword: Int32 = 0
        mupdf_document_needs_password(ctx, d, &needsPassword, &errorMsg)
        if needsPassword != 0 {
            var authenticated: Int32 = 0
            if let password {
                mupdf_document_authenticate_password(ctx, d, password, &authenticated, &errorMsg)
            }
            guard authenticated != 0 else {
                mupdf_document_drop(ctx, d)
                mupdf_context_drop_independent(ctx)
                throw password == nil ? PDFError.passwordRequired : PDFError.incorrectPassword
            }
        }
        self.ctx = ctx
        self.doc = d
    }

    var pageCount: Int {
        var count: Int32 = 0
        mupdf_document_count_pages(ctx, doc, &count, nil)
        return Int(count)
    }

    deinit {
        mupdf_document_drop(ctx, doc)
        mupdf_context_drop_independent(ctx)
    }
}

/// The open document's search workers. A search checks workers out, opening more as it needs
/// them, and returns them when it finishes; up to `capacity` stay open for the next search.
/// Searches still running hold on to theirs, so `close` (another document opened) never frees a
/// document in use; it only stops them and drops the idle ones.
final class SearchWorkerPool: Sendable {
    let filePath: String
    let password: String?
    let capacity: Int
    private let state: Mutex<(idle: [SearchResource], closed: Bool)>

    init(first: SearchResource, filePath: String, password: String?, capacity: Int) {
        self.filePath = filePath
        self.password = password
        self.capacity = capacity
        self.state = Mutex(([first], false))
    }

    var isClosed: Bool { state.withLock { $0.closed } }

    /// An idle worker, or a new one; nil once closed or if the document can't be opened again.
    func checkOut() -> SearchResource? {
        let (worker, closed) = state.withLock { state in (state.idle.popLast(), state.closed) }
        if let worker { return worker }
        guard !closed else { return nil }
        return try? SearchResource(filePath: filePath, password: password)
    }

    func checkIn(_ worker: SearchResource) {
        // A worker that isn't kept is released here, outside the lock.
        _ = state.withLock { state -> SearchResource? in
            guard !state.closed, state.idle.count < capacity else { return worker }
            state.idle.append(worker)
            return nil
        }
    }

    func close() {
        // The idle workers are released here, outside the lock.
        _ = state.withLock { state -> [SearchResource] in
            state.closed = true
            defer { state.idle = [] }
            return state.idle
        }
    }
}

/// The pages a search has left, in the order to search them, shared by its workers.
private final class PageQueue: Sendable {
    private let state: Mutex<(pages: [Int], next: Int)>

    init(_ pages: [Int]) {
        state = Mutex((pages, 0))
    }

    func take() -> Int? {
        state.withLock { state in
            guard state.next < state.pages.count else { return nil }
            defer { state.next += 1 }
            return state.pages[state.next]
        }
    }
}

public actor PDFSearchActor {
    /// Workers for each search: one per performance core, leaving cores for rendering and the UI.
    /// Past six, a worker saves little time (about 7% on a 1,000-page document) for its memory.
    public static let defaultWorkerCount: Int = {
        let active = ProcessInfo.processInfo.activeProcessorCount
        var performanceCores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let cores = sysctlbyname("hw.perflevel0.logicalcpu", &performanceCores, &size, nil, 0) == 0 && performanceCores > 0
            ? Int(performanceCores) : active
        return max(1, min(cores, active - 2, 6))
    }()

    private let workerCount: Int
    private var pool: SearchWorkerPool?
    private var currentPath: String?
    
    public init(workerCount: Int = PDFSearchActor.defaultWorkerCount) {
        self.workerCount = max(1, workerCount)
    }
    
    public func openDocument(filePath: String, password: String? = nil) throws {
        // Keep existing document open until replacement is opened and authenticated. The other
        // workers open their copies when a search first needs them.
        let first = try SearchResource(filePath: filePath, password: password)
        pool?.close()
        self.pool = SearchWorkerPool(first: first, filePath: filePath, password: password, capacity: workerCount)
        self.currentPath = filePath
    }
    
    /// Streams search results page-by-page as they are discovered in real time, prioritizing a
    /// local ±50 page window around `nearPage` first for instant (<30ms) nearby hits. Several
    /// workers search at once, so pages arrive out of order (each page's results together, in
    /// reading order); sort them rather than assume the stream is sorted.
    public func searchStream(query: String, nearPage: Int = 0, options: SearchOptions = SearchOptions(), ocrPages: [Int: PDFOCRPageResult] = [:]) -> AsyncStream<SearchResult> {
        let pool = self.pool
        let workerCount = self.workerCount
        return AsyncStream<SearchResult> { continuation in
            let task = Task {
                guard let pool, let first = pool.checkOut() else {
                    continuation.finish()
                    return
                }
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    pool.checkIn(first)
                    continuation.finish()
                    return
                }
                
                let totalPages = first.pageCount
                guard totalPages > 0 else {
                    pool.checkIn(first)
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
                    pool.checkIn(first)
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
                let queue = PageQueue(localSlice + forwardSlice + backwardSlice)
                
                // Workers take the next page from the shared queue, so the pages around nearPage
                // still report first. Cancelling this task cancels them all.
                await withTaskGroup(of: Void.self) { group in
                    for i in 0..<min(workerCount, totalPages) {
                        group.addTask {
                            guard let worker = i == 0 ? first : pool.checkOut() else { return }
                            defer { pool.checkIn(worker) }
                            var pagesDone = 0
                            // Stop too when another document is opened.
                            while !Task.isCancelled, !pool.isClosed, let pageIdx = queue.take() {
                                let results = autoreleasepool {
                                    Self.matches(onPage: pageIdx, of: worker, regex: regex, ignored: ignored, ocr: ocrPages[pageIdx])
                                }
                                for result in results {
                                    continuation.yield(result)
                                }
                                pagesDone += 1
                                if pagesDone % 5 == 0 {
                                    await Task.yield()
                                }
                            }
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

    /// The matches on one page, in reading order: in its text, or if it has none there, in the
    /// page's OCR result. Uses only `worker`, so workers can run it at the same time.
    private static func matches(onPage pageIdx: Int, of worker: SearchResource, regex: NSRegularExpression, ignored: NSRegularExpression?, ocr: PDFOCRPageResult?) -> [SearchResult] {
        let ctx = worker.ctx
        let doc = worker.doc
        var results: [SearchResult] = []
                
        var pagePtr: FZPage?
        guard mupdf_page_load(ctx, doc, Int32(pageIdx), &pagePtr, nil) == 0, let page = pagePtr else {
            return []
        }
        defer { mupdf_page_drop(ctx, page) }

        var stextPtr: FZStextPage?
        guard mupdf_stext_page_load(ctx, page, &stextPtr, nil) == 0, let stext = stextPtr else {
            return []
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
        let unhyphenated = Self.joiningWrappedLines(pageText, droppingHyphens: true)
        let hasStextMatch = matches(pageText) || matches(joined) || matches(unhyphenated)
            || (ignored != nil && (matches(withoutIgnored(joined)) || matches(withoutIgnored(unhyphenated))))

        if !hasStextMatch {
            if let ocr {
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

                        results.append(SearchResult(
                            pageIndex: pageIdx,
                            matchedText: matchedStr,
                            snippet: snippet,
                            highlightQuads: [matchQuad]
                        ))
                    }
                }
            }
            return results
        }

        var rect = fz_rect()
        mupdf_page_bounds(ctx, page, &rect, nil)
        let pageBounds = CGRect(x: CGFloat(rect.x0), y: CGFloat(rect.y0), width: CGFloat(rect.x1 - rect.x0), height: CGFloat(rect.y1 - rect.y0))

        let structuredPage = StructuredPage.load(fromStext: stext, pageIndex: pageIdx, pageBounds: pageBounds)
        let (indexedText, charQuads, lineBreakHyphens) = structuredPage.searchableIndex
        let nsIndexed = indexedText as NSString
        // Each match: its range in the index, its text, and the index units it
        // covers — all of them, or all but an ignored pattern's in the middle.
        var found = regex.matches(in: indexedText, options: [], range: NSRange(location: 0, length: nsIndexed.length)).map {
            (range: $0.range, text: nsIndexed.substring(with: $0.range), units: Array($0.range.location..<NSMaxRange($0.range)))
        }
        // A hyphen kept at a line break may still split a word: a table cell
        // wraps "DENIED_STA_AFFILIAT-" / "ED_WITH…", so also search without them.
        var removed = lineBreakHyphens.map { NSRange(location: $0, length: 1) }
        if let ignored {
            removed += ignored.matches(in: indexedText, range: NSRange(location: 0, length: nsIndexed.length)).map(\.range)
        }
        if let stripped = TextWithoutIgnored(indexedText, removing: removed) {
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

            results.append(SearchResult(
                pageIndex: pageIdx,
                matchedText: matchedStr,
                snippet: snippet,
                highlightQuads: finalQuads
            ))
        }
        return results
    }

    /// `text` without the lines that hold only a number, such as margin line numbers, and with
    /// lines ending in a hyphen joined up, as `LineJoin` joins them in the index: a word
    /// hyphenated across lines loses its hyphen, another hyphen stays. With `droppingHyphens`,
    /// every hyphen ending a line goes, so a word broken before a capital ("AFFILIAT-" / "ED")
    /// is whole too.
    static func joiningWrappedLines(_ text: String, droppingHyphens: Bool = false) -> String {
        text.replacingOccurrences(of: "(?m)^[ \\t]*\\d{1,4}[ \\t]*\\n", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(\\p{L})[-\u{2010}][ \\t]*\\n[ \\t]*(\\p{Ll})", with: "$1$2", options: .regularExpression)
            .replacingOccurrences(of: "([-\u{2010}])[ \\t]*\\n[ \\t]*", with: droppingHyphens ? "" : "$1", options: .regularExpression)
            .replacingOccurrences(of: "\u{00AD}[ \\t]*\\n[ \\t]*", with: "", options: .regularExpression)
    }

    /// Searches the entire document and returns aggregated results, in page order.
    public func search(query: String, options: SearchOptions = SearchOptions()) async throws -> [SearchResult] {
        var results: [SearchResult] = []
        let stream = searchStream(query: query, options: options)
        for await res in stream {
            results.append(res)
        }
        // Stable, so each page keeps its results in reading order.
        return results.enumerated()
            .sorted { ($0.element.pageIndex, $0.offset) < ($1.element.pageIndex, $1.offset) }
            .map(\.element)
    }
}
