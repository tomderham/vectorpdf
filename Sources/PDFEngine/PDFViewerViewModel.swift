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

/// Progress of the Agent tab's background semantic-indexing pass for the current document. See
/// PDFViewerViewModel.startAgentIndexingIfNeeded.
public enum AgentIndexState: Equatable {
    case idle
    case building(pagesDone: Int, totalPages: Int)
    case ready
    case unavailable(String)
}

/// Observable view model managing document state, rendering, search, and navigation.
@MainActor
public final class PDFViewerViewModel: ObservableObject {
    @Published public private(set) var document: PDFDocumentCore?
    @Published public var currentPageIndex: Int = 0 {
        didSet {
            if currentPageIndex != oldValue {
                updateReadingUserActivity()
            }
        }
    }
    @Published public var zoomScale: CGFloat = 1.0
    @Published public var displayScale: CGFloat = 1.0
    @Published public var isSidebarVisible: Bool = true
    @Published public var renderedPages: [Int: NSImage] = [:]

    // Cloud Download State (iCloud Drive / Dataless File Handling)
    @Published public var isDownloadingFromCloud: Bool = false
    @Published public var cloudDownloadStatusMessage: String? = nil
    private var isCloudDownloadCancelled = false

    // Continuity / Handoff
    private var readingUserActivity: NSUserActivity?

    /// The actual scaling applied to page coordinates on screen.
    /// In .physical mode (Preview default), scales relative to the display's physical DPI.
    /// In .pointToPoint mode, 1 point = 1 screen point (72 DPI).
    public var effectiveZoom: CGFloat {
        zoomScale * (PDFViewerAppCoordinator.shared.scaleMode == .physical ? displayScale : 1.0)
    }

    /// Updates the display scale factor based on the window's screen.
    public func updateDisplayScale(for window: NSWindow?) {
        let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let newScale = PDFViewerAppCoordinator.physicalScale(for: screen)
        guard abs(displayScale - newScale) > 0.001 else { return }
        displayScale = newScale
        renderedPages = [:]
        Task { await renderPage(currentPageIndex) }
    }
    /// Pages currently being rendered by renderActor, avoiding duplicate in-flight render requests.
    private var pagesCurrentlyRendering: Set<Int> = []
    /// Indicates whether renderActor has opened the current document.
    private var isRenderActorReady = false
    private var pagesAwaitingRenderActor: Set<Int> = []
    @Published public var documentTitle: String = "VectorPDF"

    /// Whole-document display-only rotation in 90-degree increments.
    @Published public private(set) var viewRotationDegrees: Int = 0
    /// Per-page Y offsets and total content height adjusted for rotation and two-page mode.
    @Published public private(set) var effectivePageYOffsets: [CGFloat] = []
    @Published public private(set) var effectiveTotalHeight: CGFloat = 0

    private var isRotatedSideways: Bool { viewRotationDegrees == 90 || viewRotationDegrees == 270 }

    /// Displays pages in side-by-side spreads when true.
    @Published public private(set) var isTwoPageMode: Bool = false

    /// The active viewport size of the PDF scroll view, tracked for accurate zoom-to-fit calculations.
    public var currentViewportSize: CGSize?

    /// False whenever rotation or two-page mode is active — the single flag PDFCanvasView checks
    /// before drawing/acting on search highlights, text selection, form widgets, and link clicks,
    /// all of which assume the plain single-column, unrotated layout to compute their screen
    /// position correctly.
    public var isInteractiveViewingMode: Bool { viewRotationDegrees == 0 && !isTwoPageMode }

    public func rotateClockwise() {
        viewRotationDegrees = (viewRotationDegrees + 90) % 360
        isTwoPageMode = false
        recomputeEffectiveLayout()
    }

    public func rotateCounterclockwise() {
        viewRotationDegrees = (viewRotationDegrees + 270) % 360
        isTwoPageMode = false
        recomputeEffectiveLayout()
    }

    public func toggleTwoPageMode() {
        let savedPage = currentPageIndex
        isTwoPageMode.toggle()
        if isTwoPageMode {
            viewRotationDegrees = 0
        }
        recomputeEffectiveLayout()
        currentPageIndex = savedPage
        if isTwoPageMode {
            zoomToFitPage()
        }
    }

    private func recomputeEffectiveLayout() {
        guard let doc = document else {
            effectivePageYOffsets = []
            effectiveTotalHeight = 0
            return
        }
        if isTwoPageMode {
            // Book Mode (Cover Page Offset):
            // Page 0 (Cover) sits alone on Row 0 on the right side of the spread (matching a physical
            // closed book). Subsequent pages 1..N are paired as physical facing spreads: (1,2), (3,4), ...
            // where odd indices (1, 3, 5...) are left-hand verso pages and even indices (2, 4, 6...)
            // are right-hand recto pages, preserving author-intended two-page spreads.
            let pageSpacing: CGFloat = 16.0
            guard !doc.pageBounds.isEmpty else {
                effectivePageYOffsets = []
                effectiveTotalHeight = 0
                return
            }

            var offsets = [CGFloat](repeating: 0, count: doc.pageBounds.count)
            var currentY: CGFloat = 0

            // Row 0: Standalone cover page
            offsets[0] = currentY
            currentY += doc.pageBounds[0].height + pageSpacing

            // Rows 1..N: Facing page pairs (1,2), (3,4), ...
            var i = 1
            while i < doc.pageBounds.count {
                let rightIndex = i + 1
                let rowHeight = rightIndex < doc.pageBounds.count
                    ? max(doc.pageBounds[i].height, doc.pageBounds[rightIndex].height)
                    : doc.pageBounds[i].height
                offsets[i] = currentY
                if rightIndex < doc.pageBounds.count {
                    offsets[rightIndex] = currentY
                }
                currentY += rowHeight + pageSpacing
                i += 2
            }
            effectivePageYOffsets = offsets
            effectiveTotalHeight = currentY
            return
        }
        guard isRotatedSideways else {
            effectivePageYOffsets = doc.pageYOffsets
            effectiveTotalHeight = doc.totalHeight
            return
        }
        // Mirrors PDFDocumentCore's own offset computation, just with each page's width standing
        // in for its (now on-screen-vertical) height — see the property doc comment above.
        let pageSpacing: CGFloat = 16.0
        var offsets: [CGFloat] = []
        offsets.reserveCapacity(doc.pageBounds.count)
        var currentY: CGFloat = 0
        for bounds in doc.pageBounds {
            offsets.append(currentY)
            currentY += bounds.width + pageSpacing
        }
        effectivePageYOffsets = offsets
        effectiveTotalHeight = currentY
    }

    /// Binary search over `effectivePageYOffsets` to find the page index at a given vertical offset,
    /// accounting for rotation and layout mode.
    public func effectivePageIndex(atYOffset y: CGFloat) -> Int {
        guard let doc = document, !effectivePageYOffsets.isEmpty else { return 0 }
        if isTwoPageMode {
            var low = 0
            var high = effectivePageYOffsets.count - 1
            var rowStartPage = 0
            while low <= high {
                let mid = (low + high) / 2
                if effectivePageYOffsets[mid] <= y {
                    rowStartPage = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            if rowStartPage == 0 {
                return 0
            }
            let leftPage = (rowStartPage % 2 == 0) ? rowStartPage - 1 : rowStartPage
            let rightPage = leftPage + 1
            if currentPageIndex == leftPage || currentPageIndex == rightPage {
                return currentPageIndex
            }
            return min(max(leftPage, 0), doc.pageCount - 1)
        }

        var low = 0
        var high = effectivePageYOffsets.count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if effectivePageYOffsets[mid] <= y {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return min(max(result, 0), doc.pageCount - 1)
    }
    
    // Page Metadata
    @Published public var pageLinks: [Int: [SnapshotTarget]] = [:]
    @Published public var pageStructuredData: [Int: StructuredPage] = [:]
    @Published public var activeSelection: (pageIndex: Int, result: SelectionResult)?
    /// Additional page selections when a selection spans across page boundaries.
    @Published public var additionalSelectionPages: [PageSelectionResult] = []
    @Published public var selectionMode: SelectionMode = .readingOrder
    
    // Form Widgets & Editing State
    @Published public var pageFormWidgets: [Int: [PDFFormWidget]] = [:]
    @Published public var isDocumentEdited: Bool = false

    // Annotations & Markup
    @Published public var pageAnnotations: [Int: [PDFAnnotation]] = [:]
    @Published public var isMarkupBarVisible: Bool = false {
        didSet {
            if isMarkupBarVisible {
                isMeasurementBarVisible = false
                isRedactionBarVisible = false
            } else {
                if canvasMode == .draw || canvasMode == .text || canvasMode == .callout || canvasMode == .stamp || canvasMode == .eraser {
                    canvasMode = .select
                }
                pendingSignatureData = nil
            }
        }
    }
    @Published public var canvasMode: CanvasMode = .select
    @Published public var selectedAnnotationColor: AnnotationColor = .yellow
    @Published public var drawStrokeWidth: CGFloat = 2.5
    @Published public var selectedFontSize: CGFloat = 13.0
    @Published public var pendingSignatureData: Data? = nil

    // Engineering Measurement & Takeoff
    @Published public var isMeasurementBarVisible: Bool = false {
        didSet {
            if isMeasurementBarVisible {
                isMarkupBarVisible = false
                isRedactionBarVisible = false
                if canvasMode == .select || canvasMode == .draw || canvasMode == .text || canvasMode == .callout || canvasMode == .redact || canvasMode == .stamp {
                    canvasMode = .measureLength
                }
            } else {
                if canvasMode == .measureLength || canvasMode == .measurePerimeter || canvasMode == .measureArea || canvasMode == .measureAngle || canvasMode == .calibrateScale {
                    canvasMode = .select
                }
            }
        }
    }
    @Published public var currentScaleConfig: PDFScaleConfiguration = .standardMetricOneToOneHundred
    @Published public var pageScaleConfigs: [Int: PDFScaleConfiguration] = [:]
    public var hasMeasurementAnnotations: Bool {
        return pageAnnotations.values.contains { list in
            list.contains { $0.isMeasurement }
        }
    }
    @Published public var isOrthoSnapEnabled: Bool = true
    @Published public var isVertexSnapEnabled: Bool = true
    @Published public var isShowingTakeoffTable: Bool = false
    @Published public var isShowingCalibrationSheet: Bool = false
    @Published public var calibrationMeasuredPoints: Double = 0.0
    @Published public var calibrationPageIndex: Int = 0

    // Navigation History
    @Published public private(set) var canGoBack: Bool = false
    @Published public private(set) var canGoForward: Bool = false
    private var navigationHistory: [Int] = []
    private var navigationHistoryIndex: Int = -1
    private var isNavigatingHistory: Bool = false

    // Thumbnail Cache for Outline/Thumbnails View
    @Published public var thumbnailImages: [Int: NSImage] = [:]
    @Published public var thumbnailVersion: UUID = UUID()
    @Published public var selectedThumbnailPageIndices: Set<Int> = [0]
    @Published public var draggedThumbnailPageIndex: Int? = nil
    @Published public var draggedThumbnailPageIndices: Set<Int> = []
    @Published public var activeThumbnailDropSlot: Int? = nil
    private var selectionAnchorPageIndex: Int = 0
    private var dragWatchdogTimer: Timer?
    private var dragEventMonitor: Any?
    private var thumbnailsLoading: Set<Int> = []
    
    // Search State
    @Published public var searchQuery: String = ""
    @Published public var searchOptions: SearchOptions = SearchOptions()
    @Published public var searchResults: [SearchResult] = []
    @Published public private(set) var searchResultsByPage: [Int: [SearchResult]] = [:]
    @Published public var isSearching: Bool = false
    @Published public var activeSearchMatchIndex: Int = 0
    @Published public var activeSearchMatchId: UUID? = nil
    @Published public var searchScrollRevision: Int = 0
    @Published public var activeScrollTargetId: String? = nil
    @Published public var searchJumpToken: Int = 0
    @Published public var hasNavigatedToActiveSearchMatch: Bool = false
    public var autoNavigateOnSearchResults: Bool = false
    
    // Cross References & Snapshots
    @Published public var activeSnapshots: [SnapshotTarget] = [] {
        didSet {
            if PDFViewerAppCoordinator.shared.activeViewModel === self || PDFViewerViewModel.active === self || PDFViewerAppCoordinator.shared.activeViewModel == nil {
                PDFViewerAppCoordinator.shared.activeAnchors = activeSnapshots
            }
        }
    }
    @Published public var activeSnapshotTarget: SnapshotTarget? = nil
    @Published public var selectedSnapshotId: UUID? = nil
    @Published public var snapshotJumpToken: Int = 0

    // Document Inspection & Metadata
    @Published public var isShowingDocumentProperties: Bool = false
    @Published public var isShowingSplitPDF: Bool = false
    @Published public var documentInspectionReport: PDFDocumentInspectionReport? = nil

    // Redaction, Callout & On-Device OCR
    @Published public var ocrResults: [Int: PDFOCRPageResult] = [:]
    @Published public var isRunningOCR: Bool = false
    private var activeOCRCount: Int = 0 {
        didSet {
            let running = activeOCRCount > 0
            if isRunningOCR != running {
                isRunningOCR = running
            }
        }
    }
    @Published public var detectedScannedPages: Set<Int> = []
    /// Incremented when page indices change to invalidate in-flight OCR requests.
    private var ocrGeneration = 0
    
    // MARK: - Edit & Redact Toolbar State
    @Published public var isRedactionBarVisible: Bool = false {
        didSet {
            if isRedactionBarVisible {
                isMarkupBarVisible = false
                isMeasurementBarVisible = false
                if editRedactTab == .redactRegion {
                    canvasMode = .redact
                }
            } else {
                if canvasMode == .redact {
                    canvasMode = .select
                }
            }
        }
    }
    @Published public var editRedactTab: EditRedactTab = .redactRegion {
        didSet {
            if isRedactionBarVisible {
                if editRedactTab == .redactRegion {
                    canvasMode = .redact
                } else if canvasMode == .redact {
                    canvasMode = .select
                }
            }
        }
    }
    @Published public var redactionColor: RedactionColor = .black
    @Published public var replaceAction: RedactAction = .redact
    @Published public var isRedactionSearchExpanded: Bool = true
    @Published public var redactionSearchQuery: String = ""
    @Published public var redactionPreset: RedactionPreset = .customText {
        didSet {
            if let pattern = redactionPreset.regexPattern {
                redactionSearchQuery = pattern
            } else if redactionPreset == .customText {
                redactionSearchQuery = ""
            }
        }
    }
    @Published public var redactionMatchCase: Bool = false
    @Published public var redactionWholeWord: Bool = false
    @Published public var isRedactionSearching: Bool = false
    @Published public var redactionMatches: [RedactionMatchItem] = []
    @Published public var activeRedactionMatchId: UUID? = nil

    private var redactionSearchTask: Task<Void, Never>?

    // Agent Tab: semantic search (always available on-device) plus optional on-device
    // synthesis (Apple Intelligence-gated) over the currently open document only — see
    // DocumentAgentService.swift and SemanticSearch.swift.
    @Published public var agentQuestion: String = ""
    @Published public var agentIndexState: AgentIndexState = .idle
    @Published public var agentIsAnswering: Bool = false
    @Published public var agentConversation: [AgentTurn] = []

    private let agentEmbedder = TextEmbedder()
    private let agentConversationEngine = DocumentAgentConversation()
    private var agentIndexBuilder: SemanticIndexBuilder?
    private var agentChunks: [EmbeddedChunk] = []
    private var agentIndexingTask: Task<Void, Never>?
    // Retrieval pool sizes for Agent questions.
    private static let embeddingCandidatePoolSize = 24
    private static let lexicalCandidatePoolSize = 10
    private static let maxPassagesForSynthesis = 6
    // Reused so the Agent tab's lazily-built index doesn't need to re-prompt for a password
    // already entered once to open the document (see promptForPasswordAndRetry).
    private var currentDocumentPassword: String?
    // Watches the open file for external changes and reloads it.
    private var fileChangeWatcher: FileChangeWatcher?
    private var workingCopyPath: String?

    private func cleanupWorkingCopy() {
        if let workingPath = workingCopyPath {
            try? FileManager.default.removeItem(atPath: workingPath)
            workingCopyPath = nil
        }
    }

    isolated deinit {
        readingUserActivity?.invalidate()
        readingUserActivity = nil
        cleanupWorkingCopy()
    }

    // Background Concurrency Actors
    // Note: PDFRenderActor and PDFSearchActor each maintain their own cloned MuPDF context
    // and document instance to avoid multi-threaded data races on the C data structures.
    // Capacity matches maxRenderedPageCache's Two-Page Mode value below — display lists are just
    // recorded drawing commands, much lighter than a rasterized bitmap, so caching more is cheap.
    private let renderActor = PDFRenderActor(cacheCapacity: 12)
    private let searchActor = PDFSearchActor()
    private var searchTask: Task<Void, Never>?
    private var debouncedWidgetTasks: [String: Task<Void, Never>] = [:]
    private var pendingWidgetValues: [String: (pageIndex: Int, widgetIndex: Int, value: String)] = [:]
    public let textSelector = SpatialTextSelector()

    // Bounded cache capacity for rendered page bitmaps.
    private var maxRenderedPageCache: Int { isTwoPageMode ? 12 : 4 }
    private let maxStructuredDataCache: Int = 6
    
    // Tab and Window Scoping
    public static weak var active: PDFViewerViewModel?
    public weak var currentWindow: NSWindow?
    @Published public var windowTitlebarHeight: CGFloat = 88.0

    public var effectiveTitlebarHeight: CGFloat {
        if let window = currentWindow ?? NSApplication.shared.keyWindow {
            let h = window.frame.height - window.contentLayoutRect.height
            if h > 0 { return h }
        }
        return windowTitlebarHeight
    }

    public func updateTitlebarHeight() {
        if let window = currentWindow ?? NSApplication.shared.keyWindow {
            let h = window.frame.height - window.contentLayoutRect.height
            if h > 0 && h != windowTitlebarHeight {
                windowTitlebarHeight = h
            }
        }
    }
    public var windowDelegate: PDFViewerWindowDelegate?
    // Adds a document as a new tab in the current window's tab group — used only by drag-and-
    // drop onto a window that already has a document open, which reads as "add this here" by
    // direct-manipulation convention (unlike explicitly choosing Open or a Favorite).
    public var onOpenNewTab: ((URL) -> Void)?
    // Opens a document in a genuinely separate window — used by every *explicit* "open this
    // document" action (File > Open, the toolbar Open button, clicking a Favorite) once this
    // window already has something open, so those all behave identically. See
    // openDocumentPreferringNewWindow(atPath:), which is what actually decides between this and
    // loading into the current, still-empty window.
    public var onOpenNewWindow: ((URL) -> Void)?
    // The saved Tab Group this window was opened as an instance of, if any. Lives here (not just
    // on the View) so both the toolbar menu and the app's menu-bar Favorites menu can read the
    // same value and offer identical "Update Group" / "Save as Group" actions, instead of the
    // menu bar silently lacking capabilities the toolbar has.
    public var groupOrigin: UUID?
    /// True for windows opened by SnapshotWindowManager — a "peek" at some other point in the
    /// document, not the reading position for it. Reading-state save (see saveReadingStateIfNeeded)
    /// is skipped entirely when this is true, so opening a cross-reference and later closing that
    /// window can never overwrite the real reading position with wherever the reference happened
    /// to point.
    public var isTransientWindow: Bool = false

    private var scaleModeCancellable: AnyCancellable?

    public init() {
        scaleModeCancellable = PDFViewerAppCoordinator.shared.$scaleMode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.objectWillChange.send()
                self.renderedPages = [:]
                Task { await self.renderPage(self.currentPageIndex) }
            }

        NotificationCenter.default.addObserver(
            forName: ReadingStateManager.didSyncExternallyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, let doc = self.document else { return }
                if let saved = ReadingStateManager.shared.state(for: doc.filePath) {
                    self.activeSnapshots = saved.snapshots
                    self.regenerateMissingThumbnails()
                }
            }
        }
    }

    public func loadDocument(from path: String, password: String? = nil) async {
        if isDocumentEdited && document?.filePath != path {
            let canProceed = promptSaveBeforeClosingIfNeeded()
            guard canProceed else { return }
        }
        
        PDFViewerViewModel.active = self
        PDFViewerAppCoordinator.shared.registerActive(self)
        // Persist the *outgoing* document's reading position before switching away from it —
        // this is the primary save point for "resume where I left off" (window-close and app-quit
        // are the other two; see saveReadingStateIfNeeded). Skipped entirely for transient
        // (snapshot/reference) windows.
        saveReadingStateIfNeeded()
        // Cancel any active search task immediately
        searchTask?.cancel()
        searchTask = nil
        cleanupWorkingCopy()

        do {
            let resolvedURL = CloudStorageHelper.resolveActualURL(for: URL(fileURLWithPath: path))
            var actualPath = resolvedURL.path

            // Check if file is evicted / dataless or downloading
            let (isEvicted, isDownloading) = CloudStorageHelper.checkDownloadStatus(for: resolvedURL)
            if isEvicted || isDownloading {
                let provider = CloudStorageHelper.detectProvider(for: resolvedURL.path)
                let providerTitle = provider.rawValue
                self.isDownloadingFromCloud = true
                self.cloudDownloadStatusMessage = "Downloading from \(providerTitle)…"
                do {
                    isCloudDownloadCancelled = false
                    try CloudStorageHelper.startDownloadIfNeeded(for: resolvedURL)
                    let downloaded = await waitForCloudDownload(url: resolvedURL, timeoutSeconds: 30)
                    self.isDownloadingFromCloud = false
                    if isCloudDownloadCancelled {
                        isCloudDownloadCancelled = false
                        self.cloudDownloadStatusMessage = nil
                        return
                    }
                    if !downloaded {
                        self.showErrorAlert(
                            title: "Document in \(providerTitle)",
                            message: "“\(resolvedURL.lastPathComponent)” is stored in \(providerTitle) and could not be downloaded right now. Please check your internet connection and try again."
                        )
                        return
                    }
                    actualPath = resolvedURL.path
                } catch {
                    self.isDownloadingFromCloud = false
                    self.showErrorAlert(
                        title: "Download Failed",
                        message: "Failed to download “\(resolvedURL.lastPathComponent)” from \(providerTitle): \(error.localizedDescription)"
                    )
                    return
                }
            }

            let doc = try await Task.detached(priority: .userInitiated) {
                try PDFDocumentCore(filePath: actualPath, password: password)
            }.value
            // Park render requests until renderActor has opened the new file.
            isRenderActorReady = false
            pagesAwaitingRenderActor.removeAll()
            pagesCurrentlyRendering.removeAll()
            self.document = doc
            self.currentDocumentPassword = password
            let fileURL = URL(fileURLWithPath: actualPath)
            let fileName = fileURL.lastPathComponent
            self.documentTitle = fileName
            PDFViewerAppCoordinator.shared.registerActive(self)
            PDFViewerAppCoordinator.shared.noteRecentDocument(fileURL)

            // Set representedURL and window title on this tab's window
            if let window = currentWindow ?? NSApplication.shared.keyWindow {
                window.title = fileName
                window.representedURL = fileURL
                window.isDocumentEdited = false
                if !isTransientWindow && window.tabGroup?.isTabBarVisible != true {
                    window.toggleTabBar(nil)
                }
                TabBarAppearanceHelper.refreshTabs(for: window)
            }

            self.isDocumentEdited = false
            self.pageFormWidgets = [:]
            self.renderedPages = [:]
            self.searchResults = []
            self.searchResultsByPage = [:]
            self.activeSearchMatchIndex = 0
            self.activeSearchMatchId = nil
            self.searchScrollRevision = 0
            self.hasNavigatedToActiveSearchMatch = false
            self.autoNavigateOnSearchResults = false
            self.activeSnapshots = []
            self.selectedSnapshotId = nil
            self.pageLinks = [:]
            self.pageStructuredData = [:]
            self.activeSelection = nil
            self.additionalSelectionPages = []
            self.pageAnnotations = [:]
            self.pageScaleConfigs = [:]
            self.ocrResults = [:]
            self.detectedScannedPages = []
            self.ocrGeneration += 1
            self.startScannedPageDetection()
            self.navigationHistory = [0]
            self.navigationHistoryIndex = 0
            self.canGoBack = false
            self.canGoForward = false
            self.thumbnailImages = [:]
            self.thumbnailsLoading.removeAll()
            self.currentPageIndex = 0
            self.zoomScale = 1.0
            let initialScreen = (currentWindow ?? NSApplication.shared.keyWindow)?.screen ?? NSScreen.main ?? NSScreen.screens.first
            self.displayScale = PDFViewerAppCoordinator.physicalScale(for: initialScreen)
            // Reset rotation and spread layout for newly opened document.
            self.viewRotationDegrees = 0
            self.isTwoPageMode = false
            self.recomputeEffectiveLayout()
            self.isSidebarVisible = (doc.pageCount > 1)

            // Reset Agent state for newly opened document.
            self.agentIndexingTask?.cancel()
            self.agentIndexingTask = nil
            self.agentIndexBuilder = nil
            self.agentChunks = []
            self.agentIndexState = .idle
            self.agentQuestion = ""
            self.agentConversation = []
            self.agentIsAnswering = false
            self.agentConversationEngine.reset()

            // Restore saved reading position for non-transient windows.
            if !isTransientWindow, let saved = ReadingStateManager.shared.state(for: actualPath) {
                self.currentPageIndex = min(max(saved.lastPageIndex, 0), max(doc.pageCount - 1, 0))
                self.zoomScale = saved.zoomScale
                self.activeSnapshots = saved.snapshots
            }

            try await renderActor.openDocument(filePath: actualPath, password: password)
            isRenderActorReady = true
            try await searchActor.openDocument(filePath: actualPath, password: password)

            let parked = pagesAwaitingRenderActor
            pagesAwaitingRenderActor.removeAll()
            for page in parked where page != currentPageIndex {
                Task { await renderPage(page) }
            }
            await renderPage(currentPageIndex)
            loadPageMetadata(currentPageIndex)
            regenerateMissingThumbnails()

            // (Re-)armed on every successful load, including a reload triggered by this very
            // watcher — that's what picks the new file back up after handleExternalFileChange
            // calls back into loadDocument.
            armFileChangeWatcher(path: actualPath)
            updateReadingUserActivity()
        } catch PDFError.passwordRequired {
            isRenderActorReady = true
            await promptForPasswordAndRetry(path: path, wasIncorrect: false)
        } catch PDFError.incorrectPassword {
            isRenderActorReady = true
            await promptForPasswordAndRetry(path: path, wasIncorrect: true)
        } catch {
            // Never leave the render path parked behind a load that didn't complete.
            isRenderActorReady = true
            print("Failed to load document: \(error)")
            self.showErrorAlert(
                title: "Failed to Open Document",
                message: "“\((path as NSString).lastPathComponent)” could not be opened: \(error.localizedDescription)"
            )
        }
    }

    /// Called when the open file changes on disk — reloads it live, asking first if this window
    /// has unsaved edits that would otherwise be silently discarded.
    private func handleExternalFileChange(path: String) async {
        // The document (or this whole window) may have moved on since this was scheduled — a
        // stale notification from a watcher that's since been replaced/torn down.
        guard document?.filePath == path else { return }

        if isDocumentEdited {
            if Self.isRunningTests {
                return
            }
            let alert = NSAlert()
            alert.messageText = "File Changed on Disk"
            alert.informativeText = "“\(documentTitle)” was changed by another application, but this window has unsaved changes. Reload it and lose them, or keep what's shown here?"
            alert.addButton(withTitle: "Reload from Disk")
            alert.addButton(withTitle: "Keep My Changes")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        await loadDocument(from: path, password: currentDocumentPassword)
    }

    /// Prompts for this document's password (an NSAlert with a secure text field, matching
    /// promptOpenFile's NSOpenPanel / promptSaveCurrentWindowAsGroup's NSAlert style elsewhere in
    /// this file) and, if one is entered, retries loadDocument with it. Cancelling just leaves
    /// this window/tab without a document, same as any other failed open.
    private func promptForPasswordAndRetry(path: String, wasIncorrect: Bool) async {
        guard !Self.isRunningTests else { return }
        let alert = NSAlert()
        alert.messageText = wasIncorrect ? "Incorrect Password" : "Password Required"
        alert.informativeText = "“\(URL(fileURLWithPath: path).lastPathComponent)” is password-protected. Enter the password to open it."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response: NSApplication.ModalResponse
        if let window = currentWindow ?? NSApplication.shared.keyWindow, window.attachedSheet == nil {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { resp in
                    continuation.resume(returning: resp)
                }
            }
        } else {
            response = alert.runModal()
        }

        guard response == .alertFirstButtonReturn else { return }
        let password = field.stringValue
        guard !password.isEmpty else { return }
        await loadDocument(from: path, password: password)
    }
    
    public func renderPage(_ pageIndex: Int) async {
        guard renderedPages[pageIndex] == nil, !pagesCurrentlyRendering.contains(pageIndex) else { return }
        guard isRenderActorReady else {
            pagesAwaitingRenderActor.insert(pageIndex)
            return
        }
        pagesCurrentlyRendering.insert(pageIndex)
        // Everything the result depends on is captured up front: zoom or the document can change
        // while the actor renders, and the finished bitmap must be judged against what it was
        // rendered for, not whatever is current by the time it comes back.
        let startDocument = document
        let startZoom = effectiveZoom
        var isStale = false
        do {
            let window = currentWindow ?? NSApplication.shared.keyWindow
            let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
            let targetScale = startZoom * backingScale
            // Supersampling quality floor: at small zooms (e.g. 25%-50%), rendering text in MuPDF below
            // ~1.5 scale causes FreeType glyph stems to drop below 1 pixel and appear faint/gray.
            // Rendering at max(targetScale, 1.5) and downsampling via CoreGraphics high-quality area
            // averaging preserves high-contrast, razor-sharp glyph outlines.
            let renderScale = max(targetScale, 1.5)
            let rendered = try await renderActor.renderPage(pageIndex: pageIndex, scale: renderScale)
            if document === startDocument, effectiveZoom == startZoom {
                // Sized from the page's native bounds, not from the bitmap: the actor may have
                // clamped the render scale (see PDFRenderActor.maxRenderDimension), which would
                // otherwise shrink the image's point size at high zoom.
                let nsImage = NSImage(
                    cgImage: rendered.image,
                    size: NSSize(width: rendered.nativeBounds.width * startZoom, height: rendered.nativeBounds.height * startZoom)
                )
                renderedPages[pageIndex] = nsImage
                // Update page bounds and layout if placeholder dimensions differed.
                if document?.recordActualPageBounds(rendered.nativeBounds, forPage: pageIndex) == true {
                    recomputeEffectiveLayout()
                }
                loadPageMetadata(pageIndex)
                pruneCaches(around: pageIndex)
            } else {
                isStale = true
            }
        } catch {
            print("Failed to render page \(pageIndex): \(error)")
        }
        pagesCurrentlyRendering.remove(pageIndex)
        // A request that arrived while this one was in flight was dropped by the guard above, so a
        // discarded result has to be redone here or the page would stay blank.
        if isStale {
            await renderPage(pageIndex)
        }
    }

    public func evictRenderedPage(_ pageIndex: Int) {
        renderedPages.removeValue(forKey: pageIndex)
    }
    
    public func notifyPageAppeared(_ pageIndex: Int) {
        Task {
            await renderPage(pageIndex)
        }
    }
    
    public func notifyPageDisappeared(_ pageIndex: Int) {
        if abs(pageIndex - currentPageIndex) > 2 {
            evictRenderedPage(pageIndex)
        }
    }
    
    public func pruneCaches(around targetPage: Int) {
        if renderedPages.count > maxRenderedPageCache {
            let sortedByDistance = renderedPages.keys.sorted {
                abs($0 - targetPage) > abs($1 - targetPage)
            }
            let toRemove = renderedPages.count - maxRenderedPageCache
            for i in 0..<toRemove {
                renderedPages.removeValue(forKey: sortedByDistance[i])
            }
        }
        
        if pageStructuredData.count > maxStructuredDataCache {
            let sortedByDistance = pageStructuredData.keys.sorted {
                abs($0 - targetPage) > abs($1 - targetPage)
            }
            let toRemove = pageStructuredData.count - maxStructuredDataCache
            for i in 0..<toRemove {
                pageStructuredData.removeValue(forKey: sortedByDistance[i])
            }
        }
        
        if pageLinks.count > maxStructuredDataCache {
            let sortedByDistance = pageLinks.keys.sorted {
                abs($0 - targetPage) > abs($1 - targetPage)
            }
            let toRemove = pageLinks.count - maxStructuredDataCache
            for i in 0..<toRemove {
                pageLinks.removeValue(forKey: sortedByDistance[i])
            }
        }
        
        if pageFormWidgets.count > maxStructuredDataCache * 2 {
            let sortedByDistance = pageFormWidgets.keys.sorted {
                abs($0 - targetPage) > abs($1 - targetPage)
            }
            let toRemove = pageFormWidgets.count - (maxStructuredDataCache * 2)
            for i in 0..<toRemove {
                pageFormWidgets.removeValue(forKey: sortedByDistance[i])
            }
        }
    }
    
    public func loadPageMetadata(_ pageIndex: Int) {
        guard let doc = self.document else { return }
        if pageLinks[pageIndex] == nil {
            pageLinks[pageIndex] = doc.loadLinks(for: pageIndex)
        }
        if pageStructuredData[pageIndex] == nil {
            pageStructuredData[pageIndex] = doc.loadStructuredPage(for: pageIndex)
        }
        if pageFormWidgets[pageIndex] == nil {
            pageFormWidgets[pageIndex] = doc.loadFormWidgets(for: pageIndex)
        }
        // Load stored drawing scale for the page.
        if pageScaleConfigs[pageIndex] == nil, let stored = doc.loadPageScale(pageIndex: pageIndex) {
            pageScaleConfigs[pageIndex] = stored
        }
    }
    
    public func jumpToPage(_ pageIndex: Int) {
        if let doc = document {
            guard pageIndex >= 0, pageIndex < doc.pageCount else { return }
        }
        self.currentPageIndex = pageIndex
        if !isNavigatingHistory {
            recordNavigationLocation(pageIndex)
        }
        pruneCaches(around: pageIndex)
        Task {
            await renderPage(pageIndex)
        }
    }
    
    public var canGoPreviousPage: Bool {
        guard let doc = document, doc.pageCount > 0 else { return false }
        return currentPageIndex > 0
    }

    public var canGoNextPage: Bool {
        guard let doc = document, doc.pageCount > 0 else { return false }
        if isTwoPageMode {
            if currentPageIndex == 0 {
                return doc.pageCount > 1
            }
            let isLeft = currentPageIndex % 2 == 1
            let spreadStart = isLeft ? currentPageIndex : currentPageIndex - 1
            return spreadStart + 2 < doc.pageCount
        } else {
            return currentPageIndex < doc.pageCount - 1
        }
    }

    public func nextPage() {
        guard let doc = document, doc.pageCount > 0 else { return }
        if isTwoPageMode {
            if currentPageIndex == 0 {
                if doc.pageCount > 1 {
                    jumpToPage(1)
                }
            } else {
                let isLeft = currentPageIndex % 2 == 1
                let spreadStart = isLeft ? currentPageIndex : currentPageIndex - 1
                let nextSpreadStart = spreadStart + 2
                if nextSpreadStart < doc.pageCount {
                    jumpToPage(nextSpreadStart)
                }
            }
        } else {
            guard currentPageIndex + 1 < doc.pageCount else { return }
            jumpToPage(currentPageIndex + 1)
        }
    }
    
    public func previousPage() {
        guard let doc = document, doc.pageCount > 0, currentPageIndex > 0 else { return }
        if isTwoPageMode {
            if currentPageIndex <= 2 {
                jumpToPage(0)
            } else {
                let isLeft = currentPageIndex % 2 == 1
                let spreadStart = isLeft ? currentPageIndex : currentPageIndex - 1
                let prevSpreadStart = spreadStart - 2
                if prevSpreadStart >= 1 {
                    jumpToPage(prevSpreadStart)
                } else {
                    jumpToPage(0)
                }
            }
        } else {
            jumpToPage(currentPageIndex - 1)
        }
    }

    public func goToFirstPage() {
        jumpToPage(0)
    }

    public func goToLastPage() {
        guard let doc = document, doc.pageCount > 0 else { return }
        jumpToPage(doc.pageCount - 1)
    }

    // MARK: - Navigation History (Back / Forward)

    public func recordNavigationLocation(_ pageIndex: Int) {
        guard !isNavigatingHistory else { return }
        if navigationHistory.isEmpty {
            navigationHistory = [pageIndex]
            navigationHistoryIndex = 0
        } else {
            if navigationHistoryIndex < navigationHistory.count - 1 {
                navigationHistory = Array(navigationHistory.prefix(navigationHistoryIndex + 1))
            }
            if navigationHistory.last != pageIndex {
                navigationHistory.append(pageIndex)
                if navigationHistory.count > 50 {
                    navigationHistory.removeFirst()
                }
                navigationHistoryIndex = navigationHistory.count - 1
            }
        }
        updateNavigationHistoryState()
    }

    private func updateNavigationHistoryState() {
        canGoBack = navigationHistoryIndex > 0
        canGoForward = navigationHistoryIndex >= 0 && navigationHistoryIndex < navigationHistory.count - 1
    }

    public func goBack() {
        guard canGoBack, navigationHistoryIndex > 0 else { return }
        navigationHistoryIndex -= 1
        let targetPage = navigationHistory[navigationHistoryIndex]
        isNavigatingHistory = true
        jumpToPage(targetPage)
        isNavigatingHistory = false
        updateNavigationHistoryState()
    }

    public func goForward() {
        guard canGoForward, navigationHistoryIndex < navigationHistory.count - 1 else { return }
        navigationHistoryIndex += 1
        let targetPage = navigationHistory[navigationHistoryIndex]
        isNavigatingHistory = true
        jumpToPage(targetPage)
        isNavigatingHistory = false
        updateNavigationHistoryState()
    }
    
    // MARK: - Search Functionality
    public struct SearchPageGroup: Identifiable, Sendable {
        public var id: Int { pageIndex }
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
        let options = self.searchOptions

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
    
    // MARK: - Text Selection
    public func handleDragSelect(pageIndex: Int, startPagePoint: CGPoint, currentPagePoint: CGPoint, forceMode: SelectionMode? = nil) {
        guard let stext = pageStructuredData[pageIndex] ?? document?.loadStructuredPage(for: pageIndex) else { return }
        let mode = forceMode ?? selectionMode
        let res = textSelector.selectText(on: stext, from: startPagePoint, to: currentPagePoint, mode: mode)
        if !res.text.isEmpty || (!res.highlightQuads.isEmpty && mode == .rectangularArea) {
            self.activeSelection = (pageIndex: pageIndex, result: res)
            self.additionalSelectionPages = []
        }
    }

    public func selectWord(at pagePoint: CGPoint, pageIndex: Int) {
        guard let stext = pageStructuredData[pageIndex] ?? document?.loadStructuredPage(for: pageIndex) else { return }
        if let res = textSelector.selectWord(at: pagePoint, on: stext) {
            self.activeSelection = (pageIndex: pageIndex, result: res)
            self.additionalSelectionPages = []
        }
    }

    public func selectLine(at pagePoint: CGPoint, pageIndex: Int) {
        guard let stext = pageStructuredData[pageIndex] ?? document?.loadStructuredPage(for: pageIndex) else { return }
        if let res = textSelector.selectLine(at: pagePoint, on: stext) {
            self.activeSelection = (pageIndex: pageIndex, result: res)
            self.additionalSelectionPages = []
        }
    }

    // MARK: - Translation Support
    @Published public var translationTargetText: String? = nil
    @Published public var isPresentingTranslation: Bool = false

    public func translateSelection() {
        let text = activeSelectionCombinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            self.translationTargetText = text
            self.isPresentingTranslation = true
            return
        }
        #endif
        if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://translate.google.com/?sl=auto&tl=en&text=\(encoded)") {
            PDFViewerAppCoordinator.shared.openExternalURL(url)
        }
    }

    // MARK: - Speech Support
    public var isSpeaking: Bool {
        PDFSpeechCoordinator.shared.isSpeaking
    }

    public func startSpeakingSelection() {
        let text = activeSelectionCombinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        PDFSpeechCoordinator.shared.startSpeaking(text)
    }

    public func stopSpeaking() {
        PDFSpeechCoordinator.shared.stopSpeaking()
    }

    public func toggleSpeakingSelection() {
        if isSpeaking {
            stopSpeaking()
        } else {
            startSpeakingSelection()
        }
    }

    /// Handles reading-order text selection spanning across page boundaries.
    public func handleCrossPageDragSelect(pageA: Int, pointA: CGPoint, pageB: Int, pointB: CGPoint) {
        guard pageA != pageB else {
            handleDragSelect(pageIndex: pageA, startPagePoint: pointA, currentPagePoint: pointB)
            return
        }
        let (firstPage, firstPoint, lastPage, lastPoint) = pageA < pageB ? (pageA, pointA, pageB, pointB) : (pageB, pointB, pageA, pointA)

        var results: [PageSelectionResult] = []
        for pageIdx in firstPage...lastPage {
            guard let stext = pageStructuredData[pageIdx] ?? document?.loadStructuredPage(for: pageIdx) else { continue }
            let topLeft = CGPoint(x: stext.bounds.minX, y: stext.bounds.minY)
            let bottomRight = CGPoint(x: stext.bounds.maxX, y: stext.bounds.maxY)

            let from: CGPoint
            let to: CGPoint
            if pageIdx == firstPage {
                from = firstPoint
                to = bottomRight
            } else if pageIdx == lastPage {
                from = topLeft
                to = lastPoint
            } else {
                // Fully intervening page — select it in its entirety.
                from = topLeft
                to = bottomRight
            }

            let res = textSelector.selectText(on: stext, from: from, to: to, mode: .readingOrder)
            if !res.text.isEmpty || !res.highlightQuads.isEmpty {
                results.append(PageSelectionResult(pageIndex: pageIdx, result: res))
            }
        }

        guard let first = results.first else {
            self.activeSelection = nil
            self.additionalSelectionPages = []
            return
        }
        self.activeSelection = (pageIndex: first.pageIndex, result: first.result)
        self.additionalSelectionPages = Array(results.dropFirst())
    }

    /// Selects all text on the current page — the PDF-content equivalent of the Edit menu's
    /// "Select All" (see PDFCanvasView.selectAll), which otherwise does nothing when the canvas
    /// itself has focus rather than some other text control. Deliberately page-scoped rather than
    /// whole-document, to keep this simple: reuses the same "select a page in full" corner-to-
    /// corner trick already used for pages fully spanned by a cross-page drag, just above.
    public func selectAllOnCurrentPage() {
        guard let stext = pageStructuredData[currentPageIndex] ?? document?.loadStructuredPage(for: currentPageIndex) else { return }
        let topLeft = CGPoint(x: stext.bounds.minX, y: stext.bounds.minY)
        let bottomRight = CGPoint(x: stext.bounds.maxX, y: stext.bounds.maxY)
        handleDragSelect(pageIndex: currentPageIndex, startPagePoint: topLeft, currentPagePoint: bottomRight, forceMode: .readingOrder)
    }

    /// The full selected text, combining `activeSelection` with any further pages in
    /// `additionalSelectionPages` in page order — for an ordinary single-page selection this is
    /// just that one page's text, unchanged.
    public var activeSelectionCombinedText: String {
        guard let sel = activeSelection else { return "" }
        return ([sel.result.text] + additionalSelectionPages.map { $0.result.text })
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    public func copyActiveSelection() {
        let combined = activeSelectionCombinedText
        guard !combined.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(combined, forType: .string)
    }
    
    /// Extracts a cropped high-resolution NSImage from the active rectangular marquee selection.
    public func renderCroppedSelection(scale: CGFloat = 2.0) -> NSImage? {
        guard let sel = activeSelection, let doc = document else { return nil }
        let pageIdx = sel.pageIndex
        guard doc.pageBounds.indices.contains(pageIdx) else { return nil }
        let pageBounds = doc.pageBounds[pageIdx]
        let targetRect = sel.result.boundingRect
        guard targetRect.width > 2 && targetRect.height > 2 else { return nil }
        
        guard let pageImage = renderedPages[pageIdx],
              let cgImage = pageImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let scaleX = CGFloat(cgImage.width) / pageBounds.width
        let scaleY = CGFloat(cgImage.height) / pageBounds.height
        
        let cropX = max(0, (targetRect.minX - pageBounds.minX) * scaleX)
        let cropY = max(0, (targetRect.minY - pageBounds.minY) * scaleY)
        let cropW = min(CGFloat(cgImage.width) - cropX, targetRect.width * scaleX)
        let cropH = min(CGFloat(cgImage.height) - cropY, targetRect.height * scaleY)
        
        guard cropW > 0 && cropH > 0 else { return nil }
        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        
        return NSImage(cgImage: cropped, size: NSSize(width: targetRect.width, height: targetRect.height))
    }
    
    /// Copies the active rectangular selection as high-DPI image (PNG primary, TIFF fallback, and extracted text) to NSPasteboard.general
    public func copyActiveScreenshot() {
        guard let image = renderCroppedSelection() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()

        let item = NSPasteboardItem()
        if let tiffData = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiffData) {
            if let pngData = rep.representation(using: .png, properties: [:]) {
                item.setData(pngData, forType: .png)
            }
            item.setData(tiffData, forType: .tiff)
        }
        if let sel = activeSelection, !sel.result.text.isEmpty {
            item.setString(sel.result.text, forType: .string)
        }
        pb.writeObjects([item])
    }
    
    /// Prompts an AppKit NSSavePanel to save the active screenshot as a PNG file.
    public func saveActiveScreenshot() {
        guard let image = renderCroppedSelection() else { return }
        guard let tiffData = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Screenshot_Page_\(currentPageIndex + 1).png"
        panel.title = "Save Screenshot As"
        panel.prompt = "Save Screenshot"
        
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url {
                try? pngData.write(to: url)
            }
        }
        
        if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
    
    /// Dispatches appropriate copy action depending on selection mode.
    public func copyCommandAction() {
        if let sel = activeSelection, sel.result.mode == .rectangularArea {
            copyActiveScreenshot()
        } else {
            copyActiveSelection()
        }
    }
    
    public func clearSelection() {
        self.activeSelection = nil
        self.additionalSelectionPages = []
    }

    /// Builds a SnapshotTarget from the current selection, without saving it anywhere — shared by
    /// addSnapshotFromSelection() (saves to the sidebar list) and openSelectionInNewWindow()
    /// (opens it directly in a new window without saving a card). For a selection spanning more
    /// than one page, the target itself (page/rect/thumbnail) always anchors to the *first* page
    /// — "jump back to this snapshot" for a passage that crosses a page break most naturally means
    /// jumping to where it begins — but the label/snippet reflect the full combined text.
    public func buildSnapshotTargetFromSelection() -> SnapshotTarget? {
        guard let sel = activeSelection else { return nil }
        let pageIdx = sel.pageIndex
        let bounds = (document?.pageBounds.indices.contains(pageIdx) == true)
            ? document!.pageBounds[pageIdx]
            : CGRect(x: 0, y: 0, width: 612, height: 792)
        let combinedText = activeSelectionCombinedText

        let labelText: String
        if !combinedText.isEmpty {
            let firstLine = combinedText.components(separatedBy: .newlines).first ?? combinedText
            let normalized = firstLine.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            let truncated = normalized.truncatedAtWordBoundary(maxLength: 45)
            labelText = truncated.isEmpty ? "Anchor (Page \(pageIdx + 1))" : truncated
        } else if sel.result.mode == .rectangularArea {
            labelText = "Area Anchor (Page \(pageIdx + 1))"
        } else {
            // A reading-order selection with nothing extractable (visible highlight, empty
            // text) — rare, but possible; "Area Anchor" would be actively misleading here.
            labelText = "Anchor (Page \(pageIdx + 1))"
        }

        // Only generate a screenshot for rectangular/area selections, where boundingRect is
        // exactly the dragged rectangle — a clean, correct crop. For text (reading-order)
        // selections, boundingRect is the union of every selected line's quad, which for any
        // multi-line/wrapped selection spans the full width between the two, pulling in
        // whatever unselected content sits between them (e.g. the rest of a two-column layout)
        // — a crop that looks distorted/wrong relative to what was actually selected. Text
        // selections rely on the extracted text alone, which is exact by construction.
        var thumbData: Data? = nil
        if sel.result.mode == .rectangularArea, let image = renderedPages[pageIdx] {
            thumbData = makeThumbnail(from: image, pageBounds: bounds, targetRect: sel.result.boundingRect)
        }

        let targetRect: CGRect
        if sel.result.mode == .rectangularArea {
            targetRect = sel.result.boundingRect
        } else if let firstLineQuad = sel.result.highlightQuads.mergedLineQuads().first {
            // For reading-order selections, anchor targetRect to the first line's quads so
            // multi-line or multi-column selections don't create an inflated box covering unselected
            // columns and gutters.
            targetRect = firstLineQuad.boundingRect
        } else {
            targetRect = sel.result.boundingRect
        }
        let targetPoint = CGPoint(x: targetRect.midX, y: targetRect.midY)

        return SnapshotTarget(
            label: labelText,
            snippet: combinedText,
            targetPage: pageIdx,
            targetPoint: targetPoint,
            targetRect: targetRect,
            sourceRect: targetRect,
            sourcePage: pageIdx,
            thumbnailData: thumbData
        )
    }

    public func addSnapshotFromSelection() {
        guard let target = buildSnapshotTargetFromSelection() else { return }
        addSnapshotTarget(target)
    }

    /// Opens the current selection (text or area) in a new window at that exact location,
    /// without saving a snapshot card — for a one-off "let me see this next to what I'm reading"
    /// without cluttering the Snapshots list.
    public func openSelectionInNewWindow() {
        guard let target = buildSnapshotTargetFromSelection() else { return }
        openSnapshotInNewWindow(target)
    }

    /// Builds a SnapshotTarget from a search result row, representing a text shortcut containing
    /// the matched hit and its surrounding context words.
    public func buildSnapshotTarget(from match: SearchResult) -> SnapshotTarget {
        let unionRect = match.highlightQuads.reduce(into: CGRect.null) { rect, quad in
            rect = rect.isNull ? quad.boundingRect : rect.union(quad.boundingRect)
        }
        let targetRect = unionRect.isNull ? nil : unionRect
        let targetPoint = targetRect.map { CGPoint(x: $0.midX, y: $0.midY) }

        let label = match.matchedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = label.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let truncated = normalized.truncatedAtWordBoundary(maxLength: 45)
        let cleanLabel = truncated.isEmpty ? "Search Match (Page \(match.pageIndex + 1))" : truncated

        return SnapshotTarget(
            label: cleanLabel,
            snippet: match.snippet,
            targetPage: match.pageIndex,
            targetPoint: targetPoint,
            targetRect: targetRect,
            sourceRect: targetRect,
            sourcePage: match.pageIndex,
            thumbnailData: nil
        )
    }

    /// Saves a snapshot shortcut from a search result hit directly into the snapshots collection.
    /// Skips duplicate creation if an identical snapshot (same page and snippet/rect) is already present,
    /// without re-selecting any snapshot so the user's active search triage flow is not disrupted.
    public func addSnapshot(from match: SearchResult) {
        let isDuplicate = activeSnapshots.contains { snap in
            guard snap.targetPage == match.pageIndex else { return false }
            if snap.snippet == match.snippet { return true }
            if let snapRect = snap.targetRect, !match.highlightQuads.isEmpty {
                let matchRect = match.highlightQuads.reduce(into: CGRect.null) { $0 = $0.isNull ? $1.boundingRect : $0.union($1.boundingRect) }
                if !matchRect.isNull && snapRect.intersects(matchRect) {
                    return true
                }
            }
            return false
        }

        guard !isDuplicate else { return }

        let target = buildSnapshotTarget(from: match)
        activeSnapshots.append(target)
        saveReadingStateIfNeeded()
    }

    /// Opens the search result in a separate snapshot window centered on the match coordinates.
    public func openSnapshotInNewWindow(from match: SearchResult) {
        let target = buildSnapshotTarget(from: match)
        openSnapshotInNewWindow(target)
    }

    /// Saves a search result as a snapshot and opens it in a new window in one step.
    public func addSnapshotAndOpenInNewWindow(from match: SearchResult) {
        let target = buildSnapshotTarget(from: match)
        addSnapshot(from: match)
        let snapToOpen = activeSnapshots.first(where: { $0.id == target.id || ($0.targetPage == match.pageIndex && $0.snippet == match.snippet) }) ?? target
        openSnapshotInNewWindow(snapToOpen)
    }

    /// Builds a SnapshotTarget from a Table of Contents outline node.
    public func buildSnapshotTarget(from node: PDFOutlineNode) -> SnapshotTarget? {
        guard let page = node.targetPage else { return nil }
        let label = node.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = label.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let cleanLabel = normalized.isEmpty ? "Page \(page + 1)" : normalized
        return SnapshotTarget(
            label: cleanLabel,
            snippet: cleanLabel,
            targetPage: page,
            targetPoint: nil,
            targetRect: nil,
            sourceRect: nil,
            sourcePage: page,
            uri: node.uri,
            thumbnailData: nil
        )
    }

    /// Saves a snapshot shortcut from a Table of Contents outline node into the snapshots collection.
    public func addSnapshot(from node: PDFOutlineNode) {
        guard let target = buildSnapshotTarget(from: node) else { return }
        addSnapshotTarget(target)
    }

    /// Opens the outline node in a separate snapshot window centered on the target page.
    public func openSnapshotInNewWindow(from node: PDFOutlineNode) {
        guard let target = buildSnapshotTarget(from: node) else { return }
        openSnapshotInNewWindow(target)
    }

    /// Saves an outline node as a snapshot and opens it in a new window in one step.
    public func addSnapshotAndOpenInNewWindow(from node: PDFOutlineNode) {
        guard let target = buildSnapshotTarget(from: node) else { return }
        addSnapshot(from: node)
        let snapToOpen = activeSnapshots.first(where: { $0.id == target.id || ($0.targetPage == target.targetPage && $0.snippet == target.snippet) }) ?? target
        openSnapshotInNewWindow(snapToOpen)
    }

    /// Saves a snapshot target and opens it in a new window in one step.
    public func addSnapshotAndOpen(_ target: SnapshotTarget) {
        addSnapshotTarget(target)
        openSnapshotInNewWindow(target)
    }

    /// Saves the current selection as a snapshot and opens it in a new window in one step.
    public func addSnapshotAndOpenFromSelection() {
        guard let target = buildSnapshotTargetFromSelection() else { return }
        addSnapshotTarget(target)
        openSnapshotInNewWindow(target)
    }

    /// Builds a SnapshotTarget at an arbitrary point on a page (e.g. from right-clicking with no active selection),
    /// Builds an Anchor/Snapshot target at an arbitrary point on a page (e.g. from right-clicking with no active selection),
    /// deterministically filtering out margin line-number gutters and matching section/subsection headings directly from the outline.
    public func buildSnapshotTarget(at pagePoint: CGPoint, pageIndex: Int) -> SnapshotTarget {
        guard let stext = pageStructuredData[pageIndex] ?? document?.loadStructuredPage(for: pageIndex) else {
            return SnapshotTarget(
                label: "Page \(pageIndex + 1)",
                snippet: "Page \(pageIndex + 1)",
                targetPage: pageIndex,
                targetPoint: pagePoint,
                targetRect: CGRect(x: max(0, pagePoint.x - 100), y: max(0, pagePoint.y - 20), width: 200, height: 40),
                sourceRect: CGRect(x: max(0, pagePoint.x - 100), y: max(0, pagePoint.y - 20), width: 200, height: 40),
                sourcePage: pageIndex,
                thumbnailData: nil
            )
        }

        // 1. Collect all authoritative outline (TOC) nodes for this page to deterministically identify section/subsection headings
        var outlineNodesOnPage: [PDFOutlineNode] = []
        func collectOutline(nodes: [PDFOutlineNode]) {
            for n in nodes {
                if n.targetPage == pageIndex {
                    outlineNodesOnPage.append(n)
                }
                collectOutline(nodes: n.children)
            }
        }
        if let outline = document?.outline {
            collectOutline(nodes: outline)
        }

        // 2. Separate body content from margin line-number gutters
        let textBlocks = stext.blocks.filter { $0.type == .text && !$0.lines.isEmpty }
        let bodyBlocks = textBlocks.filter { $0.bbox.width >= SpatialTextSelector.minColumnWidth }
        let candidateBlocks = bodyBlocks.isEmpty ? textBlocks : bodyBlocks
        let bodyLeftMargin = candidateBlocks.map { $0.bbox.minX }.min() ?? (stext.bounds.minX + SpatialTextSelector.minColumnWidth)

        var contentLines: [(line: TextLine, block: TextBlock)] = []
        for block in textBlocks {
            for line in block.lines {
                // Strictly exclude margin line numbers: numeric-only with narrow width or in the left margin gutter
                if SpatialTextSelector.isLineNumberGutter(line: line, bodyLeftMargin: bodyLeftMargin) { continue }
                if line.characters.allSatisfy({ $0.char.isNumber || $0.char.isWhitespace }) && line.bbox.width < 45 { continue }
                contentLines.append((line, block))
            }
        }

        // 3. Find the best content line closest to the click point (prioritizing vertical alignment)
        var bestCandidate: (line: TextLine, block: TextBlock)? = nil
        var bestScore: CGFloat = .infinity

        for item in contentLines {
            let line = item.line
            let dy: CGFloat
            if pagePoint.y >= line.bbox.minY - 4 && pagePoint.y <= line.bbox.maxY + 4 {
                dy = 0
            } else if pagePoint.y < line.bbox.minY {
                dy = line.bbox.minY - pagePoint.y
            } else {
                dy = pagePoint.y - line.bbox.maxY
            }

            let dx: CGFloat
            if pagePoint.x >= line.bbox.minX && pagePoint.x <= line.bbox.maxX {
                dx = 0
            } else if pagePoint.x < line.bbox.minX {
                dx = line.bbox.minX - pagePoint.x
            } else {
                dx = pagePoint.x - line.bbox.maxX
            }

            let score = (dy * 3.5) + dx
            if score < bestScore {
                bestScore = score
                bestCandidate = item
            }
        }

        if let (bestLine, bestBlock) = bestCandidate, bestScore < 250 {
            func normalizeHeading(_ str: String) -> String {
                str.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").lowercased()
            }

            let lineNorm = normalizeHeading(bestLine.text)
            let blockNorm = normalizeHeading(bestBlock.text)

            // 4. Deterministic Heading Detection: Check if the clicked line or its block matches a document outline node
            var matchedOutlineNode: PDFOutlineNode? = nil
            for node in outlineNodesOnPage {
                let nodeNorm = normalizeHeading(node.title)
                guard !nodeNorm.isEmpty else { continue }
                if lineNorm == nodeNorm || blockNorm == nodeNorm ||
                   lineNorm.hasPrefix(nodeNorm) || nodeNorm.hasPrefix(lineNorm) ||
                   blockNorm.hasPrefix(nodeNorm) {
                    matchedOutlineNode = node
                    break
                }
            }

            if let node = matchedOutlineNode {
                let cleanHeading = node.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let targetRect = (bestBlock.lines.count <= 3 && bestBlock.bbox.width >= bestLine.bbox.width) ? bestBlock.bbox : bestLine.bbox
                let targetPoint = CGPoint(x: targetRect.minX, y: targetRect.midY)
                return SnapshotTarget(
                    label: cleanHeading,
                    snippet: cleanHeading,
                    targetPage: pageIndex,
                    targetPoint: targetPoint,
                    targetRect: targetRect,
                    sourceRect: targetRect,
                    sourcePage: pageIndex,
                    uri: node.uri,
                    thumbnailData: nil
                )
            }

            // 5. Regular Body Line (not an outline heading): Extract clean words without any line numbers
            let validChars = bestLine.characters.filter { $0.char != "\n" }
            let lineCleanText = bestLine.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")

            var startCharIdx = 0
            if pagePoint.x > bestLine.bbox.minX + 25 {
                var closestCharIdx = 0
                var closestDx: CGFloat = .infinity
                for (cIdx, char) in validChars.enumerated() {
                    let dx = abs(char.boundingRect.midX - pagePoint.x)
                    if dx < closestDx {
                        closestDx = dx
                        closestCharIdx = cIdx
                    }
                }
                while closestCharIdx > 0 && validChars[closestCharIdx - 1].char != " " {
                    closestCharIdx -= 1
                }
                startCharIdx = closestCharIdx
            }

            let remainingText = String(validChars[startCharIdx...].map { $0.char }).trimmingCharacters(in: .whitespacesAndNewlines)
            let words = remainingText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            let candidateLabel = words.prefix(6).joined(separator: " ")
            let truncated = candidateLabel.truncatedAtWordBoundary(maxLength: 45)
            let cleanLabel = truncated.isEmpty ? (lineCleanText.isEmpty ? "Page \(pageIndex + 1)" : lineCleanText) : truncated

            let targetRect = bestLine.bbox
            let targetPoint = CGPoint(x: targetRect.minX, y: targetRect.midY)

            return SnapshotTarget(
                label: cleanLabel,
                snippet: lineCleanText,
                targetPage: pageIndex,
                targetPoint: targetPoint,
                targetRect: targetRect,
                sourceRect: targetRect,
                sourcePage: pageIndex,
                thumbnailData: nil
            )
        }

        return SnapshotTarget(
            label: "Page \(pageIndex + 1)",
            snippet: "Page \(pageIndex + 1)",
            targetPage: pageIndex,
            targetPoint: pagePoint,
            targetRect: CGRect(x: max(0, pagePoint.x - 100), y: max(0, pagePoint.y - 20), width: 200, height: 40),
            sourceRect: CGRect(x: max(0, pagePoint.x - 100), y: max(0, pagePoint.y - 20), width: 200, height: 40),
            sourcePage: pageIndex,
            thumbnailData: nil
        )
    }
    
    private func makeThumbnail(from image: NSImage, pageBounds: CGRect, targetRect: CGRect) -> Data? {
        guard targetRect.width > 5 && targetRect.height > 5 else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        let scaleX = CGFloat(cgImage.width) / pageBounds.width
        let scaleY = CGFloat(cgImage.height) / pageBounds.height
        
        let cropX = max(0, (targetRect.minX - pageBounds.minX) * scaleX)
        let cropY = max(0, (targetRect.minY - pageBounds.minY) * scaleY)
        let cropW = min(CGFloat(cgImage.width) - cropX, max(targetRect.width * scaleX, 20))
        let cropH = min(CGFloat(cgImage.height) - cropY, max(targetRect.height * scaleY, 20))
        
        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        
        let rep = NSBitmapImageRep(cgImage: cropped)
        return rep.representation(using: .png, properties: [:])
    }
    
    /// Opens `target` in a new, separate window (not a tab) positioned at that exact location —
    /// for keeping related sections of the same document visible side by side. Used both by
    /// saved snapshot cards and by Option-click / "Open in New Window" on cross-reference links,
    /// selections, and plain page locations. `currentWindow` (this document's own window) is
    /// passed as the source so the new window cascades near it and closes automatically if this
    /// window closes first.
    public func openSnapshotInNewWindow(_ target: SnapshotTarget) {
        guard let doc = document else { return }
        let source = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
        SnapshotWindowManager.shared.open(url: URL(fileURLWithPath: doc.filePath), target: target, source: source)
    }

    /// Closes the snapshot window for `target`, if one is currently open. Snapshot cards use
    /// this to turn their window button into a Close action once its window is already open.
    public func closeSnapshotWindow(_ target: SnapshotTarget) {
        SnapshotWindowManager.shared.close(target.id)
    }

    /// Resolves the bounding box for a reference or snapshot target in native page coordinates,
    /// unifying spatial text line detection, margin gutter filtering, and fallbacks so that both
    /// the focus ring renderer and viewport scrolling share identical geometry.
    public func resolvedTargetRect(for snap: SnapshotTarget) -> CGRect {
        let pageIdx = snap.targetPage
        let doc = document
        let pageBounds: CGRect
        if let doc, pageIdx >= 0, pageIdx < doc.pageCount {
            pageBounds = doc.pageBounds[pageIdx]
        } else {
            pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        }

        if let rect = snap.targetRect, rect.width > 0, rect.height > 0 {
            if snap.thumbnailFileName != nil {
                // Exact user-drawn marquee area crop
                return rect
            }
            // Text selections, search hits, and point snapshots receive breathable padding matching link targets
            let padded = rect.insetBy(dx: -6, dy: -3)
            let safeLeft = pageBounds.minX + 4
            let safeRight = pageBounds.maxX - 4
            let clampedX = max(safeLeft, min(padded.minX, safeRight - 24))
            let clampedY = max(pageBounds.minY + 4, min(padded.minY, pageBounds.maxY - 20))
            let clampedW = min(padded.width, safeRight - clampedX)
            let clampedH = min(padded.height, pageBounds.maxY - clampedY)
            return CGRect(x: clampedX, y: clampedY, width: max(clampedW, 24), height: max(clampedH, 20))
        }

        guard let doc, pageIdx >= 0, pageIdx < doc.pageCount else {
            return snap.targetRect ?? CGRect(x: 54, y: 36, width: 300, height: 40)
        }

        // Ensure structured data is available for line resolution
        if pageStructuredData[pageIdx] == nil {
            pageStructuredData[pageIdx] = doc.loadStructuredPage(for: pageIdx)
        }
        let stext = pageStructuredData[pageIdx]

        let rawPoint = snap.targetPoint
        let hasValidX = (rawPoint != nil && !rawPoint!.x.isNaN)
        let hasValidY = (rawPoint != nil && !rawPoint!.y.isNaN)

        // If MuPDF returned (0, 0) or near-origin coords (e.g. for /Fit links with unspecified coordinates),
        // anchor into the top body content rather than the top-left margin gutter.
        let isOriginPoint = (hasValidX && hasValidY && rawPoint!.x <= pageBounds.minX + 10 && rawPoint!.y <= pageBounds.minY + 10)
        let bodyLeftMargin = max(pageBounds.minX + 48, stext?.blocks
            .filter { $0.type == .text && $0.bbox.width >= SpatialTextSelector.minColumnWidth }
            .map { $0.bbox.minX }.min() ?? (pageBounds.minX + SpatialTextSelector.minColumnWidth))

        let safeX = (hasValidX && !isOriginPoint) ? rawPoint!.x : bodyLeftMargin
        let safeY = (hasValidY && !isOriginPoint) ? rawPoint!.y : (pageBounds.minY + 40)
        let safePoint = CGPoint(x: safeX, y: safeY)

        var resolvedLineRect: CGRect? = nil
        if let stext,
           let line = textSelector.targetLine(on: stext, at: safePoint, label: snap.label, uri: snap.uri) {
            resolvedLineRect = line.bbox.insetBy(dx: -6, dy: -3)
        }

        if let lineRect = resolvedLineRect {
            return lineRect
        }

        if rawPoint != nil && (hasValidX || hasValidY) && !isOriginPoint {
            // Fallback geometry when structured text is unavailable or non-textual.
            let isLeftAnchored = safePoint.x <= bodyLeftMargin + 10
            let desiredWidth: CGFloat = min(360, pageBounds.width - (bodyLeftMargin - pageBounds.minX) - 36)
            let desiredHeight: CGFloat = 36

            let rx: CGFloat = isLeftAnchored ? bodyLeftMargin : (safePoint.x - desiredWidth / 2)
            let ry: CGFloat = safePoint.y - desiredHeight / 2

            let minX = bodyLeftMargin
            let maxX = pageBounds.maxX - 16
            let minY = pageBounds.minY + 16
            let maxY = pageBounds.maxY - 16

            let clampedX = max(minX, min(rx, maxX - desiredWidth))
            let clampedY = max(minY, min(ry, maxY - desiredHeight))
            let clampedW = min(desiredWidth, maxX - clampedX)
            let clampedH = min(desiredHeight, maxY - clampedY)

            return CGRect(x: clampedX, y: clampedY, width: max(clampedW, 40), height: max(clampedH, 20))
        }

        let minX = max(bodyLeftMargin, pageBounds.minX + 54)
        let width = max(min(pageBounds.width - (minX - pageBounds.minX) - 36, 400), 100)
        let minY = pageBounds.minY + 36
        return CGRect(x: minX, y: minY, width: width, height: 40)
    }

    public func jumpToSnapshot(_ snap: SnapshotTarget) {
        loadPageMetadata(snap.targetPage)
        self.selectedSnapshotId = snap.id
        self.activeSnapshotTarget = snap
        self.snapshotJumpToken &+= 1
        self.currentPageIndex = snap.targetPage
        pruneCaches(around: snap.targetPage)
        
        Task {
            await renderPage(snap.targetPage)
            await MainActor.run {
                self.activeScrollTargetId = "snap_\(snap.id.uuidString)"
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.activeSnapshotTarget?.id == snap.id {
                withAnimation(.easeOut(duration: 0.5)) {
                    self.activeSnapshotTarget = nil
                }
            }
        }
    }
    
    // MARK: - Zoom Controls
    // Zoom bounds come from PDFViewerAppCoordinator.minZoomScale/maxZoomScale, which also drive
    // the View menu's Zoom In/Out enablement.
    public func zoomIn() {
        let step: CGFloat = 0.25
        let epsilon: CGFloat = 0.001
        let nextStep = (floor((zoomScale + epsilon) / step) + 1.0) * step
        setZoom(min(round(nextStep * 100) / 100, PDFViewerAppCoordinator.maxZoomScale))
    }

    public func zoomOut() {
        guard zoomScale > PDFViewerAppCoordinator.minZoomScale else { return }
        let step: CGFloat = 0.25
        let epsilon: CGFloat = 0.001
        let prevStep = (ceil((zoomScale - epsilon) / step) - 1.0) * step
        setZoom(min(zoomScale, max(round(prevStep * 100) / 100, PDFViewerAppCoordinator.minZoomScale)))
    }
    
    public func resetZoom() {
        setZoom(1.0)
    }
    
    public func setZoom(_ newZoom: CGFloat) {
        zoomScale = newZoom
        renderedPages = [:]
        Task { await renderPage(currentPageIndex) }
    }

    public func zoomToFitWidth(viewportWidth: CGFloat? = nil) {
        guard let doc = document, doc.pageBounds.indices.contains(currentPageIndex) else { return }
        let sideways = isRotatedSideways
        let pageW = sideways ? doc.pageBounds[currentPageIndex].height : doc.pageBounds[currentPageIndex].width
        
        let effectiveW: CGFloat
        if isTwoPageMode {
            let pageGap: CGFloat = 16.0
            if currentPageIndex == 0 {
                let leftW = doc.pageCount > 1 ? (sideways ? doc.pageBounds[1].height : doc.pageBounds[1].width) : pageW
                effectiveW = leftW + pageGap + pageW
            } else {
                let isLeft = currentPageIndex % 2 == 1
                let leftIdx = isLeft ? currentPageIndex : currentPageIndex - 1
                let rightIdx = leftIdx + 1
                let leftW = sideways ? doc.pageBounds[leftIdx].height : doc.pageBounds[leftIdx].width
                let rightW = rightIdx < doc.pageCount ? (sideways ? doc.pageBounds[rightIdx].height : doc.pageBounds[rightIdx].width) : leftW
                effectiveW = leftW + pageGap + rightW
            }
        } else {
            effectiveW = pageW
        }
        
        // PDFVirtualizedScrollView applies 32pt padding on both left and right (total 64pt)
        let horizontalPadding: CGFloat = 64.0
        let availW: CGFloat
        if let custom = viewportWidth, custom > 100 {
            availW = max(custom - horizontalPadding, 200)
        } else if let vp = currentViewportSize, vp.width > 100 {
            availW = max(vp.width - horizontalPadding, 200)
        } else if let window = currentWindow ?? NSApplication.shared.keyWindow {
            let sidebarOffset: CGFloat = (isTwoPageMode || !isSidebarVisible) ? 0 : 260
            availW = max(window.contentLayoutRect.width - sidebarOffset - horizontalPadding, 200)
        } else {
            availW = 700
        }
        let targetEffectiveZoom = availW / effectiveW
        let baseScale = (PDFViewerAppCoordinator.shared.scaleMode == .physical ? displayScale : 1.0)
        let targetZoom = targetEffectiveZoom / max(baseScale, 0.1)
        let clamped = min(max(targetZoom, PDFViewerAppCoordinator.minZoomScale), PDFViewerAppCoordinator.maxZoomScale)
        setZoom(round(clamped * 100) / 100)
    }

    public func zoomToFitPage(viewportSize: CGSize? = nil) {
        guard let doc = document, doc.pageBounds.indices.contains(currentPageIndex) else { return }
        let sideways = isRotatedSideways
        let pageW = sideways ? doc.pageBounds[currentPageIndex].height : doc.pageBounds[currentPageIndex].width
        let pageH = sideways ? doc.pageBounds[currentPageIndex].width : doc.pageBounds[currentPageIndex].height
        
        let effectiveW: CGFloat
        if isTwoPageMode {
            let pageGap: CGFloat = 16.0
            if currentPageIndex == 0 {
                let leftW = doc.pageCount > 1 ? (sideways ? doc.pageBounds[1].height : doc.pageBounds[1].width) : pageW
                effectiveW = leftW + pageGap + pageW
            } else {
                let isLeft = currentPageIndex % 2 == 1
                let leftIdx = isLeft ? currentPageIndex : currentPageIndex - 1
                let rightIdx = leftIdx + 1
                let leftW = sideways ? doc.pageBounds[leftIdx].height : doc.pageBounds[leftIdx].width
                let rightW = rightIdx < doc.pageCount ? (sideways ? doc.pageBounds[rightIdx].height : doc.pageBounds[rightIdx].width) : leftW
                effectiveW = leftW + pageGap + rightW
            }
        } else {
            effectiveW = pageW
        }
        
        let horizontalPadding: CGFloat = 64.0
        let verticalPadding: CGFloat = 48.0
        let availW: CGFloat
        let availH: CGFloat
        if let size = viewportSize, size.width > 100, size.height > 100 {
            availW = max(size.width - horizontalPadding, 200)
            availH = max(size.height - verticalPadding, 200)
        } else if let vp = currentViewportSize, vp.width > 100, vp.height > 100 {
            availW = max(vp.width - horizontalPadding, 200)
            availH = max(vp.height - verticalPadding, 200)
        } else if let window = currentWindow ?? NSApplication.shared.keyWindow {
            let sidebarOffset: CGFloat = (isTwoPageMode || !isSidebarVisible) ? 0 : 260
            availW = max(window.contentLayoutRect.width - sidebarOffset - horizontalPadding, 200)
            availH = max(window.contentLayoutRect.height - verticalPadding, 200)
        } else {
            availW = 700
            availH = 900
        }
        let scaleX = availW / effectiveW
        let scaleY = availH / pageH
        let targetEffectiveZoom = min(scaleX, scaleY)
        let baseScale = (PDFViewerAppCoordinator.shared.scaleMode == .physical ? displayScale : 1.0)
        let targetZoom = targetEffectiveZoom / max(baseScale, 0.1)
        let clamped = min(max(targetZoom, PDFViewerAppCoordinator.minZoomScale), PDFViewerAppCoordinator.maxZoomScale)
        setZoom(round(clamped * 100) / 100)
    }

    public func toggleMarkupToolbar() {
        isMarkupBarVisible.toggle()
        if !isMarkupBarVisible {
            canvasMode = .select
        }
    }

    // MARK: - Annotations

    @discardableResult
    public func addTextMarkupSelection(type: PDFAnnotationType, color: AnnotationColor = .yellow) -> [PDFAnnotation] {
        guard let sel = activeSelection, !sel.result.highlightQuads.isEmpty, let doc = document else { return [] }
        var created: [PDFAnnotation] = []

        let pIdx = sel.pageIndex
        let quads = sel.result.highlightQuads
        let text = sel.result.text
        let annot = PDFAnnotation(pageIndex: pIdx, type: type, quads: quads, color: color, text: text)
        do {
            try doc.addTextMarkup(pageIndex: pIdx, type: type, quads: quads, red: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue)
            created.append(recordAddedAnnotation(annot))
        } catch {
            print("Failed to add \(type) on page \(pIdx): \(error)")
        }

        for extra in additionalSelectionPages {
            let epIdx = extra.pageIndex
            let eQuads = extra.result.highlightQuads
            guard !eQuads.isEmpty else { continue }
            let eText = extra.result.text
            let eAnnot = PDFAnnotation(pageIndex: epIdx, type: type, quads: eQuads, color: color, text: eText)
            do {
                try doc.addTextMarkup(pageIndex: epIdx, type: type, quads: eQuads, red: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue)
                created.append(recordAddedAnnotation(eAnnot))
            } catch {
                print("Failed to add \(type) on page \(epIdx): \(error)")
            }
        }

        if !created.isEmpty {
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            clearSelection()
        }
        return created
    }

    @discardableResult
    public func highlightSelection(color: AnnotationColor = .yellow) -> [PDFAnnotation] {
        return addTextMarkupSelection(type: .highlight, color: color)
    }

    @discardableResult
    public func underlineSelection(color: AnnotationColor = .yellow) -> [PDFAnnotation] {
        return addTextMarkupSelection(type: .underline, color: color)
    }

    @discardableResult
    public func strikethroughSelection(color: AnnotationColor = .yellow) -> [PDFAnnotation] {
        return addTextMarkupSelection(type: .strikeout, color: color)
    }

    @discardableResult
    public func addInkAnnotation(pageIndex: Int, points: [CGPoint], strokeWidth: CGFloat = 2.5, color: AnnotationColor = .yellow) -> PDFAnnotation? {
        guard !points.isEmpty, let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return nil }
        let annot = PDFAnnotation(pageIndex: pageIndex, type: .ink, inkPoints: points, strokeWidth: strokeWidth, color: color)
        do {
            try doc.addInkStroke(pageIndex: pageIndex, points: points, strokeWidth: strokeWidth, red: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue)
            let stored = recordAddedAnnotation(annot)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            return stored
        } catch {
            print("Failed to add ink annotation on page \(pageIndex): \(error)")
            return nil
        }
    }

    @discardableResult
    public func addFreeTextAnnotation(pageIndex: Int, rect: CGRect, text: String, fontSize: CGFloat = 13.0, color: AnnotationColor = .black) -> PDFAnnotation? {
        guard !text.isEmpty, let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return nil }
        let annot = PDFAnnotation(pageIndex: pageIndex, type: .freeText, rect: rect, fontSize: fontSize, color: color, text: text)
        do {
            try doc.addFreeText(pageIndex: pageIndex, rect: rect, text: text, fontSize: fontSize, red: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue)
            let stored = recordAddedAnnotation(annot)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            return stored
        } catch {
            print("Failed to add free text annotation on page \(pageIndex): \(error)")
            return nil
        }
    }

    @discardableResult
    public func addStampAnnotation(pageIndex: Int, rect: CGRect, imageData: Data, color: AnnotationColor = .black) -> PDFAnnotation? {
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return nil }
        let pageTopY = doc.pageBounds[pageIndex].maxY
        let nativeRect = CGRect(x: rect.minX, y: pageTopY - rect.maxY, width: rect.width, height: rect.height)
        let annot = PDFAnnotation(pageIndex: pageIndex, type: .stamp, rect: rect, color: color, stampImageData: imageData)
        do {
            try doc.stampImage(pageIndex: pageIndex, rect: nativeRect, imageData: imageData)
            let stored = recordAddedAnnotation(annot)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            return stored
        } catch {
            print("Failed to add stamp annotation on page \(pageIndex): \(error)")
            return nil
        }
    }

    /// Adds an annotation that was just written to the document to the on-screen overlay, tagged
    /// with the PDF object it became so later edits and deletes touch only that annotation.
    private func recordAddedAnnotation(_ annot: PDFAnnotation) -> PDFAnnotation {
        var stored = annot
        stored.documentObjectNumber = document?.lastAnnotationObjectNumber(pageIndex: annot.pageIndex)
        pageAnnotations[annot.pageIndex, default: []].append(stored)
        return stored
    }

    public func removeAnnotation(_ annotation: PDFAnnotation) {
        let pIdx = annotation.pageIndex
        if let idx = pageAnnotations[pIdx]?.firstIndex(where: { $0.id == annotation.id }) {
            pageAnnotations[pIdx]?.remove(at: idx)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
        }
        guard let doc = document else { return }
        // Delete exactly the PDF object this annotation was written as. Finding it by position
        // instead deletes whichever annotation happens to come first near that point — often one
        // that was already in the file underneath it.
        if let objectNumber = annotation.documentObjectNumber {
            _ = try? doc.deleteAnnotation(pageIndex: pIdx, objectNumber: objectNumber)
            return
        }
        let testPoint: CGPoint
        if annotation.type == .ink, let firstPt = annotation.inkPoints.first {
            testPoint = firstPt
        } else if annotation.type == .freeText, let r = annotation.rect {
            testPoint = CGPoint(x: r.midX, y: r.midY)
        } else if annotation.type == .callout, let tp = annotation.targetPoint {
            testPoint = tp
        } else if annotation.type == .stamp, let r = annotation.rect {
            let pageTopY = (pIdx >= 0 && pIdx < doc.pageBounds.count) ? doc.pageBounds[pIdx].maxY : 0
            testPoint = CGPoint(x: r.midX, y: pageTopY - r.midY)
        } else {
            testPoint = CGPoint(x: annotation.boundingRect.midX, y: annotation.boundingRect.midY)
        }
        _ = try? doc.deleteAnnotation(pageIndex: pIdx, at: testPoint)
        if annotation.type == .stamp, let r = annotation.rect {
            // Also try top-down center in case annot rect was recorded top-down
            _ = try? doc.deleteAnnotation(pageIndex: pIdx, at: CGPoint(x: r.midX, y: r.midY))
        }
        if annotation.type == .callout, let r = annotation.rect {
            _ = try? doc.deleteAnnotation(pageIndex: pIdx, at: CGPoint(x: r.midX, y: r.midY))
        }
    }

    public func removeAnnotation(at pagePoint: CGPoint, pageIndex: Int) {
        if let list = pageAnnotations[pageIndex], let annot = list.first(where: { $0.contains(pagePoint: pagePoint) }) {
            removeAnnotation(annot)
        } else if let doc = document {
            // An annotation that came with the file isn't in `pageAnnotations`. Deleting it from the
            // document alone changes nothing on screen (rendering reads the file through its own
            // actor) and nothing flags the document as edited — so push the change through the
            // same working-copy refresh the other edits use.
            if (try? doc.deleteAnnotation(pageIndex: pageIndex, at: pagePoint)) == true {
                finalizeRedactionChanges(affectedPages: [pageIndex])
            }
        }
    }

    // MARK: - Redaction & Security Scrubbing

    /// Directly and immediately applies a redaction box over a user-drawn region.
    public func applyRedactionRegion(pageIndex: Int, rect: CGRect) {
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return }
        let mode: Int32 = (redactionColor == .black) ? 1 : 2
        do {
            try doc.applyRedactions(pageIndex: pageIndex, rects: [rect], mode: mode)
            finalizeRedactionChanges(affectedPages: [pageIndex])
        } catch {
            print("Failed to apply redaction region on page \(pageIndex): \(error)")
        }
    }

    /// Directly and immediately applies the chosen RedactAction (.redact, .delete) to all selected search matches.
    public func applySelectedMatches() {
        let selected = redactionMatches.filter { $0.isSelected }
        guard !selected.isEmpty, let doc = document else { return }

        var affectedPages = Set<Int>()
        let isBlack = (redactionColor == .black)
        let byPage = Dictionary(grouping: selected, by: { $0.result.pageIndex })

        for (pIdx, items) in byPage {
            let rects = items.flatMap { item in
                item.result.highlightQuads.isEmpty
                    ? [item.result.rect.insetBy(dx: -1.0, dy: -1.0)]
                    : item.result.highlightQuads.map { $0.boundingRect.insetBy(dx: -1.0, dy: -1.0) }
            }

            switch replaceAction {
            case .redact:
                let mode: Int32 = isBlack ? 1 : 2
                do {
                    try doc.applyRedactions(pageIndex: pIdx, rects: rects, mode: mode)
                    affectedPages.insert(pIdx)
                } catch {
                    print("Failed to apply redactions on page \(pIdx): \(error)")
                }

            case .remove:
                do {
                    try doc.applyRedactions(pageIndex: pIdx, rects: rects, mode: 0)
                    affectedPages.insert(pIdx)
                } catch {
                    print("Failed to remove text on page \(pIdx): \(error)")
                }
            }
        }

        let appliedIDs = Set(selected.map { $0.id })
        redactionMatches.removeAll(where: { appliedIDs.contains($0.id) })

        finalizeRedactionChanges(affectedPages: affectedPages)
    }

    /// Saves document modifications to the working copy, updates background actors, and re-renders affected pages.
    public func finalizeRedactionChanges(affectedPages: Set<Int>) {
        guard !affectedPages.isEmpty, let doc = document else { return }

        if workingCopyPath == nil {
            workingCopyPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("working_\(UUID().uuidString).pdf").path
        }
        guard let workingPath = workingCopyPath else { return }

        do {
            try doc.save(to: workingPath)
        } catch {
            print("Failed to save modified working copy: \(error)")
        }

        self.isDocumentEdited = true
        self.currentWindow?.isDocumentEdited = true
        // Redacted text must not survive in the Agent's index — in memory or in its disk cache.
        invalidateAgentIndex(deleteCache: true)

        Task { @MainActor in
            await self.reopenActors(at: workingPath)
            self.thumbnailVersion = UUID()
            for pIdx in affectedPages {
                self.renderedPages.removeValue(forKey: pIdx)
                self.thumbnailImages.removeValue(forKey: pIdx)
                self.pageStructuredData.removeValue(forKey: pIdx)
                self.requestThumbnail(for: pIdx)
                await self.renderPage(pIdx)
            }
            self.objectWillChange.send()
        }
    }

    public func toggleRedactionBar() {
        isRedactionBarVisible.toggle()
        if isRedactionBarVisible {
            if editRedactTab == .redactRegion {
                canvasMode = .redact
            }
        } else {
            if canvasMode == .redact {
                canvasMode = .select
            }
        }
    }

    public func performRedactionSearch() {
        redactionSearchTask?.cancel()
        
        let query: String
        let isRegex: Bool
        if let presetRegex = redactionPreset.regexPattern {
            query = presetRegex
            isRegex = true
        } else if redactionPreset == .customRegex {
            query = redactionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            isRegex = true
        } else {
            query = redactionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            isRegex = false
        }

        guard !query.isEmpty else {
            redactionMatches = []
            isRedactionSearching = false
            return
        }

        // Match Case / Whole Word are only offered for custom searches (Whole Word only for
        // plain text); a value left over from one must not silently narrow a preset's search.
        let options = SearchOptions(
            matchCase: (redactionPreset == .customText || redactionPreset == .customRegex) && redactionMatchCase,
            wholeWord: redactionPreset == .customText && redactionWholeWord,
            smartSearch: !isRegex,
            isRegex: isRegex
        )

        isRedactionSearching = true
        redactionMatches = []

        let nearPage = currentPageIndex
        let ocr = self.ocrResults

        redactionSearchTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let stream = await self.searchActor.searchStream(
                query: query,
                nearPage: nearPage,
                options: options,
                ocrPages: ocr
            )

            var items: [RedactionMatchItem] = []
            var lastUpdate = Date()

            for await result in stream {
                guard !Task.isCancelled else { break }
                items.append(RedactionMatchItem(result: result, isSelected: true))
                if items.count < 5 || Date().timeIntervalSince(lastUpdate) > 0.08 {
                    self.redactionMatches = items
                    lastUpdate = Date()
                }
            }

            if !Task.isCancelled {
                self.redactionMatches = items
                self.isRedactionSearching = false
            }
        }
    }

    public func cancelRedactionSearch() {
        redactionSearchTask?.cancel()
        isRedactionSearching = false
    }

    public func selectAllRedactionMatches(_ selected: Bool) {
        for idx in redactionMatches.indices {
            redactionMatches[idx].isSelected = selected
        }
    }

    public func toggleRedactionMatchSelection(id: UUID) {
        if let idx = redactionMatches.firstIndex(where: { $0.id == id }) {
            redactionMatches[idx].isSelected.toggle()
        }
    }

    public func selectRedactionMatch(_ item: RedactionMatchItem) {
        activeRedactionMatchId = item.id
        let match = item.result
        let pageIdx = match.pageIndex
        activeScrollTargetId = item.id.uuidString
        searchJumpToken &+= 1
        currentPageIndex = pageIdx
        pruneCaches(around: pageIdx)
        Task {
            await renderPage(pageIdx)
        }
        objectWillChange.send()
    }

    // MARK: - Technical Callout Annotations

    @discardableResult
    public func addCalloutAnnotation(
        pageIndex: Int,
        targetPoint: CGPoint,
        kneePoint: CGPoint,
        textBoxRect: CGRect,
        text: String,
        fontSize: CGFloat = 11.0,
        color: AnnotationColor = .red
    ) -> PDFAnnotation? {
        guard !text.isEmpty, let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return nil }
        let annot = PDFAnnotation(
            pageIndex: pageIndex,
            type: .callout,
            rect: textBoxRect,
            targetPoint: targetPoint,
            kneePoint: kneePoint,
            fontSize: fontSize,
            color: color,
            text: text
        )
        do {
            try doc.addCallout(
                pageIndex: pageIndex,
                targetPoint: targetPoint,
                kneePoint: kneePoint,
                textBoxRect: textBoxRect,
                text: text,
                fontSize: fontSize,
                red: color.rgb.red,
                green: color.rgb.green,
                blue: color.rgb.blue
            )
            let stored = recordAddedAnnotation(annot)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            return stored
        } catch {
            print("Failed to add callout annotation on page \(pageIndex): \(error)")
            return nil
        }
    }

    // MARK: - Engineering Measurement & Takeoff Annotations

    public func toggleMeasurementBar() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isMeasurementBarVisible.toggle()
        }
    }

    public func scaleConfig(for pageIndex: Int) -> PDFScaleConfiguration {
        pageScaleConfigs[pageIndex] ?? currentScaleConfig
    }

    public func setScaleConfig(_ config: PDFScaleConfiguration, for pageIndex: Int? = nil, applyToAll: Bool = false) {
        if applyToAll || pageIndex == nil {
            currentScaleConfig = config
            if let count = document?.pageCount {
                for i in 0..<count {
                    pageScaleConfigs[i] = config
                }
            }
        } else if let pIdx = pageIndex {
            pageScaleConfigs[pIdx] = config
        }

        // Persist scale via ISO 32000 Viewport (/VP) on target pages
        if let doc = document {
            let targetPages = applyToAll ? Array(0..<doc.pageCount) : (pageIndex != nil ? [pageIndex!] : [currentPageIndex])
            for p in targetPages {
                try? doc.setPageScale(
                    pageIndex: p,
                    ratioString: config.ratioString,
                    unitString: config.linearUnit.shortSymbol,
                    pointsPerUnit: config.pointsPerUnit
                )
            }
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
        }
        objectWillChange.send()
    }

    @discardableResult
    public func addMeasurementAnnotation(
        pageIndex: Int,
        type: PDFAnnotationType,
        points: [CGPoint],
        value: Double,
        formattedText: String,
        leaderOffset: CGFloat = 0.0,
        color: AnnotationColor? = nil,
        strokeWidth: CGFloat = 2.0,
        label: String? = nil
    ) -> PDFAnnotation? {
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount, !points.isEmpty else { return nil }
        let annotColor = color ?? selectedAnnotationColor
        let annot = PDFAnnotation(
            pageIndex: pageIndex,
            type: type,
            strokeWidth: strokeWidth,
            color: annotColor,
            text: label ?? formattedText,
            measurementPoints: points,
            measurementValue: value,
            measurementText: formattedText,
            leaderOffset: leaderOffset
        )

        // Write directly to PDF backend
        do {
            switch type {
            case .measureLength:
                if points.count >= 2 {
                    try doc.addLineDimension(
                        pageIndex: pageIndex,
                        startPoint: points[0],
                        endPoint: points[1],
                        leaderOffset: leaderOffset,
                        text: formattedText,
                        red: annotColor.rgb.red,
                        green: annotColor.rgb.green,
                        blue: annotColor.rgb.blue
                    )
                }
            case .measurePerimeter:
                if points.count >= 2 {
                    try doc.addPolylineDimension(
                        pageIndex: pageIndex,
                        vertices: points,
                        text: formattedText,
                        red: annotColor.rgb.red,
                        green: annotColor.rgb.green,
                        blue: annotColor.rgb.blue
                    )
                }
            case .measureArea:
                if points.count >= 3 {
                    try doc.addPolygonDimension(
                        pageIndex: pageIndex,
                        vertices: points,
                        text: formattedText,
                        red: annotColor.rgb.red,
                        green: annotColor.rgb.green,
                        blue: annotColor.rgb.blue
                    )
                }
            case .measureAngle:
                if points.count >= 3 {
                    try doc.addAngleMeasurement(
                        pageIndex: pageIndex,
                        points: Array(points.prefix(3)),
                        text: formattedText,
                        red: annotColor.rgb.red,
                        green: annotColor.rgb.green,
                        blue: annotColor.rgb.blue
                    )
                }
            default:
                break
            }
        } catch {
            print("Failed to save measurement annotation to PDF core: \(error)")
            return nil
        }

        let stored = recordAddedAnnotation(annot)
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
        objectWillChange.send()
        return stored
    }

    // MARK: - Review Summary Export

    public func generateReviewSummaryMarkdown() -> String {
        let title = documentInspectionReport?.metadata.title.isEmpty == false ? documentInspectionReport!.metadata.title : (document?.filePath != nil ? URL(fileURLWithPath: document!.filePath).lastPathComponent : "Document")
        
        var md = "# Review Summary: \(title)\n\n"
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        md += "**Generated:** \(df.string(from: Date()))  \n"
        let totalCount = pageAnnotations.values.reduce(0) { $0 + $1.count }
        md += "**Total Annotations:** \(totalCount)  \n\n"
        md += "---\n\n"

        let sortedPages = pageAnnotations.keys.sorted()
        if sortedPages.isEmpty {
            md += "*No annotations found in this document.*\n"
            return md
        }

        for pIdx in sortedPages {
            guard let annots = pageAnnotations[pIdx], !annots.isEmpty else { continue }
            md += "## Page \(pIdx + 1)\n\n"
            for annot in annots {
                let colorName = annot.color.displayName
                switch annot.type {
                case .highlight:
                    let quoted = annot.text.isEmpty ? "*(Highlighted area)*" : "\"\(annot.text)\""
                    md += "- **[Highlight]** *(\(colorName))*: \(quoted)\n"
                case .underline:
                    let quoted = annot.text.isEmpty ? "*(Underlined area)*" : "\"\(annot.text)\""
                    md += "- **[Underline]** *(\(colorName))*: \(quoted)\n"
                case .strikeout:
                    let quoted = annot.text.isEmpty ? "*(Strikethrough area)*" : "\"\(annot.text)\""
                    md += "- **[Strikethrough]** *(\(colorName))*: \(quoted)\n"
                case .freeText:
                    md += "- **[Note / Free Text]** *(\(colorName))*: \(annot.text)\n"
                case .callout:
                    var loc = ""
                    if let tp = annot.targetPoint {
                        loc = " pointing at (\(Int(tp.x)), \(Int(tp.y)))"
                    }
                    md += "- **[Callout]** *(\(colorName)\(loc))*: \(annot.text)\n"
                case .ink:
                    md += "- **[Ink Drawing]** *(\(colorName))*: \(annot.inkPoints.count) points\n"
                case .stamp:
                    md += "- **[Signature / Stamp]**: Area \(annot.rect.map { "(\(Int($0.minX)), \(Int($0.minY)), \(Int($0.width))x\(Int($0.height)))" } ?? "")\n"
                case .measureLength:
                    md += "- **[Dimension]** *(\(colorName))*: \(annot.measurementText.isEmpty ? annot.text : annot.measurementText)\n"
                case .measurePerimeter:
                    md += "- **[Perimeter]** *(\(colorName))*: \(annot.measurementText.isEmpty ? annot.text : annot.measurementText)\n"
                case .measureArea:
                    md += "- **[Area Takeoff]** *(\(colorName))*: \(annot.measurementText.isEmpty ? annot.text : annot.measurementText)\n"
                case .measureAngle:
                    md += "- **[Angle]** *(\(colorName))*: \(annot.measurementText.isEmpty ? annot.text : annot.measurementText)\n"
                }
            }
            md += "\n"
        }
        return md
    }

    public func generateReviewSummaryCSV() -> String {
        var csv = "Page,Type,Color,Content,Coordinates,Date\n"
        let df = ISO8601DateFormatter()
        let sortedPages = pageAnnotations.keys.sorted()
        for pIdx in sortedPages {
            guard let annots = pageAnnotations[pIdx] else { continue }
            for annot in annots {
                let pageStr = "\(pIdx + 1)"
                let typeStr = annot.type.rawValue.capitalized
                let colorStr = annot.color.displayName
                let contentRaw = annot.measurementText.isEmpty ? annot.text : annot.measurementText
                let contentEscaped = contentRaw.replacingOccurrences(of: "\"", with: "\"\"")
                var coordStr = ""
                if let r = annot.rect {
                    coordStr = "(\(Int(r.minX)) \(Int(r.minY)) \(Int(r.width))x\(Int(r.height)))"
                } else if let tp = annot.targetPoint {
                    coordStr = "(\(Int(tp.x)) \(Int(tp.y)))"
                } else if !annot.measurementPoints.isEmpty {
                    coordStr = annot.measurementPoints.map { "(\(Int($0.x)),\(Int($0.y)))" }.joined(separator: "-")
                }
                let dateStr = df.string(from: annot.dateCreated)
                csv += "\(pageStr),\(typeStr),\(colorStr),\"\(contentEscaped)\",\"\(coordStr)\",\(dateStr)\n"
            }
        }
        return csv
    }

    public func exportAnnotationsSummary() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Annotations Summary"
        savePanel.prompt = "Export"
        let baseName = (document?.filePath != nil ? URL(fileURLWithPath: document!.filePath).deletingPathExtension().lastPathComponent : "Document")
        savePanel.nameFieldStringValue = "\(baseName)_Annotations_Summary.md"
        savePanel.allowedContentTypes = [.plainText, .commaSeparatedText]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            let isCSV = url.pathExtension.lowercased() == "csv"
            let content = isCSV ? generateReviewSummaryCSV() : generateReviewSummaryMarkdown()
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public func exportReviewSummary() {
        exportAnnotationsSummary()
    }

    // MARK: - Takeoff Summary Generation & Export

    /// One measurement in the takeoff, valued with the scale of the page it's on.
    public struct TakeoffEntry: Identifiable, Sendable {
        public let id = UUID()
        public let pageIndex: Int
        public let annotation: PDFAnnotation
        public let scale: PDFScaleConfiguration
        /// Length in `scale.linearUnit`, area in `scale.areaUnit`, or angle in degrees.
        public let realValue: Double
        public let unitSymbol: String
        public let formattedValue: String
    }

    /// The scale for a page, reading one stored in the document if this page hasn't been shown
    /// yet (scaleConfig(for:) only knows pages whose metadata has been loaded).
    private func resolvedScaleConfig(for pageIndex: Int) -> PDFScaleConfiguration {
        pageScaleConfigs[pageIndex] ?? document?.loadPageScale(pageIndex: pageIndex) ?? currentScaleConfig
    }

    /// Returns every measurement in the document.
    public func takeoffEntries() -> [TakeoffEntry] {
        guard let doc = document else { return [] }
        var entries: [TakeoffEntry] = []
        for pageIndex in 0..<doc.pageCount {
            let annots = doc.measurementAnnotations(pageIndex: pageIndex)
            guard !annots.isEmpty else { continue }
            let scale = resolvedScaleConfig(for: pageIndex)
            for annot in annots {
                let realValue: Double
                let unit: String
                let formatted: String
                switch annot.type {
                case .measureArea:
                    realValue = scale.convertAreaPointsToReal(pointsArea: annot.measurementValue)
                    unit = scale.areaUnit.shortSymbol
                    formatted = scale.formatArea(pointsSquared: annot.measurementValue)
                case .measureAngle:
                    realValue = annot.measurementValue
                    unit = "°"
                    formatted = scale.formatAngle(degrees: annot.measurementValue)
                default:
                    realValue = scale.convertPointsToReal(pointsDistance: annot.measurementValue)
                    // A feet-and-inches scale still yields a plain number of feet.
                    unit = scale.linearUnit == .footInch ? "ft" : scale.linearUnit.shortSymbol
                    formatted = scale.formatLength(points: annot.measurementValue)
                }
                entries.append(TakeoffEntry(pageIndex: pageIndex, annotation: annot, scale: scale, realValue: realValue, unitSymbol: unit, formattedValue: formatted))
            }
        }
        return entries
    }

    /// Total length (dimensions + perimeters) and area across `entries`, each converted with its
    /// own page's scale and expressed in the units of the first entry's scale.
    public func takeoffTotals(_ entries: [TakeoffEntry]) -> (linear: String?, area: String?) {
        guard let reference = entries.first?.scale else { return (nil, nil) }
        var meters = 0.0
        var squareMeters = 0.0
        for entry in entries {
            switch entry.annotation.type {
            case .measureLength, .measurePerimeter:
                meters += entry.scale.convertPointsToReal(pointsDistance: entry.annotation.measurementValue) * entry.scale.metersPerLinearUnit
            case .measureArea:
                squareMeters += entry.scale.squareMeters(pointsSquared: entry.annotation.measurementValue)
            default:
                break
            }
        }
        let ppu = reference.pointsPerUnit
        let mpu = reference.metersPerLinearUnit
        let linear = meters > 0 ? reference.formatLength(points: meters / mpu * ppu) : nil
        let area = squareMeters > 0 ? reference.formatArea(pointsSquared: squareMeters / (mpu * mpu) * ppu * ppu) : nil
        return (linear, area)
    }

    private static func takeoffTypeName(_ type: PDFAnnotationType) -> String {
        switch type {
        case .measureLength: return "Linear Dimension"
        case .measurePerimeter: return "Perimeter"
        case .measureArea: return "Area Takeoff"
        case .measureAngle: return "Angle"
        default: return "Measurement"
        }
    }

    public func generateTakeoffSummaryMarkdown() -> String {
        let title = documentInspectionReport?.metadata.title.isEmpty == false ? documentInspectionReport!.metadata.title : (document?.filePath != nil ? URL(fileURLWithPath: document!.filePath).lastPathComponent : "Document")
        var md = "# Measurement Takeoff Summary: \(title)\n\n"
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        md += "**Generated:** \(df.string(from: Date()))  \n\n"
        md += "---\n\n"

        let entries = takeoffEntries()
        guard !entries.isEmpty else {
            md += "*No calibrated measurements or takeoffs found in this document.*\n"
            return md
        }

        for (pageIndex, pageEntries) in Dictionary(grouping: entries, by: \.pageIndex).sorted(by: { $0.key < $1.key }) {
            md += "## Page \(pageIndex + 1) (Scale: \(pageEntries[0].scale.ratioString))\n\n"
            md += "| Item | Type | Color | Measurement |\n"
            md += "| :--- | :--- | :--- | :--- |\n"
            for (idx, entry) in pageEntries.enumerated() {
                md += "| #\(idx + 1) | \(Self.takeoffTypeName(entry.annotation.type)) | \(entry.annotation.color.displayName) | **\(entry.formattedValue)** |\n"
            }
            md += "\n"
        }

        let totals = takeoffTotals(entries)
        md += "---\n\n"
        md += "### Cumulative Totals\n\n"
        md += "- **Total Measurements:** \(entries.count)\n"
        if let linear = totals.linear {
            md += "- **Total Linear Footage / Perimeter:** \(linear)\n"
        }
        if let area = totals.area {
            md += "- **Total Calculated Surface Area:** \(area)\n"
        }
        return md
    }

    public func generateTakeoffSummaryCSV() -> String {
        func quoted(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var csv = "Page,Index,Type,Color,Measurement,Value,Unit,Scale\n"
        for (pageIndex, pageEntries) in Dictionary(grouping: takeoffEntries(), by: \.pageIndex).sorted(by: { $0.key < $1.key }) {
            for (idx, entry) in pageEntries.enumerated() {
                csv += "\(pageIndex + 1),\(idx + 1),\(Self.takeoffTypeName(entry.annotation.type)),\(entry.annotation.color.displayName),\(quoted(entry.formattedValue)),\(String(format: "%.3f", entry.realValue)),\(quoted(entry.unitSymbol)),\(quoted(entry.scale.ratioString))\n"
            }
        }
        return csv
    }

    public func exportTakeoffSummary() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Measurement Takeoff Summary"
        savePanel.prompt = "Export"
        let baseName = (document?.filePath != nil ? URL(fileURLWithPath: document!.filePath).deletingPathExtension().lastPathComponent : "Document")
        savePanel.nameFieldStringValue = "\(baseName)_Takeoff_Summary.csv"
        savePanel.allowedContentTypes = [.commaSeparatedText, .plainText]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            let isMD = url.pathExtension.lowercased() == "md"
            let content = isMD ? generateTakeoffSummaryMarkdown() : generateTakeoffSummaryCSV()
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                showErrorAlert(title: "Couldn't Export Takeoff Summary", message: error.localizedDescription)
            }
        }
    }

    /// Prompts the user with a save panel and exports the open document in the specified format (.txt, .docx, or flattened .pdf).
    public func exportDocument(as format: ExportDocumentFormat) {
        guard let doc = document else { return }

        if format == .flattenedPDF {
            saveDocumentFlattenedAs()
            return
        }

        let isMultiPageSVG = (format == .svgDocument && doc.pageCount > 1)
        let baseName = URL(fileURLWithPath: doc.filePath).deletingPathExtension().lastPathComponent

        let savePanel = NSSavePanel()
        if isMultiPageSVG {
            savePanel.title = "Export SVG Pages to Folder"
            savePanel.prompt = "Export"
            savePanel.nameFieldStringValue = "\(baseName)"
            savePanel.canCreateDirectories = true
        } else {
            let formatTitle: String
            switch format {
            case .plainText: formatTitle = "Plain Text"
            case .wordDocument: formatTitle = "Word Document"
            case .svgDocument: formatTitle = "Scalable Vector Graphics"
            case .flattenedPDF: formatTitle = "Flattened PDF"
            }
            savePanel.title = "Export Document As \(formatTitle)"
            savePanel.prompt = "Export"
            savePanel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
            if let utType = UTType(filenameExtension: format.fileExtension) {
                savePanel.allowedContentTypes = [utType]
            }
        }

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        // Reconstructing every page's layout takes a while on a long document — off the main thread.
        Task { [weak self] in
            let failure: String? = await Task.detached(priority: .userInitiated) {
                let exporter = PDFDocumentExporter()
                do {
                    switch format {
                    case .plainText:
                        try exporter.exportPlainText(from: doc).write(to: url, atomically: true, encoding: .utf8)
                    case .wordDocument:
                        try exporter.exportWordDocument(from: doc, to: url)
                    case .svgDocument:
                        try exporter.exportSVG(from: doc, to: url)
                    case .flattenedPDF:
                        break // Handled above via saveDocumentFlattenedAs()
                    }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let failure {
                self?.showErrorAlert(title: "Couldn't Export Document", message: failure)
            }
        }
    }

    // MARK: - On-Device Apple Vision OCR

    public func isScannedPage(_ pageIndex: Int) -> Bool {
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return false }
        if ocrResults[pageIndex] != nil { return false }
        return doc.isScannedPage(pageIndex: pageIndex)
    }

    public func runOCR(onPageIndex pageIndex: Int) async {
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return }
        guard ocrResults[pageIndex] == nil else { return }
        let generation = ocrGeneration

        await MainActor.run { self.activeOCRCount += 1 }
        defer {
            Task { @MainActor in
                self.activeOCRCount = max(0, self.activeOCRCount - 1)
            }
        }

        do {
            let pageBounds = doc.pageBounds[pageIndex]
            let maxDim = max(pageBounds.width, pageBounds.height)
            let result: PDFOCRPageResult

            if maxDim > 1200 {
                // Tiled high-resolution OCR for large schematics, posters, and technical drawings
                var tileResults: [PDFOCRPageResult] = []
                let targetTileSize: CGFloat = 1100.0
                let overlap: CGFloat = 60.0
                let step = targetTileSize - overlap

                var y = pageBounds.minY
                while y < pageBounds.maxY {
                    let tileH = min(targetTileSize, pageBounds.maxY - y)
                    var x = pageBounds.minX
                    while x < pageBounds.maxX {
                        let tileW = min(targetTileSize, pageBounds.maxX - x)
                        let tileRect = CGRect(x: x, y: y, width: tileW, height: tileH)

                        let tileImage = try await renderActor.renderPageRect(
                            pageIndex: pageIndex,
                            rect: tileRect,
                            scale: 300.0 / 72.0
                        )
                        let res = try await PDFOCREngine.shared.recognizeText(
                            in: tileImage,
                            pageIndex: pageIndex,
                            pageBounds: tileRect
                        )
                        tileResults.append(res)

                        if x + tileW >= pageBounds.maxX { break }
                        x += step
                    }
                    if y + tileH >= pageBounds.maxY { break }
                    y += step
                }
                result = await PDFOCREngine.shared.mergeOCRResults(pageIndex: pageIndex, results: tileResults)
            } else {
                let rendered = try await renderActor.renderPage(pageIndex: pageIndex, scale: 300.0 / 72.0)
                result = try await PDFOCREngine.shared.recognizeText(
                    in: rendered.image,
                    pageIndex: pageIndex,
                    pageBounds: pageBounds
                )
            }
            await MainActor.run {
                guard self.document === doc, self.ocrGeneration == generation else { return }
                self.ocrResults[pageIndex] = result
                self.detectedScannedPages.remove(pageIndex)
                let query = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    self.performSearch(autoNavigate: false)
                }
            }
        } catch {
            print("OCR failed on page \(pageIndex): \(error)")
        }
    }

    public func runOCROnAllScannedPages() async {
        guard let doc = document else { return }
        let generation = ocrGeneration

        // Checking every page for extractable text is slow on a large document, so it happens off
        // the main thread; only the OCR bookkeeping itself comes back here.
        let scanned = await Task.detached(priority: .utility) {
            (0..<doc.pageCount).filter { doc.isScannedPage(pageIndex: $0) }
        }.value
        for pIdx in scanned {
            guard document === doc, ocrGeneration == generation else { return }
            if ocrResults[pIdx] == nil {
                await runOCR(onPageIndex: pIdx)
            }
        }
    }

    // MARK: - Page Thumbnail Generation

    public func requestThumbnail(for pageIndex: Int) {
        guard thumbnailImages[pageIndex] == nil, !thumbnailsLoading.contains(pageIndex), let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return }
        thumbnailsLoading.insert(pageIndex)
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let rendered = try await self.renderActor.renderPage(pageIndex: pageIndex, scale: 0.25)
                let cgImg = rendered.image
                let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: CGFloat(cgImg.width), height: CGFloat(cgImg.height)))
                await MainActor.run {
                    self.thumbnailImages[pageIndex] = nsImg
                    self.thumbnailsLoading.remove(pageIndex)
                }
            } catch {
                await MainActor.run {
                    _ = self.thumbnailsLoading.remove(pageIndex)
                }
            }
        }
    }

    // MARK: - Thumbnail Selection Management

    public func selectThumbnail(pageIndex: Int, isShift: Bool, isCommand: Bool) {
        if let doc = document {
            guard pageIndex >= 0, pageIndex < doc.pageCount else { return }
        }

        if isCommand {
            if selectedThumbnailPageIndices.contains(pageIndex) {
                if selectedThumbnailPageIndices.count > 1 {
                    selectedThumbnailPageIndices.remove(pageIndex)
                }
            } else {
                selectedThumbnailPageIndices.insert(pageIndex)
            }
            selectionAnchorPageIndex = pageIndex
            jumpToPage(pageIndex)
        } else if isShift {
            let start = min(selectionAnchorPageIndex, pageIndex)
            let end = max(selectionAnchorPageIndex, pageIndex)
            selectedThumbnailPageIndices = Set(start...end)
            jumpToPage(pageIndex)
        } else {
            selectedThumbnailPageIndices = [pageIndex]
            selectionAnchorPageIndex = pageIndex
            jumpToPage(pageIndex)
        }
    }

    public func selectAllThumbnails() {
        guard let doc = document, doc.pageCount > 0 else { return }
        selectedThumbnailPageIndices = Set(0..<doc.pageCount)
    }

    // MARK: - Thumbnail Drag and Drop Lifecycle

    public func startThumbnailDrag(pageIndex: Int) {
        self.endThumbnailDrag()

        // If the dragged thumbnail is part of multi-selection, drag the whole selection;
        // otherwise, collapse selection to just this page.
        if selectedThumbnailPageIndices.contains(pageIndex) {
            self.draggedThumbnailPageIndices = selectedThumbnailPageIndices
        } else {
            self.selectedThumbnailPageIndices = [pageIndex]
            self.selectionAnchorPageIndex = pageIndex
            self.draggedThumbnailPageIndices = [pageIndex]
        }
        self.draggedThumbnailPageIndex = pageIndex

        // Local event monitor for immediate mouse-up and Escape key detection
        self.dragEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if event.type == .leftMouseUp || (event.type == .keyDown && event.keyCode == 53 /* Escape */) {
                    self.endThumbnailDrag()
                }
            }
            return event
        }

        // Repeating timer in .common run loop mode to guarantee reset if mouse is released anywhere,
        // even if AppKit's dragging session swallowed the mouse-up event.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if self.draggedThumbnailPageIndex == nil || (NSEvent.pressedMouseButtons & 1) == 0 {
                    self.endThumbnailDrag()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.dragWatchdogTimer = timer
    }

    public func endThumbnailDrag() {
        self.dragWatchdogTimer?.invalidate()
        self.dragWatchdogTimer = nil
        if let monitor = self.dragEventMonitor {
            NSEvent.removeMonitor(monitor)
            self.dragEventMonitor = nil
        }
        if self.draggedThumbnailPageIndex != nil || !self.draggedThumbnailPageIndices.isEmpty || self.activeThumbnailDropSlot != nil {
            self.draggedThumbnailPageIndex = nil
            self.draggedThumbnailPageIndices = []
            self.activeThumbnailDropSlot = nil
        }
    }
    
    /// The single decision point for every *explicit* "open this document" action (File > Open,
    /// the toolbar Open button, clicking a Favorite): load directly into this window/tab if it's
    /// still empty, otherwise always open a genuinely separate window — never a tab — so all of
    /// these actions behave identically regardless of which one you used. Drag-and-drop is the
    /// one exception, handled separately via onOpenNewTab (see its doc comment).
    public func openDocumentPreferringNewWindow(atPath path: String) {
        Task { @MainActor in
            if self.document == nil {
                await self.loadDocument(from: path)
            } else if let onOpenNewWindow = self.onOpenNewWindow {
                onOpenNewWindow(URL(fileURLWithPath: path))
            } else {
                await self.loadDocument(from: path)
            }
        }
    }

    /// Opens `path` directly into this window/tab if still empty, otherwise appends it as a new tab
    /// in the current window's tab group.
    public func openDocumentInNewTab(atPath path: String) {
        Task { @MainActor in
            if self.document == nil {
                await self.loadDocument(from: path)
            } else if let onOpenNewTab = self.onOpenNewTab {
                onOpenNewTab(URL(fileURLWithPath: path))
            } else {
                await self.loadDocument(from: path)
            }
        }
    }

    /// Total tabs in this window's tab group, including this one — 1 if it isn't tabbed with
    /// anything. Drives whether "Save All Open Tabs as a Group..." is offered at all (only makes
    /// sense once there's more than one tab to bundle up).
    public var currentWindowTabCount: Int {
        currentWindow?.tabbedWindows?.count ?? 1
    }

    private var currentWindowTabPaths: [String] {
        let windows = currentWindow.map { $0.tabbedWindows ?? [$0] } ?? []
        return windows.compactMap { $0.representedURL?.path }
    }

    /// Overwrites the saved Tab Group this window belongs to (`groupOrigin`) with whatever tabs
    /// are currently open here. No-op if this window isn't an instance of a saved group.
    public func updateGroupFromCurrentTabs() {
        guard let groupOrigin else { return }
        let paths = currentWindowTabPaths
        guard !paths.isEmpty else { return }
        TabGroupManager.shared.updateDocumentPaths(for: groupOrigin, to: paths)
    }

    /// Prompts for a name (a plain NSAlert, matching promptOpenFile's NSOpenPanel style — no
    /// SwiftUI view-local state needed, so this works identically whether triggered from the
    /// toolbar or the app's menu bar) and saves every tab currently open in this window as a new
    /// Tab Group.
    public func promptSaveCurrentWindowAsGroup() {
        let paths = currentWindowTabPaths
        guard !paths.isEmpty, !Self.isRunningTests else { return }

        let alert = NSAlert()
        alert.messageText = "Save Window as Tab Group"
        alert.informativeText = "Saves all \(paths.count) open tabs in this window as a group you can reopen together."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        field.placeholderString = "Group Name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            TabGroupManager.shared.addGroup(name: name, documentPaths: paths)
        }

        if let window = currentWindow ?? NSApplication.shared.keyWindow, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    public func promptOpenFile(inNewTab: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = inNewTab ? "Open PDF in New Tab" : "Open PDF"

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            if inNewTab {
                self?.openDocumentInNewTab(atPath: url.path)
            } else {
                self?.openDocumentPreferringNewWindow(atPath: url.path)
            }
        }
        
        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            if window.attachedSheet == nil {
                panel.beginSheetModal(for: window, completionHandler: completion)
                return
            }
        }
        panel.begin(completionHandler: completion)
    }
    
    public func updateWidgetValueDebounced(pageIndex: Int, widgetIndex: Int, value: String) {
        let key = "p\(pageIndex)_w\(widgetIndex)"
        debouncedWidgetTasks[key]?.cancel()
        pendingWidgetValues[key] = (pageIndex, widgetIndex, value)
        
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
        
        debouncedWidgetTasks[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
            guard !Task.isCancelled else { return }
            self?.debouncedWidgetTasks.removeValue(forKey: key)
            self?.pendingWidgetValues.removeValue(forKey: key)
            self?.commitWidgetValue(pageIndex: pageIndex, widgetIndex: widgetIndex, value: value)
        }
    }
    
    public func updateWidgetValue(pageIndex: Int, widgetIndex: Int, value: String) {
        let key = "p\(pageIndex)_w\(widgetIndex)"
        debouncedWidgetTasks[key]?.cancel()
        debouncedWidgetTasks.removeValue(forKey: key)
        pendingWidgetValues.removeValue(forKey: key)
        commitWidgetValue(pageIndex: pageIndex, widgetIndex: widgetIndex, value: value)
    }
    
    /// Flushes any pending debounced form edits and commits active field edits immediately.
    public func flushPendingFormEdits() {
        currentWindow?.makeFirstResponder(nil)
        guard !pendingWidgetValues.isEmpty else { return }
        for (_, task) in debouncedWidgetTasks {
            task.cancel()
        }
        debouncedWidgetTasks.removeAll()
        let pending = pendingWidgetValues
        pendingWidgetValues.removeAll()
        for (_, entry) in pending {
            commitWidgetValue(pageIndex: entry.pageIndex, widgetIndex: entry.widgetIndex, value: entry.value)
        }
    }
    
    private func commitWidgetValue(pageIndex: Int, widgetIndex: Int, value: String) {
        guard let doc = document else { return }
        // Focusing a field and leaving it commits its value too; unchanged, that's not an edit.
        if let current = pageFormWidgets[pageIndex]?.first(where: { $0.widgetIndex == widgetIndex }),
           current.value == value {
            return
        }
        do {
            try doc.setFormWidgetValue(pageIndex: pageIndex, widgetIndex: widgetIndex, value: value)
            let refreshed = doc.loadFormWidgets(for: pageIndex)
            pageFormWidgets[pageIndex] = refreshed
            // Other pages only matter if they have fields a calculation could have changed.
            for otherPage in pageFormWidgets.keys where otherPage != pageIndex && pageFormWidgets[otherPage]?.isEmpty == false {
                pageFormWidgets[otherPage] = doc.loadFormWidgets(for: otherPage)
            }
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            NotificationCenter.default.post(name: .formWidgetDidChange, object: nil)
        } catch {
            print("Failed to set form widget value: \(error)")
        }
    }
    
    public func resetForm() {
        guard let doc = document else { return }
        for (_, task) in debouncedWidgetTasks {
            task.cancel()
        }
        debouncedWidgetTasks.removeAll()
        pendingWidgetValues.removeAll()
        do {
            try doc.resetForm()
            for page in pageFormWidgets.keys {
                pageFormWidgets[page] = doc.loadFormWidgets(for: page)
            }
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            NotificationCenter.default.post(name: .formWidgetDidChange, object: nil)
        } catch {
            print("Failed to reset form: \(error)")
        }
    }
    
    /// Places a visual signature stamp (drawn or picked image, not a cryptographic signature) into
    /// `rect` on a page. PDFSignatureStampButton shows the image itself, so no on-screen preview
    /// refresh is needed here beyond updating the in-memory document for the next save.
    public func insertSignatureStamp(pageIndex: Int, rect: CGRect, imageData: Data) {
        guard let doc = document else { return }
        // `rect` (PDFFormWidget.rect) is top-down; stampImage needs bottom-up. Flip using
        // pageBounds' actual top edge (maxY), not height, since MediaBox may not start at y=0.
        let pageTopY = doc.pageBounds[pageIndex].maxY
        let nativeRect = CGRect(x: rect.minX, y: pageTopY - rect.maxY, width: rect.width, height: rect.height)
        do {
            try doc.stampImage(pageIndex: pageIndex, rect: nativeRect, imageData: imageData)
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
        } catch {
            print("Failed to insert signature stamp: \(error)")
        }
    }

    /// Arms fileChangeWatcher for `path`, calling back into handleExternalFileChange on a real
    /// external change, or handleExternalFileMove on a Finder / iCloud rename or move.
    private func armFileChangeWatcher(path: String) {
        fileChangeWatcher = FileChangeWatcher(path: path, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleExternalFileChange(path: path)
            }
        }, onMove: { [weak self] newURL in
            Task { @MainActor [weak self] in
                self?.handleExternalFileMove(to: newURL)
            }
        })
    }

    public func handleExternalFileMove(to newURL: URL) {
        guard let doc = document else { return }
        let oldPath = doc.filePath
        let newPath = newURL.path
        guard oldPath != newPath else { return }

        doc.updateFilePath(newPath)
        let fileName = newURL.lastPathComponent
        self.documentTitle = fileName
        if let window = currentWindow ?? NSApplication.shared.keyWindow {
            window.title = fileName
            window.representedURL = newURL
        }
        updateReadingUserActivity()
    }

    private func waitForCloudDownload(url: URL, timeoutSeconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled || isCloudDownloadCancelled { return false }
            let (isEvicted, isDownloading) = CloudStorageHelper.checkDownloadStatus(for: url)
            if !isEvicted && !isDownloading && FileManager.default.fileExists(atPath: url.path) {
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return false
    }

    public func cancelCloudDownload() {
        isCloudDownloadCancelled = true
        isDownloadingFromCloud = false
        cloudDownloadStatusMessage = nil
    }

    public func updateReadingUserActivity() {
        guard let doc = document else {
            readingUserActivity?.invalidate()
            readingUserActivity = nil
            return
        }
        let path = doc.filePath
        let canonical = CloudStorageHelper.canonicalKey(for: path)

        if readingUserActivity == nil {
            let activity = NSUserActivity(activityType: "com.thomasderham.vectorpdf.document-reading")
            activity.title = documentTitle
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.isEligibleForPublicIndexing = false
            readingUserActivity = activity
        }

        guard let activity = readingUserActivity else { return }
        activity.title = documentTitle
        activity.userInfo = [
            "filePath": path,
            "canonicalKey": canonical,
            "pageIndex": currentPageIndex,
            "zoomScale": Double(zoomScale),
            "documentTitle": documentTitle
        ]
        activity.needsSave = true
        activity.becomeCurrent()
    }

    public func saveDocument() {
        guard let doc = document else { return }
        flushPendingFormEdits()
        // Suspend for our own write (an atomic replace, indistinguishable from an external change)
        // to avoid a pointless self-triggered reload; re-arm right after.
        fileChangeWatcher = nil
        defer { armFileChangeWatcher(path: doc.filePath) }
        let actorsOnWorkingCopy = workingCopyPath != nil
        do {
            try doc.save(to: doc.filePath)
            self.isDocumentEdited = false
            self.currentWindow?.isDocumentEdited = false
            cleanupWorkingCopy()
            // The file on disk changed, so a cached index for it is stale; and if the in-memory
            // index came from the working copy, it's now indexing a deleted file.
            invalidateAgentIndex(deleteCache: true)
            if actorsOnWorkingCopy {
                // The render/search actors had the working copy open; it no longer exists.
                let savedPath = doc.filePath
                Task { @MainActor [weak self] in
                    await self?.reopenActors(at: savedPath)
                }
            }
        } catch {
            print("Failed to save document: \(error)")
            // showErrorAlert is a no-op under the test runner — a bare runModal() here hangs a
            // headless test run forever.
            showErrorAlert(title: "Failed to Save Document", message: error.localizedDescription)
        }
    }
    
    public func saveDocumentAs() {
        guard let doc = document else { return }
        flushPendingFormEdits()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (doc.filePath as NSString).lastPathComponent
        panel.prompt = "Save As"
        
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self = self, let doc = self.document else { return }
                do {
                    try doc.save(to: url.path)
                    self.isDocumentEdited = false
                    self.currentWindow?.isDocumentEdited = false
                    self.cleanupWorkingCopy()
                    await self.loadDocument(from: url.path)
                } catch {
                    print("Failed to save document as: \(error)")
                    self.showErrorAlert(title: "Failed to Save Document", message: error.localizedDescription)
                }
            }
        }
        
        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            if window.attachedSheet == nil {
                panel.beginSheetModal(for: window, completionHandler: completion)
                return
            }
        }
        panel.begin(completionHandler: completion)
    }

    /// Prompts the user with a save panel to save the open PDF as a flattened document (baking annotations and form widgets into static content).
    public func saveDocumentFlattenedAs() {
        guard let doc = document else { return }
        flushPendingFormEdits()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canCreateDirectories = true
        let originalName = (doc.filePath as NSString).lastPathComponent
        let baseName = (originalName as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName) (Flattened).pdf"
        panel.prompt = "Save Flattened"
        panel.title = "Save as Flattened PDF"

        // Accessory view providing fine-grained flattening options
        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 52))
        let annotCheckbox = NSButton(checkboxWithTitle: "Flatten annotations and markups", target: nil, action: nil)
        annotCheckbox.frame = NSRect(x: 10, y: 28, width: 320, height: 18)
        annotCheckbox.state = .on

        let widgetCheckbox = NSButton(checkboxWithTitle: "Flatten form fields (make static)", target: nil, action: nil)
        widgetCheckbox.frame = NSRect(x: 10, y: 6, width: 320, height: 18)
        widgetCheckbox.state = .on

        accessoryView.addSubview(annotCheckbox)
        accessoryView.addSubview(widgetCheckbox)
        panel.accessoryView = accessoryView

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let bakeAnnots = annotCheckbox.state == .on
            let bakeWidgets = widgetCheckbox.state == .on
            Task { @MainActor in
                guard let self = self, let doc = self.document else { return }
                do {
                    try doc.saveFlattened(to: url.path, bakeAnnotations: bakeAnnots, bakeWidgets: bakeWidgets)
                    PDFViewerAppCoordinator.shared.noteRecentDocument(url)
                    if url.path == doc.filePath {
                        // User chose to overwrite the active document with the flattened version
                        self.isDocumentEdited = false
                        self.currentWindow?.isDocumentEdited = false
                        self.cleanupWorkingCopy()
                        await self.loadDocument(from: url.path)
                    }
                } catch {
                    print("Failed to save flattened document: \(error)")
                    self.showErrorAlert(title: "Failed to Save Flattened Document", message: error.localizedDescription)
                }
            }
        }

        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            if window.attachedSheet == nil {
                panel.beginSheetModal(for: window, completionHandler: completion)
                return
            }
        }
        panel.begin(completionHandler: completion)
    }

    /// Prompts the user for a destination and password, then saves the current PDF encrypted with AES-256.
    public func saveDocumentEncryptedAs() {
        guard let doc = document else { return }
        flushPendingFormEdits()
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canCreateDirectories = true
        let originalName = (doc.filePath as NSString).lastPathComponent
        let baseName = (originalName as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName) (Encrypted).pdf"
        panel.prompt = "Save Encrypted"
        
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let targetURL = panel.url else { return }
            Task { @MainActor in
                guard let self = self, let doc = self.document, !Self.isRunningTests else { return }
                
                let alert = NSAlert()
                alert.messageText = "Set Document Password"
                alert.informativeText = "Enter a password to encrypt “\(targetURL.lastPathComponent)”. A password will be required to open this document."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Encrypt & Save")
                alert.addButton(withTitle: "Cancel")
                
                let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 75))
                let passwordLabel = NSTextField(labelWithString: "Password:")
                passwordLabel.frame = NSRect(x: 0, y: 48, width: 80, height: 18)
                let passwordField = NSSecureTextField(frame: NSRect(x: 85, y: 46, width: 215, height: 22))
                
                let verifyLabel = NSTextField(labelWithString: "Verify:")
                verifyLabel.frame = NSRect(x: 0, y: 16, width: 80, height: 18)
                let verifyField = NSSecureTextField(frame: NSRect(x: 85, y: 14, width: 215, height: 22))
                
                container.addSubview(passwordLabel)
                container.addSubview(passwordField)
                container.addSubview(verifyLabel)
                container.addSubview(verifyField)
                alert.accessoryView = container
                
                let modalResponse: NSApplication.ModalResponse
                if let window = self.currentWindow ?? NSApplication.shared.keyWindow, window.attachedSheet == nil {
                    modalResponse = await withCheckedContinuation { continuation in
                        alert.beginSheetModal(for: window) { resp in
                            continuation.resume(returning: resp)
                        }
                    }
                } else {
                    modalResponse = alert.runModal()
                }
                
                guard modalResponse == .alertFirstButtonReturn else { return }
                let password = passwordField.stringValue
                let verify = verifyField.stringValue
                
                guard !password.isEmpty else {
                    self.showErrorAlert(title: "Password Cannot Be Empty", message: "Please provide a non-empty password to encrypt the document.")
                    return
                }
                
                guard password == verify else {
                    self.showErrorAlert(title: "Passwords Do Not Match", message: "The entered passwords do not match. Please try again.")
                    return
                }
                
                do {
                    try doc.saveEncrypted(to: targetURL.path, password: password)
                    PDFViewerAppCoordinator.shared.noteRecentDocument(targetURL)
                } catch {
                    print("Failed to save encrypted document: \(error)")
                    self.showErrorAlert(title: "Failed to Encrypt Document", message: error.localizedDescription)
                }
            }
        }
        
        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            if window.attachedSheet == nil {
                panel.beginSheetModal(for: window, completionHandler: completion)
                return
            }
        }
        panel.begin(completionHandler: completion)
    }

    /// Displays the native macOS sharing pane (AirDrop, Mail, Messages, etc.) for the current document.
    public func shareDocument(from positioningView: NSView? = nil) {
        guard let doc = document, !doc.filePath.isEmpty else { return }
        let fileURL = URL(fileURLWithPath: doc.filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        
        let picker = NSSharingServicePicker(items: [fileURL])
        if let targetView = positioningView ?? currentWindow?.contentView {
            let rect = NSRect(x: targetView.bounds.midX, y: targetView.bounds.maxY - 10, width: 1, height: 1)
            picker.show(relativeTo: rect, of: targetView, preferredEdge: .minY)
        }
    }

    /// Reveals the current PDF document file in Finder.
    public func showInFinder() {
        guard let doc = document, !doc.filePath.isEmpty else { return }
        let fileURL = URL(fileURLWithPath: doc.filePath)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// True under `swift test` / XCTest, where a modal alert would hang the headless run forever.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains { $0.contains("swiftpm-testing-helper") || $0.contains("xctest") }
    }

    private func showErrorAlert(title: String, message: String) {
        if Self.isRunningTests {
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        if let window = currentWindow ?? NSApplication.shared.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Working-copy plumbing

    /// Reopens the render and search actors at `path` using the document's password.
    private func reopenActors(at path: String) async {
        searchTask?.cancel()
        let password = currentDocumentPassword
        do {
            try await renderActor.openDocument(filePath: path, password: password)
        } catch {
            print("Failed to reopen render actor on \(path): \(error)")
        }
        do {
            try await searchActor.openDocument(filePath: path, password: password)
        } catch {
            print("Failed to reopen search actor on \(path): \(error)")
        }
        // Refresh active search on updated content.
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isSearching = false
        } else {
            performSearch()
        }
    }

    /// Drops everything cached per page *index* after pages were inserted, deleted, reordered or
    /// duplicated — those caches now describe different pages. Form widgets, OCR results and
    /// scale calibrations are re-derived on demand from the (already updated) document.
    private func invalidateStructuralState() {
        ocrGeneration += 1
        invalidateAgentIndex(deleteCache: false)
        pageFormWidgets.removeAll()
        ocrResults.removeAll()
        detectedScannedPages.removeAll()
        pageScaleConfigs.removeAll()
        // Back/Forward entries are page indices too, and now name different pages.
        navigationHistory.removeAll()
        navigationHistoryIndex = -1
        updateNavigationHistoryState()
        startScannedPageDetection()
    }

    // MARK: - Anchor protection for page edits

    /// Anchors that a page edit touching pages `firstPage...lastPage` would leave pointing at the
    /// wrong page, or at one that no longer exists — an anchor stores a plain page index, and is
    /// not remapped when pages are inserted, deleted or moved.
    func anchorsAffected(byPageEditFrom firstPage: Int, through lastPage: Int = .max) -> [SnapshotTarget] {
        activeSnapshots.filter { $0.targetPage >= firstPage && $0.targetPage <= lastPage }
    }

    /// Runs `edit` — a change that shifts or removes the pages in `firstPage...lastPage` — after
    /// warning about any anchors it would break. The user can make the change in a copy saved
    /// under a new name (which starts without anchors, leaving this document's intact), go ahead
    /// regardless, or cancel.
    private func performPageEdit(
        affectingPagesFrom firstPage: Int,
        through lastPage: Int = .max,
        _ edit: @escaping @MainActor @Sendable () -> Void
    ) {
        let affected = anchorsAffected(byPageEditFrom: firstPage, through: lastPage)
        guard !affected.isEmpty, !Self.isRunningTests, let doc = document else {
            edit()
            return
        }

        let alert = NSAlert()
        alert.messageText = affected.count == 1
            ? "This Change Affects an Anchor"
            : "This Change Affects \(affected.count) Anchors"
        alert.informativeText = "Anchors remember a page number, so adding, deleting or moving pages would leave "
            + (affected.count == 1 ? "it" : "them")
            + " pointing at the wrong place. You can make the change in a copy saved under a new name instead — the copy starts without anchors, and “\(documentTitle)” keeps its anchors as they are."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save as Copy…")   // .alertFirstButtonReturn
        alert.addButton(withTitle: "Cancel")          // .alertSecondButtonReturn
        alert.addButton(withTitle: "Edit Anyway")     // .alertThirdButtonReturn

        let handle: @MainActor @Sendable (NSApplication.ModalResponse) -> Void = { [weak self] response in
            // The document may have been closed or replaced while the alert was up.
            guard let self, self.document === doc else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.promptSaveCopyForPageEdit(edit)
            case .alertThirdButtonReturn:
                edit()
            default:
                break
            }
        }

        if let window = currentWindow ?? NSApplication.shared.keyWindow, window.attachedSheet == nil {
            alert.beginSheetModal(for: window) { response in
                // Hop off the sheet's dismissal so the save panel can attach to the same window.
                Task { @MainActor in handle(response) }
            }
        } else {
            handle(alert.runModal())
        }
    }

    private func promptSaveCopyForPageEdit(_ edit: @escaping @MainActor @Sendable () -> Void) {
        guard let doc = document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canCreateDirectories = true
        let baseName = ((doc.filePath as NSString).lastPathComponent as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName) copy.pdf"
        panel.directoryURL = URL(fileURLWithPath: doc.filePath).deletingLastPathComponent()
        panel.prompt = "Save Copy"
        panel.message = "The page change will be made in this copy."

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.continuePageEdit(onCopyAt: url, edit)
            }
        }

        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow,
           window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: completion)
            return
        }
        panel.begin(completionHandler: completion)
    }

    /// Saves the document as it stands to `url`, switches this window to that copy, and applies
    /// `edit` there. Returns whether the edit was applied.
    @discardableResult
    func continuePageEdit(onCopyAt url: URL, _ edit: @MainActor @Sendable () -> Void) async -> Bool {
        guard let doc = document else { return false }
        let original = URL(fileURLWithPath: doc.filePath).standardizedFileURL.resolvingSymlinksInPath()
        guard url.standardizedFileURL.resolvingSymlinksInPath() != original else {
            showErrorAlert(
                title: "Choose a Different Name",
                message: "The copy has to be saved under a new name — saving over “\(documentTitle)” would keep its anchors."
            )
            return false
        }
        flushPendingFormEdits()
        do {
            try doc.save(to: url.path)
        } catch {
            print("Failed to save copy for page edit: \(error)")
            showErrorAlert(title: "Failed to Save Copy", message: error.localizedDescription)
            return false
        }
        // The copy starts without anchors (also clearing any left by a file it just replaced),
        // but opens at the same page and zoom.
        ReadingStateManager.shared.updateState(
            for: url.path,
            lastPageIndex: currentPageIndex,
            zoomScale: zoomScale,
            snapshots: []
        )
        // The unsaved edits went into the copy; the original on disk is left as it was.
        isDocumentEdited = false
        currentWindow?.isDocumentEdited = false
        cleanupWorkingCopy()
        await loadDocument(from: url.path, password: currentDocumentPassword)
        guard let copy = document, copy !== doc else { return false }
        edit()
        return true
    }

    /// Finds scanned (text-less) pages among the first 50 off the main thread, then OCRs them.
    private func startScannedPageDetection() {
        guard let doc = document else { return }
        let generation = ocrGeneration
        Task { [weak self] in
            let limit = min(doc.pageCount, 50)
            let scanned = await Task.detached(priority: .utility) {
                (0..<limit).filter { doc.isScannedPage(pageIndex: $0) }
            }.value
            guard let self, self.document === doc, self.ocrGeneration == generation, !scanned.isEmpty else { return }
            self.detectedScannedPages.formUnion(scanned)
            // Only the pages just found — OCRing the rest of a long scanned document is left to
            // "Run OCR" (or a search), rather than starting it for every page on open.
            for pageIndex in scanned {
                guard self.document === doc, self.ocrGeneration == generation else { return }
                await self.runOCR(onPageIndex: pageIndex)
            }
        }
    }

    // MARK: - Page Manipulation
    public func rotatePage(_ pageIndex: Int, by degrees: Int = 90) {
        guard let doc = document else { return }
        do {
            try doc.rotatePage(pageIndex, by: degrees)
            if workingCopyPath == nil {
                workingCopyPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("working_\(UUID().uuidString).pdf").path
            }
            guard let workingPath = workingCopyPath else {
                return
            }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                self.renderedPages.removeValue(forKey: pageIndex)
                self.thumbnailImages.removeValue(forKey: pageIndex)
                self.pageAnnotations.removeValue(forKey: pageIndex)
                self.pageStructuredData.removeValue(forKey: pageIndex)
                self.pageLinks.removeValue(forKey: pageIndex)
                self.pageFormWidgets.removeValue(forKey: pageIndex)
                self.objectWillChange.send()
                self.requestThumbnail(for: pageIndex)
                await self.renderPage(pageIndex)
            }
        } catch {
            print("Failed to rotate page \(pageIndex): \(error)")
        }
    }

    public func deletePage(_ pageIndex: Int) {
        guard let doc = document, doc.pageCount > 1 else { return }
        performPageEdit(affectingPagesFrom: pageIndex) { [weak self] in
            self?.applyDeletePage(pageIndex)
        }
    }

    private func applyDeletePage(_ pageIndex: Int) {
        guard let doc = document, doc.pageCount > 1 else { return }
        do {
            try doc.deletePage(pageIndex)
            if workingCopyPath == nil {
                workingCopyPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("working_\(UUID().uuidString).pdf").path
            }
            guard let workingPath = workingCopyPath else {
                return
            }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()
                if self.currentPageIndex >= doc.pageCount {
                    self.currentPageIndex = max(0, doc.pageCount - 1)
                }
                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, self.currentPageIndex - 8)
                let end = min(doc.pageCount, self.currentPageIndex + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to delete page \(pageIndex): \(error)")
        }
    }

    public func reorderPage(from fromIndex: Int, to toIndex: Int) {
        self.endThumbnailDrag()
        guard let doc = document else { return }
        guard fromIndex != toIndex, fromIndex >= 0, fromIndex < doc.pageCount, toIndex >= 0, toIndex < doc.pageCount else { return }
        performPageEdit(affectingPagesFrom: min(fromIndex, toIndex), through: max(fromIndex, toIndex)) { [weak self] in
            self?.applyReorderPage(from: fromIndex, to: toIndex)
        }
    }

    private func applyReorderPage(from fromIndex: Int, to toIndex: Int) {
        guard let doc = document else { return }
        guard fromIndex != toIndex, fromIndex >= 0, fromIndex < doc.pageCount, toIndex >= 0, toIndex < doc.pageCount else { return }
        do {
            try doc.reorderPage(from: fromIndex, to: toIndex)
            if workingCopyPath == nil {
                workingCopyPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("working_\(UUID().uuidString).pdf").path
            }
            guard let workingPath = workingCopyPath else {
                return
            }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.endThumbnailDrag()
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()
                self.currentPageIndex = toIndex
                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, toIndex - 8)
                let end = min(doc.pageCount, toIndex + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to reorder page from \(fromIndex) to \(toIndex): \(error)")
        }
    }

    public func reorderPages(from fromIndices: [Int], toSlot destSlot: Int) {
        self.endThumbnailDrag()
        guard let doc = document else { return }
        guard !fromIndices.isEmpty,
              ThumbnailDropLogic.isValidSlot(slot: destSlot, fromIndices: Set(fromIndices), pageCount: doc.pageCount) else {
            return
        }
        let sortedFrom = fromIndices.sorted()
        performPageEdit(
            affectingPagesFrom: min(sortedFrom[0], destSlot),
            through: max(sortedFrom[sortedFrom.count - 1], destSlot - 1)
        ) { [weak self] in
            self?.applyReorderPages(from: sortedFrom, toSlot: destSlot)
        }
    }

    private func applyReorderPages(from sortedFrom: [Int], toSlot destSlot: Int) {
        guard let doc = document else { return }
        guard !sortedFrom.isEmpty,
              ThumbnailDropLogic.isValidSlot(slot: destSlot, fromIndices: Set(sortedFrom), pageCount: doc.pageCount) else {
            return
        }
        let beforeCount = sortedFrom.filter { $0 < destSlot }.count
        let targetStartingIndex = destSlot - beforeCount

        do {
            try doc.reorderPages(from: sortedFrom, toSlot: destSlot)
            if workingCopyPath == nil {
                workingCopyPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("working_\(UUID().uuidString).pdf").path
            }
            guard let workingPath = workingCopyPath else { return }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.endThumbnailDrag()
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()

                let newSelectedRange = Set(targetStartingIndex..<(targetStartingIndex + sortedFrom.count))
                self.selectedThumbnailPageIndices = newSelectedRange
                self.selectionAnchorPageIndex = targetStartingIndex
                self.currentPageIndex = targetStartingIndex

                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, targetStartingIndex - 8)
                let end = min(doc.pageCount, targetStartingIndex + sortedFrom.count + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to reorder pages from \(sortedFrom) to slot \(destSlot): \(error)")
        }
    }

    public func deleteSelectedThumbnails() {
        guard let doc = document else { return }
        let toDelete = selectedThumbnailPageIndices.sorted()
        guard !toDelete.isEmpty, toDelete.count < doc.pageCount else { return }
        performPageEdit(affectingPagesFrom: toDelete[0]) { [weak self] in
            self?.applyDeletePages(toDelete)
        }
    }

    private func applyDeletePages(_ toDelete: [Int]) {
        guard let doc = document else { return }
        guard !toDelete.isEmpty, toDelete.count < doc.pageCount else { return }
        do {
            try doc.deletePages(toDelete)
            if workingCopyPath == nil {
                workingCopyPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("working_\(UUID().uuidString).pdf").path
            }
            guard let workingPath = workingCopyPath else { return }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()

                let targetPage = min(toDelete[0], doc.pageCount - 1)
                self.currentPageIndex = targetPage
                self.selectedThumbnailPageIndices = [targetPage]
                self.selectionAnchorPageIndex = targetPage

                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, targetPage - 8)
                let end = min(doc.pageCount, targetPage + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to delete pages \(toDelete): \(error)")
        }
    }

    public func rotateSelectedThumbnails(by degrees: Int = 90) {
        guard let doc = document else { return }
        let toRotate = selectedThumbnailPageIndices.sorted()
        guard !toRotate.isEmpty else { return }
        do {
            try doc.rotatePages(toRotate, by: degrees)
            if workingCopyPath == nil {
                workingCopyPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("working_\(UUID().uuidString).pdf").path
            }
            guard let workingPath = workingCopyPath else { return }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                for p in toRotate {
                    self.renderedPages.removeValue(forKey: p)
                    self.thumbnailImages.removeValue(forKey: p)
                    self.pageAnnotations.removeValue(forKey: p)
                    self.pageStructuredData.removeValue(forKey: p)
                    self.pageLinks.removeValue(forKey: p)
                    self.pageFormWidgets.removeValue(forKey: p)
                }
                self.objectWillChange.send()
                for p in toRotate {
                    self.requestThumbnail(for: p)
                }
                await self.renderPage(self.currentPageIndex)
            }
        } catch {
            print("Failed to rotate pages \(toRotate): \(error)")
        }
    }

    public func extractSelectedThumbnails() {
        let pages = selectedThumbnailPageIndices.sorted()
        guard !pages.isEmpty else { return }
        extractPages(pages)
    }

    public func extractPage(_ pageIndex: Int) {
        extractPages([pageIndex])
    }

    public func extractPages(_ pageIndices: [Int]) {
        guard let doc = document, !pageIndices.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        let baseName = ((doc.filePath as NSString).lastPathComponent as NSString).deletingPathExtension
        if pageIndices.count == 1 {
            panel.nameFieldStringValue = "\(baseName)_Page_\(pageIndices[0] + 1).pdf"
        } else {
            panel.nameFieldStringValue = "\(baseName)_Selected_Pages.pdf"
        }
        panel.prompt = "Save"

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try self?.document?.extractPages(pageIndices, to: url)
            } catch {
                print("Failed to extract pages: \(error)")
                Task { @MainActor [weak self] in
                    self?.showErrorAlert(title: "Failed to Extract Pages", message: error.localizedDescription)
                }
            }
        }

        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    public func duplicateSelectedThumbnails() {
        guard let doc = document else { return }
        let toDuplicate = selectedThumbnailPageIndices.sorted()
        guard doc.pageCount > 0, !toDuplicate.isEmpty else { return }
        // The copies are inserted right after the last selected page.
        performPageEdit(affectingPagesFrom: toDuplicate[toDuplicate.count - 1] + 1) { [weak self] in
            self?.applyDuplicatePages(toDuplicate)
        }
    }

    private func applyDuplicatePages(_ toDuplicate: [Int]) {
        guard let doc = document, !toDuplicate.isEmpty else { return }

        do {
            let (insertedSlot, count) = try doc.duplicatePages(toDuplicate)
            if workingCopyPath == nil {
                workingCopyPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("working_\(UUID().uuidString).pdf").path
            }
            guard let workingPath = workingCopyPath else { return }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()

                let newSelectedRange = Set(insertedSlot..<(insertedSlot + count))
                self.selectedThumbnailPageIndices = newSelectedRange
                self.selectionAnchorPageIndex = insertedSlot
                self.currentPageIndex = insertedSlot

                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, insertedSlot - 8)
                let end = min(doc.pageCount, insertedSlot + count + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to duplicate pages \(toDuplicate): \(error)")
        }
    }

    public func duplicatePage(_ pageIndex: Int) {
        selectedThumbnailPageIndices = [pageIndex]
        selectionAnchorPageIndex = pageIndex
        duplicateSelectedThumbnails()
    }

    public func insertBlankPage(after pageIndex: Int) {
        guard let doc = document else { return }
        let targetSlot = min(max(0, pageIndex + 1), doc.pageCount)
        insertBlankPage(atSlot: targetSlot)
    }

    public func insertBlankPageAtSelection() {
        guard let doc = document else { return }
        let maxSelected = selectedThumbnailPageIndices.max() ?? currentPageIndex
        let targetSlot = min(max(0, maxSelected + 1), doc.pageCount)
        insertBlankPage(atSlot: targetSlot)
    }

    public func insertBlankPage(atSlot slot: Int, width: CGFloat? = nil, height: CGFloat? = nil) {
        guard let doc = document else { return }
        let clampedSlot = max(0, min(slot, doc.pageCount))
        performPageEdit(affectingPagesFrom: clampedSlot) { [weak self] in
            self?.applyInsertBlankPage(atSlot: clampedSlot, width: width, height: height)
        }
    }

    private func applyInsertBlankPage(atSlot slot: Int, width: CGFloat?, height: CGFloat?) {
        guard let doc = document else { return }
        let clampedSlot = max(0, min(slot, doc.pageCount))

        do {
            let insertedSlot = try doc.insertBlankPage(atSlot: clampedSlot, width: width, height: height)
            if workingCopyPath == nil {
                workingCopyPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("working_\(UUID().uuidString).pdf").path
            }
            guard let workingPath = workingCopyPath else { return }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()

                let newSelectedRange: Set<Int> = [insertedSlot]
                self.selectedThumbnailPageIndices = newSelectedRange
                self.selectionAnchorPageIndex = insertedSlot
                self.currentPageIndex = insertedSlot

                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, insertedSlot - 8)
                let end = min(doc.pageCount, insertedSlot + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to insert blank page at slot \(clampedSlot): \(error)")
        }
    }

    public func importPages(from fileURL: URL, toSlot: Int? = nil) {
        guard let doc = document else { return }
        let slot = toSlot ?? (selectedThumbnailPageIndices.max().map { $0 + 1 } ?? doc.pageCount)
        let clampedSlot = max(0, min(slot, doc.pageCount))
        performPageEdit(affectingPagesFrom: clampedSlot) { [weak self] in
            self?.applyImportPages(from: fileURL, atSlot: clampedSlot)
        }
    }

    private func applyImportPages(from fileURL: URL, atSlot slot: Int) {
        guard let doc = document else { return }
        let clampedSlot = max(0, min(slot, doc.pageCount))

        do {
            let (insertedSlot, count) = try doc.importPages(from: fileURL, atSlot: clampedSlot)
            if workingCopyPath == nil {
                workingCopyPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("working_\(UUID().uuidString).pdf").path
            }
            guard let workingPath = workingCopyPath else { return }
            try doc.save(to: workingPath)
            self.isDocumentEdited = true
            self.currentWindow?.isDocumentEdited = true
            self.recomputeEffectiveLayout()
            Task { @MainActor in
                await self.reopenActors(at: workingPath)
                self.thumbnailVersion = UUID()
                self.renderedPages.removeAll()
                self.thumbnailImages.removeAll()
                self.pageAnnotations.removeAll()
                self.pageStructuredData.removeAll()
                self.pageLinks.removeAll()
                self.invalidateStructuralState()

                let newSelectedRange = Set(insertedSlot..<(insertedSlot + count))
                self.selectedThumbnailPageIndices = newSelectedRange
                self.selectionAnchorPageIndex = insertedSlot
                self.currentPageIndex = insertedSlot

                self.objectWillChange.send()
                await self.renderPage(self.currentPageIndex)
                self.loadPageMetadata(self.currentPageIndex)
                let start = max(0, insertedSlot - 8)
                let end = min(doc.pageCount, insertedSlot + count + 12)
                for p in start..<end {
                    self.requestThumbnail(for: p)
                }
            }
        } catch {
            print("Failed to import pages from \(fileURL.path): \(error)")
        }
    }

    public func promptImportPDF(atSlot slot: Int? = nil) {
        guard document != nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Insert"
        panel.message = "Choose a PDF file to insert into this document"

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importPages(from: url, toSlot: slot)
        }

        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }
    
    /// Prompts the user to Save, Don't Save, or Cancel when closing a document with unsaved edits.
    /// Returns true if closing should proceed (changes saved or discarded), or false if closing should abort.
    @MainActor
    public func promptSaveBeforeClosingIfNeeded() -> Bool {
        // Commit any pending active text field input before checking or saving
        currentWindow?.makeFirstResponder(nil)
        
        guard isDocumentEdited, let _ = document else { return true }
        // No one can answer a modal under the test runner; behave as "Don't Save".
        guard !Self.isRunningTests else { return true }
        
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to the document “\(documentTitle)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")          // .alertFirstButtonReturn (1000)
        alert.addButton(withTitle: "Cancel")        // .alertSecondButtonReturn (1001)
        alert.addButton(withTitle: "Don’t Save")     // .alertThirdButtonReturn (1002)
        
        if alert.buttons.count >= 3 {
            alert.buttons[0].keyEquivalent = "\r"
            alert.buttons[1].keyEquivalent = "\u{1b}" // Escape
            alert.buttons[2].keyEquivalent = "d"
            alert.buttons[2].keyEquivalentModifierMask = [.command]
        }
        
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // Save
            saveDocument()
            return !isDocumentEdited
        case .alertThirdButtonReturn: // Don't Save
            isDocumentEdited = false
            currentWindow?.isDocumentEdited = false
            cleanupWorkingCopy()
            return true
        default: // Cancel (.alertSecondButtonReturn)
            return false
        }
    }
    
    public func printDocument() {
        guard let doc = document else { return }
        flushPendingFormEdits()

        let printURL: URL
        var temporaryFileURL: URL? = nil
        
        if isDocumentEdited {
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".pdf")
            do {
                try doc.save(to: tempFile.path)
                printURL = tempFile
                temporaryFileURL = tempFile
            } catch {
                print("Failed to save temporary copy for printing: \(error)")
                printURL = URL(fileURLWithPath: doc.filePath)
            }
        } else {
            printURL = URL(fileURLWithPath: doc.filePath)
        }
        
        // Print through MuPDF (MuPDFPrintView) rather than PDFKit so the output matches the on-screen
        // rendering (font rasterization, blend modes, form appearances).

        // Isolate print settings on an optimized PDFPrintInfo rather than mutating the shared singleton
        let baseShared = NSPrintInfo.shared
        let dict = (baseShared.dictionary() as? [NSPrintInfo.AttributeKey: Any]) ?? [:]
        let printInfo = PDFPrintInfo(dictionary: dict)
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        printInfo.dictionary()[NSPrintInfo.AttributeKey.firstPage] = 1
        printInfo.dictionary()[NSPrintInfo.AttributeKey.lastPage] = doc.pageCount
        printInfo.dictionary()[NSPrintInfo.AttributeKey.allPages] = true

        if let firstPageBounds = doc.pageBounds.first {
            printInfo.orientation = (firstPageBounds.width > firstPageBounds.height) ? .landscape : .portrait
        }

        let printView: MuPDFPrintView
        do {
            printView = try MuPDFPrintView(filePath: printURL.path, password: currentDocumentPassword, pageCount: doc.pageCount, printInfo: printInfo)
        } catch {
            if let temp = temporaryFileURL {
                try? FileManager.default.removeItem(at: temp)
            }
            showPrintFailureAlert(reason: "Failed to open document for printing: \(error.localizedDescription)")
            return
        }

        let printOp = NSPrintOperation(view: printView, printInfo: printInfo)

        // Set job title so "Save as PDF" and print spools use the document's actual filename
        printOp.jobTitle = (doc.filePath as NSString).lastPathComponent

        printOp.showsPrintPanel = true
        printOp.showsProgressPanel = true
        // Must be false: NSView and MuPDFPrintView are @MainActor-isolated. Spawning a separate
        // background thread causes AppKit to invoke knowsPageRange(_:) and draw(_:) on a non-main
        // thread, which trips Swift Concurrency's executor assertion (_dispatch_assert_queue_fail).
        printOp.canSpawnSeparateThread = false
        
        // Expose native orientation and paper size options in the print dialog.
        printOp.printPanel.options.insert([
            .showsPaperSize,
            .showsOrientation
        ])
        printOp.printPanel.options.remove([
            .showsScaling,
            .showsPageSetupAccessory
        ])
        
        let hasMeasurements = self.hasMeasurementAnnotations
        if hasMeasurements {
            printView.scaleMode = 0
            printView.customScale = 1.0
        }
        let accessoryVC = PDFPrintAccessoryViewController(printOperation: printOp, printView: printView, hasMeasurements: hasMeasurements)
        printOp.printPanel.addAccessoryController(accessoryVC)
        
        let cleanup = {
            if let temp = temporaryFileURL {
                try? FileManager.default.removeItem(at: temp)
            }
        }
        
        let completionDelegate = PrintCompletionDelegate(onComplete: cleanup)
        objc_setAssociatedObject(printOp, &printCompletionDelegateKey, completionDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        if let window = currentWindow ?? NSApplication.shared.keyWindow {
            printOp.runModal(for: window, delegate: completionDelegate, didRun: #selector(PrintCompletionDelegate.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        } else {
            printOp.run()
            cleanup()
        }
    }

    private func showPrintFailureAlert(reason: String) {
        showErrorAlert(title: "Unable to Print Document", message: reason)
    }
    
    /// Adds an anchor for the current page location (or active selection if text is selected),
    /// switching the sidebar tab to Anchors to provide immediate visual feedback.
    public func addAnchorForCurrentPage() {
        if let target = buildSnapshotTargetFromSelection() {
            addSnapshotTarget(target)
            NotificationCenter.default.post(name: .focusAnchorsCommand, object: nil)
            return
        }
        guard let doc = document, doc.pageCount > 0 else { return }
        let p = currentPageIndex
        let bounds = doc.pageBounds[p]
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let target = buildSnapshotTarget(at: center, pageIndex: p)
        addSnapshotTarget(target)
        NotificationCenter.default.post(name: .focusAnchorsCommand, object: nil)
    }

    public func addSnapshotTarget(_ target: SnapshotTarget) {
        let isDuplicate = activeSnapshots.contains { existing in
            if existing.id == target.id { return true }
            if existing.targetPage == target.targetPage && !target.snippet.isEmpty && existing.snippet == target.snippet {
                return true
            }
            return false
        }
        guard !isDuplicate else { return }
        activeSnapshots.append(target)
        selectedSnapshotId = target.id
        saveReadingStateIfNeeded()
        if PDFViewerAppCoordinator.shared.activeViewModel === self || PDFViewerViewModel.active === self {
            PDFViewerAppCoordinator.shared.activeAnchors = activeSnapshots
        }
    }

    public func removeSnapshotTarget(_ target: SnapshotTarget) {
        if selectedSnapshotId == target.id {
            selectedSnapshotId = nil
        }
        activeSnapshots.removeAll(where: { $0.id == target.id })
        target.deleteThumbnailFile()
        saveReadingStateIfNeeded()
        if PDFViewerAppCoordinator.shared.activeViewModel === self || PDFViewerViewModel.active === self {
            PDFViewerAppCoordinator.shared.activeAnchors = activeSnapshots
        }
    }

    public func clearAllSnapshots() {
        selectedSnapshotId = nil
        for target in activeSnapshots {
            target.deleteThumbnailFile()
        }
        activeSnapshots.removeAll()
        saveReadingStateIfNeeded()
        if PDFViewerAppCoordinator.shared.activeViewModel === self || PDFViewerViewModel.active === self {
            PDFViewerAppCoordinator.shared.activeAnchors = activeSnapshots
        }
    }

    /// Checks all active snapshots for missing cached thumbnail images (e.g. when synced across devices
    /// via iCloud KVS without local disk cache files) and regenerates them in the background.
    public func regenerateMissingThumbnails() {
        guard let doc = document else { return }
        let currentDocPath = doc.filePath
        let snapshotsToRecreate = activeSnapshots.filter { snap in
            (snap.thumbnailFileName != nil || snap.label.hasPrefix("Area Anchor"))
            && snap.thumbnailImage == nil
            && snap.targetRect != nil
            && snap.targetPage >= 0
            && snap.targetPage < doc.pageCount
        }
        guard !snapshotsToRecreate.isEmpty else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            var didRegenerateAny = false
            for snap in snapshotsToRecreate {
                guard let rect = snap.targetRect, rect.width > 2 && rect.height > 2 else { continue }
                do {
                    let cgImage = try await self.renderActor.renderPageRect(
                        pageIndex: snap.targetPage,
                        rect: rect,
                        scale: 2.0
                    )
                    let rep = NSBitmapImageRep(cgImage: cgImage)
                    if let pngData = rep.representation(using: .png, properties: [:]) {
                        SnapshotTarget.writeThumbnailFile(id: snap.id, data: pngData)
                        didRegenerateAny = true
                    }
                } catch {
                    // Gracefully continue on error
                }
            }
            if didRegenerateAny {
                await MainActor.run {
                    guard let activeDoc = self.document, activeDoc.filePath == currentDocPath else { return }
                    var changed = false
                    for idx in self.activeSnapshots.indices {
                        let snap = self.activeSnapshots[idx]
                        if snap.thumbnailFileName == nil && SnapshotTarget.hasCachedThumbnail(fileName: "\(snap.id.uuidString).png") {
                            self.activeSnapshots[idx].thumbnailFileName = "\(snap.id.uuidString).png"
                            changed = true
                        }
                    }
                    if changed {
                        self.saveReadingStateIfNeeded()
                    }
                    self.objectWillChange.send()
                }
            }
        }
    }

    /// Persists this document's current page, zoom, and snapshots so they can be restored next
    /// time it's opened. Called on every document switch (see loadDocument), snapshot change, and
    /// externally on window close / app quit (see PDFViewerAppCoordinator.flushAllReadingStates).
    /// No-op for transient (snapshot/reference) windows or when no document is open.
    public func saveReadingStateIfNeeded() {
        guard !isTransientWindow, let doc = document else { return }
        ReadingStateManager.shared.updateState(
            for: doc.filePath,
            lastPageIndex: currentPageIndex,
            zoomScale: zoomScale,
            snapshots: activeSnapshots
        )
    }

    // MARK: - Document Properties & Font Inspection

    public func showDocumentProperties() {
        guard let doc = document else { return }
        self.documentInspectionReport = doc.generateInspectionReport(pageIndex: currentPageIndex)
        self.isShowingDocumentProperties = true
    }

    public func refreshInspectionReport() {
        guard let doc = document else { return }
        self.documentInspectionReport = doc.generateInspectionReport(pageIndex: currentPageIndex)
    }

    public func showSplitPDF() {
        guard document != nil else { return }
        self.isShowingSplitPDF = true
    }

    // MARK: - Agent Tab

    /// True when on-device answer synthesis (not just passage retrieval) can be attempted on this
    /// Mac — used by the UI to set expectations before a query is even run (e.g. "showing matching
    /// passages only" vs. an actual generated answer).
    public func isAgentSynthesisAvailable() -> Bool {
        agentConversationEngine.isSynthesisAvailable()
    }

    /// Invalidates the semantic index and cancels any in-flight indexing tasks.
    private func invalidateAgentIndex(deleteCache: Bool) {
        agentIndexingTask?.cancel()
        agentIndexingTask = nil
        agentIndexBuilder = nil
        agentChunks = []
        if agentIndexState != .idle {
            agentIndexState = .idle
        }
        if deleteCache, let path = document?.filePath {
            Task { await SemanticIndexStore.shared.remove(for: path) }
        }
    }

    /// Builds or loads from disk the semantic index for the current document if not already loaded.
    public func startAgentIndexingIfNeeded() {
        guard let doc = document, agentIndexState == .idle else { return }
        // Unsaved page edits or redactions live in the working copy; index that, not the file.
        let indexesWorkingCopy = workingCopyPath != nil
        let path = workingCopyPath ?? doc.filePath
        let password = currentDocumentPassword
        // The cache is plain JSON in Application Support: never write (or trust) one for a
        // password-protected document or a temporary working copy.
        let usesCache = password == nil && !indexesWorkingCopy

        agentIndexingTask?.cancel()
        agentIndexingTask = Task { [weak self] in
            guard let self else { return }

            // Guard resumptions so a cancelled task does not write stale index state.
            if password != nil {
                await SemanticIndexStore.shared.remove(for: path)
            }
            let cached = usesCache ? await SemanticIndexStore.shared.load(for: path) : nil
            guard !Task.isCancelled else { return }
            if let cached {
                self.agentChunks = cached.chunks
                self.agentIndexState = .ready
                return
            }

            let embedderAvailable = await self.agentEmbedder.isAvailable()
            guard !Task.isCancelled else { return }
            guard embedderAvailable else {
                self.agentIndexState = .unavailable("Semantic search isn't available on this Mac.")
                return
            }

            self.agentIndexState = .building(pagesDone: 0, totalPages: doc.pageCount)
            let builder = SemanticIndexBuilder()
            self.agentIndexBuilder = builder
            do {
                try await builder.openDocument(filePath: path, password: password)
            } catch {
                guard !Task.isCancelled else { return }
                self.agentIndexState = .unavailable("Couldn't open the document for indexing.")
                self.agentIndexBuilder = nil
                return
            }
            guard !Task.isCancelled else { return }

            let totalPages = await builder.pageCount()
            guard !Task.isCancelled else { return }
            var chunks: [EmbeddedChunk] = []
            var pagesDone = 0
            for await (pageIndex, text) in await builder.extractPageTexts() {
                if Task.isCancelled { return }
                for chunk in chunkPageText(text, pageIndex: pageIndex) {
                    if let vector = await self.agentEmbedder.embed(chunk.text) {
                        chunks.append(EmbeddedChunk(chunk: chunk, vector: vector))
                    }
                }
                pagesDone += 1
                // Updating on every page would mean thousands of @Published writes for a long
                // document; every 10 pages keeps the progress bar smooth without that overhead.
                if pagesDone % 10 == 0 || pagesDone == totalPages {
                    self.agentIndexState = .building(pagesDone: pagesDone, totalPages: totalPages)
                }
            }
            guard !Task.isCancelled else { return }

            self.agentIndexBuilder = nil
            guard !chunks.isEmpty else {
                self.agentIndexState = .unavailable("This document has no text the Agent can search.")
                return
            }
            self.agentChunks = chunks
            self.agentIndexState = .ready

            guard usesCache else { return }
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let modDate = (attrs?[.modificationDate] as? Date) ?? Date()
            await SemanticIndexStore.shared.save(
                DocumentSemanticIndex(sourcePath: path, sourceModifiedAt: modDate, chunks: chunks)
            )
        }
    }

    /// Resets an `.unavailable` index state and tries again — surfaced as a "Retry" button, since
    /// a transient failure (e.g. a document that failed to open for indexing) shouldn't need a
    /// document switch to recover from.
    public func retryAgentIndexing() {
        agentIndexState = .idle
        startAgentIndexingIfNeeded()
    }

    /// Clears the visible conversation and resets the conversation session.
    public func startNewAgentConversation() {
        agentConversation = []
        agentConversationEngine.reset()
    }

    /// Runs `agentQuestion` against the semantic index, appending a new turn to `agentConversation`.
    public func askAgentQuestion() {
        let question = agentQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, agentIndexState == .ready, !agentChunks.isEmpty else { return }

        agentQuestion = ""
        agentIsAnswering = true
        // Capture previous question for follow-up query folding.
        let previousQuestion = agentConversation.last?.question
        let turnId = UUID()
        agentConversation.append(AgentTurn(id: turnId, question: question, isStreaming: true))

        let chunksSnapshot = agentChunks
        Task { [weak self] in
            guard let self else { return }
            let activeProvider = self.agentConversationEngine.activeSynthesisProvider()

            // For small documents under context limits, pass full document prose directly.
            let totalDocChars = chunksSnapshot.reduce(0) { $0 + $1.chunk.text.count }
            let estimatedTokens = totalDocChars / 4
            let isFullDocEligible = activeProvider == .privateCloudCompute && estimatedTokens <= DocumentAgentConversation.fullDocumentTokenThreshold

            let passages: [AgentPassage]
            let isFullDoc: Bool

            if isFullDocEligible {
                var pageMap: [Int: [String]] = [:]
                for c in chunksSnapshot {
                    pageMap[c.chunk.pageIndex, default: []].append(c.chunk.text)
                }
                let sortedPages = pageMap.keys.sorted()
                passages = sortedPages.map { pageIdx in
                    AgentPassage(pageIndex: pageIdx, text: pageMap[pageIdx]!.joined(separator: "\n\n"), score: 1.0)
                }
                isFullDoc = true
            } else {
                // Fold previous question into query for anaphoric follow-ups.
                let retrievalQuery: String
                if let prev = previousQuestion, self.shouldFoldPreviousQuestion(question) {
                    retrievalQuery = "\(prev)\n\(question)"
                } else {
                    retrievalQuery = question
                }
                guard let queryVector = await self.agentEmbedder.embed(retrievalQuery) else {
                    self.finishAgentTurn(id: turnId, text: "", errorMessage: "Couldn't process this question.")
                    return
                }

                // Hybrid retrieval combining embedding similarity and lexical relevance.
                let embeddingScores = chunksSnapshot.map { cosineSimilarity(queryVector, $0.vector) }
                let lexicalScores = chunksSnapshot.map { lexicalRelevanceScore(query: question, text: $0.chunk.text) }

                let pools = self.agentConversationEngine.recommendedCandidatePoolSizes()
                let topByEmbedding = chunksSnapshot.indices.sorted { embeddingScores[$0] > embeddingScores[$1] }.prefix(pools.embedding)
                let topByLexical = chunksSnapshot.indices
                    .filter { lexicalScores[$0] > 0 }
                    .sorted { lexicalScores[$0] > lexicalScores[$1] }
                    .prefix(pools.lexical)
                let candidateIndices = Set(topByEmbedding).union(topByLexical)
                let passageBudget = self.agentConversationEngine.recommendedPassageCount(onDeviceDefault: Self.maxPassagesForSynthesis)
                let ranked = candidateIndices
                    .map { i in (embedded: chunksSnapshot[i], score: hybridRelevanceScore(embeddingScore: embeddingScores[i], lexicalScore: lexicalScores[i])) }
                    .sorted { $0.score > $1.score }
                    .prefix(passageBudget)

                // Passages retain their full, natural chunk content with zero truncation
                passages = ranked.map { item in
                    AgentPassage(pageIndex: item.embedded.chunk.pageIndex, text: item.embedded.chunk.text, score: item.score)
                }
                isFullDoc = false
            }

            let initialProvider = self.agentConversationEngine.activeSynthesisProvider()
            self.updateAgentTurn(id: turnId) {
                $0.passages = passages
                $0.providerUsed = initialProvider
            }
            // Without on-device generation the passages are the answer — not an error.
            guard initialProvider != nil else {
                self.finishAgentTurn(id: turnId, text: "")
                return
            }

            let result = await self.agentConversationEngine.streamAnswer(
                question: question,
                passages: passages,
                isFullDocument: isFullDoc
            ) { [weak self] partial in
                self?.updateAgentTurn(id: turnId) { $0.answerText = partial }
            }
            self.finishAgentTurn(
                id: turnId,
                text: result.text ?? "",
                provider: result.providerUsed,
                statusNote: result.statusNote,
                errorMessage: result.errorMessage
            )
        }
    }

    /// Determines whether the question is an anaphoric follow-up referring to previous context.
    public func shouldFoldPreviousQuestion(_ question: String) -> Bool {
        let q = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let words = q.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.count <= 4 { return true }
        let followUpTriggers: Set<String> = [
            "it", "this", "that", "these", "those", "they", "them", "he", "she",
            "more", "why", "how", "details", "explain", "elaborate", "again", "also"
        ]
        return words.contains(where: { followUpTriggers.contains($0) })
    }

    private func updateAgentTurn(id: UUID, _ mutate: (inout AgentTurn) -> Void) {
        guard let index = agentConversation.firstIndex(where: { $0.id == id }) else { return }
        mutate(&agentConversation[index])
    }

    private func finishAgentTurn(
        id: UUID,
        text: String,
        provider: AgentSynthesisProvider? = nil,
        statusNote: String? = nil,
        errorMessage: String? = nil
    ) {
        updateAgentTurn(id: id) {
            $0.answerText = text
            $0.isStreaming = false
            if let provider {
                $0.providerUsed = provider
            }
            $0.statusNote = statusNote
            $0.errorMessage = errorMessage
        }
        agentIsAnswering = false
    }
}

extension String {
    /// Truncates string to at most `maxLength` characters without cutting off in the middle of a word.
    /// If cutting at `maxLength` falls inside a word, that partial word is suppressed.
    public func truncatedAtWordBoundary(maxLength: Int) -> String {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }

        let cutoffIndex = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        let slice = trimmed[..<cutoffIndex]

        // If character at cutoff is whitespace, the word ended cleanly right before cutoff.
        if trimmed[cutoffIndex].isWhitespace {
            return String(slice).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-")))
        }

        // Slice ends in the middle of a word. Find the last whitespace to drop the partial word.
        if let lastSpace = slice.lastIndex(where: { $0.isWhitespace }) {
            let clean = slice[..<lastSpace].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-")))
            if !clean.isEmpty {
                return String(clean)
            }
        }

        // Fallback for single long word: truncate directly
        return String(slice)
    }
}

/// NSWindowDelegate helper to intercept close requests on edited documents and prompt to save
@MainActor
public final class PDFViewerWindowDelegate: NSObject, NSWindowDelegate {
    public weak var viewModel: PDFViewerViewModel?
    
    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
        super.init()
    }
    
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let vm = viewModel else { return true }
        return vm.promptSaveBeforeClosingIfNeeded()
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            TabBarAppearanceHelper.refreshTabs(for: window)
        }
    }

    public func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            TabBarAppearanceHelper.refreshTabs(for: window)
        }
    }

    public func windowDidBecomeMain(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            TabBarAppearanceHelper.refreshTabs(for: window)
        }
    }

    public func windowDidChangeScreen(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            viewModel?.updateDisplayScale(for: window)
            TabBarAppearanceHelper.refreshTabs(for: window)
        }
    }
}

private nonisolated(unsafe) var printCompletionDelegateKey: UInt8 = 0

@MainActor
private final class PrintCompletionDelegate: NSObject {
    private var onComplete: (() -> Void)?
    
    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        super.init()
    }
    
    @objc func printOperationDidRun(_ printOperation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if success {
            NSPrintInfo.shared = printOperation.printInfo
        }
        onComplete?()
        onComplete = nil
    }
}

/// Print panel accessory view controller providing controls for Auto Rotate and Scaling.
@MainActor
final class PDFPrintAccessoryViewController: NSViewController, NSPrintPanelAccessorizing {
    private weak var printOperation: NSPrintOperation?
    private weak var printView: MuPDFPrintView?
    private let hasMeasurements: Bool
    
    @objc dynamic var previewAutoRotate: Bool = true
    @objc dynamic var previewScale: Double = 1.0
    
    private var autoRotateCheckbox: NSButton!
    private var scaleToFitRadio: NSButton!
    private var scaleCustomRadio: NSButton!
    private var scaleField: NSTextField!
    private var scaleStepper: NSStepper!
    
    private var activePrintInfo: NSPrintInfo? {
        return printOperation?.printInfo
    }
    
    init(printOperation: NSPrintOperation, printView: MuPDFPrintView, hasMeasurements: Bool = false) {
        self.printOperation = printOperation
        self.printView = printView
        self.hasMeasurements = hasMeasurements
        super.init(nibName: nil, bundle: nil)
        self.title = "PDF Options"
        self.previewAutoRotate = printView.autoRotate
        self.previewScale = 1.0
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        // Auto Rotate (left side)
        autoRotateCheckbox = NSButton(checkboxWithTitle: "Auto Rotate", target: self, action: #selector(autoRotateChanged(_:)))
        autoRotateCheckbox.state = printView?.autoRotate == false ? .off : .on
        
        // Scale controls (right side)
        scaleToFitRadio = NSButton(radioButtonWithTitle: "Scale to Fit", target: self, action: #selector(scaleModeChanged(_:)))
        scaleToFitRadio.state = hasMeasurements ? .off : .on
        
        scaleCustomRadio = NSButton(radioButtonWithTitle: "Scale:", target: self, action: #selector(scaleModeChanged(_:)))
        scaleCustomRadio.state = hasMeasurements ? .on : .off
        
        scaleField = NSTextField(string: "100")
        scaleField.alignment = .right
        scaleField.target = self
        scaleField.action = #selector(customScaleChanged(_:))
        scaleField.isEnabled = hasMeasurements
        scaleField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        
        let pctLabel = NSTextField(labelWithString: "%")
        
        scaleStepper = NSStepper()
        scaleStepper.minValue = 10
        scaleStepper.maxValue = 400
        scaleStepper.increment = 5
        scaleStepper.integerValue = 100
        scaleStepper.target = self
        scaleStepper.action = #selector(stepperChanged(_:))
        scaleStepper.isEnabled = hasMeasurements
        
        let customScaleRow = NSStackView(views: [scaleCustomRadio, scaleField, pctLabel, scaleStepper])
        customScaleRow.orientation = .horizontal
        customScaleRow.spacing = 4
        customScaleRow.alignment = .centerY
        
        let scaleStack = NSStackView(views: [scaleToFitRadio, customScaleRow])
        scaleStack.orientation = .vertical
        scaleStack.alignment = .leading
        scaleStack.spacing = 6
        
        // Horizontal main stack: Auto Rotate on the left, Scale options to the right
        let mainStack = NSStackView(views: [autoRotateCheckbox, scaleStack])
        mainStack.orientation = .horizontal
        mainStack.alignment = .top
        mainStack.spacing = 32
        
        let outerStack = NSStackView()
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 10
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        outerStack.addArrangedSubview(mainStack)
        
        if hasMeasurements {
            let noteContainer = NSView()
            noteContainer.wantsLayer = true
            noteContainer.layer?.cornerRadius = 6
            noteContainer.layer?.borderWidth = 1
            noteContainer.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.4).cgColor
            noteContainer.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.08).cgColor
            
            let noteIcon = NSImageView()
            if let rulerImg = NSImage(systemSymbolName: "ruler", accessibilityDescription: "Measurements") {
                noteIcon.image = rulerImg
            } else {
                noteIcon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Information")
            }
            noteIcon.contentTintColor = .systemOrange
            noteIcon.setContentHuggingPriority(.required, for: .horizontal)
            
            let noteLabel = NSTextField(wrappingLabelWithString: "Document contains calibrated measurements. Scale defaults to 100% (Actual Size). Please confirm paper type, size, and zoom to preserve calibrated scale.")
            noteLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            noteLabel.textColor = .labelColor
            
            let noteStack = NSStackView(views: [noteIcon, noteLabel])
            noteStack.orientation = .horizontal
            noteStack.alignment = .centerY
            noteStack.spacing = 8
            noteStack.translatesAutoresizingMaskIntoConstraints = false
            
            noteContainer.addSubview(noteStack)
            NSLayoutConstraint.activate([
                noteStack.leadingAnchor.constraint(equalTo: noteContainer.leadingAnchor, constant: 10),
                noteStack.trailingAnchor.constraint(equalTo: noteContainer.trailingAnchor, constant: -10),
                noteStack.topAnchor.constraint(equalTo: noteContainer.topAnchor, constant: 6),
                noteStack.bottomAnchor.constraint(equalTo: noteContainer.bottomAnchor, constant: -6),
                noteContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 440)
            ])
            outerStack.addArrangedSubview(noteContainer)
        }
        
        container.addSubview(outerStack)
        
        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            outerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            outerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            outerStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16)
        ])
        
        self.view = container
    }
    
    @objc func keyPathsForValuesAffectingPreview() -> Set<String> {
        return ["previewScale", "previewAutoRotate"]
    }
    
    @objc private func autoRotateChanged(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        previewAutoRotate = enabled
        printView?.autoRotate = enabled
        printView?.needsDisplay = true
    }
    
    @objc private func scaleModeChanged(_ sender: NSButton) {
        if sender === scaleToFitRadio {
            scaleToFitRadio.state = .on
            scaleCustomRadio.state = .off
            scaleField.isEnabled = false
            scaleStepper.isEnabled = false
            printView?.scaleMode = 1
            previewScale = 1.0
        } else {
            scaleToFitRadio.state = .off
            scaleCustomRadio.state = .on
            scaleField.isEnabled = true
            scaleStepper.isEnabled = true
            applyCustomScale()
        }
        printView?.needsDisplay = true
    }
    
    @objc private func stepperChanged(_ sender: NSStepper) {
        if scaleCustomRadio.state != .on {
            scaleToFitRadio.state = .off
            scaleCustomRadio.state = .on
            scaleField.isEnabled = true
            scaleStepper.isEnabled = true
        }
        scaleField.integerValue = sender.integerValue
        applyCustomScale()
    }
    
    @objc private func customScaleChanged(_ sender: NSTextField) {
        if scaleCustomRadio.state != .on {
            scaleToFitRadio.state = .off
            scaleCustomRadio.state = .on
            scaleField.isEnabled = true
            scaleStepper.isEnabled = true
        }
        let val = max(10, min(400, sender.integerValue))
        scaleField.integerValue = val
        scaleStepper.integerValue = val
        applyCustomScale()
    }
    
    private func applyCustomScale() {
        let pct = max(10, min(400, scaleField.integerValue))
        let factor = CGFloat(pct) / 100.0
        printView?.scaleMode = 0
        printView?.customScale = factor
        previewScale = Double(factor)
        printView?.needsDisplay = true
    }
    
    nonisolated func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        return MainActor.assumeIsolated {
            var items: [[NSPrintPanel.AccessorySummaryKey: String]] = []
            let autoRot = (autoRotateCheckbox?.state == .on) ? "Yes" : "No"
            items.append([.itemName: "Auto Rotate", .itemDescription: autoRot])
            let scaleDesc = (scaleToFitRadio?.state == .on) ? "Scale to Fit" : "\(scaleField?.stringValue ?? "100")%"
            items.append([.itemName: "Scale", .itemDescription: scaleDesc])
            if hasMeasurements {
                items.append([.itemName: "Measurements", .itemDescription: "100% Actual Size (Calibrated)"])
            }
            return items
        }
    }
}


