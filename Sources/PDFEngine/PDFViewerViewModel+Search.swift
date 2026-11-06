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
    // MARK: - Search Functionality
    public struct SearchPageGroup: Identifiable, Sendable {
        /// The first match's, since a page split between sections has a group in each.
        public var id: UUID { matches.first?.id ?? UUID() }
        public let pageIndex: Int
        public var matches: [SearchResult]
        
        public init(pageIndex: Int, matches: [SearchResult]) {
            self.pageIndex = pageIndex
            self.matches = matches
        }
    }
    
    public var searchPageGroups: [SearchPageGroup] {
        var groups: [SearchPageGroup] = []
        for match in searchResults {
            if let last = groups.last, last.pageIndex == match.pageIndex {
                groups[groups.count - 1].matches.append(match)
            } else {
                groups.append(SearchPageGroup(pageIndex: match.pageIndex, matches: [match]))
            }
        }
        return groups
    }

    /// The results on the pages of one outline section, in order.
    public struct SearchSectionGroup: Identifiable, Sendable {
        /// The first match's: results out of reading order can bring a section back.
        public var id: UUID { pages.first?.id ?? UUID() }
        /// Nil for results before the document's first outline entry, or with no outline.
        public let section: OutlineSections.Section?
        public var pages: [SearchPageGroup]
    }

    /// The search results by outline section, then by page.
    public var searchSectionGroups: [SearchSectionGroup] {
        let sections = document?.outlineSections ?? OutlineSections(outline: [])
        var groups: [SearchSectionGroup] = []
        for match in searchResults {
            let section = sections.isEmpty ? nil : sections.section(page: match.pageIndex, y: match.highlightQuads.isEmpty ? nil : match.boundingRect.midY)
            if groups.isEmpty || groups[groups.count - 1].section != section {
                groups.append(SearchSectionGroup(section: section, pages: []))
            }
            let last = groups.count - 1
            if let page = groups[last].pages.last, page.pageIndex == match.pageIndex {
                groups[last].pages[groups[last].pages.count - 1].matches.append(match)
            } else {
                groups[last].pages.append(SearchPageGroup(pageIndex: match.pageIndex, matches: [match]))
            }
        }
        return groups
    }

    public func matches(on pageIndex: Int) -> [SearchResult] {
        return searchResultsByPage[pageIndex] ?? []
    }
    
    public func isActiveMatch(_ match: SearchResult) -> Bool {
        guard activeSearchMatchIndex < searchResults.count else { return false }
        return searchResults[activeSearchMatchIndex].id == match.id
    }
    
    public func submitSearch() {
        if searchResults.isEmpty && isSearching {
            // User pressed Return while search is streaming: navigate as soon as results arrive
            autoNavigateOnSearchResults = true
        } else if !searchResults.isEmpty {
            nextSearchMatch()
        } else {
            performSearch(autoNavigate: true)
        }
    }

    public func nextSearchMatch() {
        guard !searchResults.isEmpty else { return }
        if !hasNavigatedToActiveSearchMatch {
            navigateToMatch(at: activeSearchMatchIndex, shouldScrollList: false)
            return
        }
        let nextIndex = (activeSearchMatchIndex + 1) % searchResults.count
        navigateToMatch(at: nextIndex, shouldScrollList: true)
    }
    
    public func previousSearchMatch() {
        guard !searchResults.isEmpty else { return }
        if !hasNavigatedToActiveSearchMatch {
            navigateToMatch(at: activeSearchMatchIndex, shouldScrollList: false)
            return
        }
        let prevIndex = (activeSearchMatchIndex - 1 + searchResults.count) % searchResults.count
        navigateToMatch(at: prevIndex, shouldScrollList: true)
    }
    
    public func navigateToMatch(at index: Int, shouldScrollList: Bool = false) {
        guard index >= 0 && index < searchResults.count else { return }
        hasNavigatedToActiveSearchMatch = true
        activeSearchMatchIndex = index
        let match = searchResults[index]
        self.activeSearchMatchId = match.id
        if shouldScrollList {
            self.searchScrollRevision += 1
        }
        self.currentPageIndex = match.pageIndex
        self.activeScrollTargetId = match.id.uuidString
        self.searchJumpToken &+= 1
        recordRecentSearch()
        pruneCaches(around: match.pageIndex)
        Task {
            await renderPage(match.pageIndex)
        }
    }

    public func navigateToMatch(_ match: SearchResult, shouldScrollList: Bool = false) {
        if let idx = searchResults.firstIndex(where: { $0.id == match.id }) {
            navigateToMatch(at: idx, shouldScrollList: shouldScrollList)
        }
    }
    
    // MARK: - Recent Searches

    /// Puts the current query at the top of this document's recent searches. Called when the user
    /// goes to a match, so the partial words typed on the way to a query aren't kept.
    func recordRecentSearch() {
        setRecentSearches(ReadingStateManager.addingRecentSearch(searchQuery, to: recentSearches))
    }

    /// Searches for a recent query and goes to its nearest match.
    public func selectRecentSearch(_ query: String) {
        searchQuery = query
        performSearch(autoNavigate: true)
    }

    public func clearRecentSearches() {
        setRecentSearches([])
    }

    /// Stores the list with the document's reading state (and so in iCloud when that's on), and
    /// tells other tabs on the same document. A document with no saved state, or one shown in a
    /// transient window, keeps the list in memory only.
    private func setRecentSearches(_ list: [String]) {
        guard list != recentSearches else { return }
        recentSearches = list
        guard !isTransientWindow, let doc = document else { return }
        ReadingStateManager.shared.updateState(
            for: doc.filePath,
            lastPageIndex: currentPageIndex,
            zoomScale: zoomScale,
            snapshots: activeSnapshots,
            recentSearches: list
        )
        NotificationCenter.default.post(
            name: ReadingStateManager.recentSearchesDidChangeNotification,
            object: self,
            userInfo: ["canonicalKey": CloudStorageHelper.canonicalKey(for: doc.filePath)]
        )
    }

    /// One-off whole-document search that leaves the Search sidebar's query and results alone.
    /// Empty until the document has finished opening.
    public func searchWholeDocument(_ query: String, options: SearchOptions = SearchOptions()) async -> [SearchResult] {
        guard isRenderActorReady, document != nil else { return [] }
        return (try? await searchActor.search(query: query, options: withIgnoredPatterns(options))) ?? []
    }

    /// `options` with the ignored patterns from Settings.
    func withIgnoredPatterns(_ options: SearchOptions) -> SearchOptions {
        var options = options
        options.ignoredPatterns = PDFViewerAppCoordinator.shared.enabledIgnoredSearchPatterns
        return options
    }

    public func performSearch(autoNavigate: Bool = false) {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            self.searchResults = []
            self.searchResultsByPage = [:]
            self.isSearching = false
            self.activeSearchMatchIndex = 0
            self.activeSearchMatchId = nil
            self.searchScrollRevision = 0
            self.activeScrollTargetId = nil
            self.hasNavigatedToActiveSearchMatch = false
            self.autoNavigateOnSearchResults = false
            return
        }
        
        self.searchResults = []
        self.searchResultsByPage = [:]
        self.isSearching = true
        self.activeSearchMatchIndex = 0
        self.activeSearchMatchId = nil
        self.searchScrollRevision = 0
        self.activeScrollTargetId = nil
        self.hasNavigatedToActiveSearchMatch = false
        self.autoNavigateOnSearchResults = autoNavigate
        
        let currentNear = self.currentPageIndex
        let localStart = max(0, currentNear - 50)
        let options = withIgnoredPatterns(self.searchOptions)

        if !detectedScannedPages.isEmpty && !isRunningOCR {
            Task { [weak self] in
                await self?.runOCROnAllScannedPages()
            }
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            let stream = await searchActor.searchStream(query: query, nearPage: currentNear, options: options, ocrPages: ocrResults)
            var buffer: [SearchResult] = []
            var earlyResultsBuffer: [SearchResult] = []
            var lastFlushTime = Date()
            var hasSetInitialMatch = false
            
            for await result in stream {
                guard !Task.isCancelled else { break }
                
                if result.pageIndex < localStart {
                    // Suppress early-in-doc results until search completes to eliminate sidebar judder
                    earlyResultsBuffer.append(result)
                } else {
                    buffer.append(result)
                    if self.searchResults.count < 3 || Date().timeIntervalSince(lastFlushTime) > 0.08 {
                        self.flushSearchBuffer(&buffer, nearPage: currentNear, hasSetInitialMatch: &hasSetInitialMatch)
                        lastFlushTime = Date()
                    }
                }
            }
            
            if !buffer.isEmpty && !Task.isCancelled {
                self.flushSearchBuffer(&buffer, nearPage: currentNear, hasSetInitialMatch: &hasSetInitialMatch)
            }
            if !earlyResultsBuffer.isEmpty && !Task.isCancelled {
                self.flushEarlyResultsBuffer(&earlyResultsBuffer, nearPage: currentNear, hasSetInitialMatch: &hasSetInitialMatch)
            }
            if !Task.isCancelled {
                self.isSearching = false
                if !hasSetInitialMatch && !self.searchResults.isEmpty {
                    hasSetInitialMatch = true
                    let idx = self.selectInitialMatchIndex(nearPage: currentNear)
                    self.activeSearchMatchIndex = idx
                    self.activeSearchMatchId = self.searchResults[idx].id
                    self.searchScrollRevision += 1
                    if self.autoNavigateOnSearchResults {
                        self.navigateToMatch(at: idx, shouldScrollList: true)
                    }
                }
            }
        }
    }

    private func selectInitialMatchIndex(nearPage: Int) -> Int {
        guard !self.searchResults.isEmpty else { return 0 }
        if let firstAtOrAfter = self.searchResults.firstIndex(where: { $0.pageIndex >= nearPage }) {
            return firstAtOrAfter
        } else if let lastBefore = self.searchResults.lastIndex(where: { $0.pageIndex <= nearPage }) {
            return lastBefore
        } else {
            return 0
        }
    }
    
    private func flushSearchBuffer(_ buffer: inout [SearchResult], nearPage: Int, hasSetInitialMatch: inout Bool) {
        guard !buffer.isEmpty else { return }
        
        let currentActiveId = self.activeSearchMatchId ?? (
            self.searchResults.indices.contains(self.activeSearchMatchIndex)
                ? self.searchResults[self.activeSearchMatchIndex].id
                : nil
        )
            
        for item in buffer {
            self.searchResultsByPage[item.pageIndex, default: []].append(item)
        }
        self.searchResults.append(contentsOf: buffer)
        buffer.removeAll()
        
        // Keep results sorted in logical reading order: pageIndex ascending, then Y position
        self.searchResults.sort { a, b in
            if a.pageIndex != b.pageIndex {
                return a.pageIndex < b.pageIndex
            }
            let ya = a.highlightQuads.first?.boundingRect.minY ?? 0
            let yb = b.highlightQuads.first?.boundingRect.minY ?? 0
            return ya < yb
        }
        
        if !hasSetInitialMatch {
            // Check if we have discovered a match at or after nearPage
            if let idx = self.searchResults.firstIndex(where: { $0.pageIndex >= nearPage }) {
                hasSetInitialMatch = true
                self.activeSearchMatchIndex = idx
                self.activeSearchMatchId = self.searchResults[idx].id
                self.searchScrollRevision += 1
                if self.autoNavigateOnSearchResults {
                    self.navigateToMatch(at: idx, shouldScrollList: true)
                }
            } else if currentActiveId == nil, !self.searchResults.isEmpty {
                // Temporarily point to the closest match discovered so far until nearPage is reached
                self.activeSearchMatchIndex = self.searchResults.count - 1
                self.activeSearchMatchId = self.searchResults[self.activeSearchMatchIndex].id
            }
        } else if let activeId = currentActiveId, let newIdx = self.searchResults.firstIndex(where: { $0.id == activeId }) {
            let indexChanged = (newIdx != self.activeSearchMatchIndex)
            self.activeSearchMatchIndex = newIdx
            self.activeSearchMatchId = activeId
            if indexChanged {
                self.searchScrollRevision += 1
            }
        }
    }
    
    private func flushEarlyResultsBuffer(_ earlyBuffer: inout [SearchResult], nearPage: Int, hasSetInitialMatch: inout Bool) {
        guard !earlyBuffer.isEmpty else { return }
        
        let currentActiveId = self.activeSearchMatchId ?? (
            self.searchResults.indices.contains(self.activeSearchMatchIndex)
                ? self.searchResults[self.activeSearchMatchIndex].id
                : nil
        )
        
        for item in earlyBuffer {
            self.searchResultsByPage[item.pageIndex, default: []].append(item)
        }
        self.searchResults.append(contentsOf: earlyBuffer)
        earlyBuffer.removeAll()
        
        // Sort all results in logical reading order
        self.searchResults.sort { a, b in
            if a.pageIndex != b.pageIndex {
                return a.pageIndex < b.pageIndex
            }
            let ya = a.highlightQuads.first?.boundingRect.minY ?? 0
            let yb = b.highlightQuads.first?.boundingRect.minY ?? 0
            return ya < yb
        }
        
        if hasSetInitialMatch {
            if let activeId = currentActiveId, let newIdx = self.searchResults.firstIndex(where: { $0.id == activeId }) {
                self.activeSearchMatchIndex = newIdx
                self.activeSearchMatchId = activeId
                // Re-center active match once at completion now that early results were prepended
                self.searchScrollRevision += 1
            }
        } else if !self.searchResults.isEmpty {
            hasSetInitialMatch = true
            let idx = self.selectInitialMatchIndex(nearPage: nearPage)
            self.activeSearchMatchIndex = idx
            self.activeSearchMatchId = self.searchResults[idx].id
            self.searchScrollRevision += 1
            if self.autoNavigateOnSearchResults {
                self.navigateToMatch(at: idx, shouldScrollList: true)
            }
        }
    }
}
