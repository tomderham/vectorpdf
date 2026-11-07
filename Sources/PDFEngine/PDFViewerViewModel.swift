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
    @Published public internal(set) var document: PDFDocumentCore?
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
    var isCloudDownloadCancelled = false

    // Continuity / Handoff
    var readingUserActivity: NSUserActivity?

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
    var isRenderActorReady = false
    private var pagesAwaitingRenderActor: Set<Int> = []
    /// The zoom each of `renderedPages` was rendered at. After a zoom a page keeps its old
    /// bitmap, stretched to its new size, until the sharp one is ready, rather than going blank.
    private var renderedPageZooms: [Int: CGFloat] = [:]
    /// True while a pinch is changing the zoom with every event: pages render once it ends,
    /// not at each step.
    public var isLiveZooming = false
    @Published public var documentTitle: String = "VectorPDF"

    /// Whole-document display-only rotation in 90-degree increments.
    @Published public private(set) var viewRotationDegrees: Int = 0
    /// Per-page Y offsets and total content height adjusted for rotation and two-page mode.
    @Published public private(set) var effectivePageYOffsets: [CGFloat] = []
    @Published public private(set) var effectiveTotalHeight: CGFloat = 0

    var isRotatedSideways: Bool { viewRotationDegrees == 90 || viewRotationDegrees == 270 }

    /// Displays pages in side-by-side spreads when true.
    @Published public private(set) var isTwoPageMode: Bool = false

    /// The sidebar tab a document opens on (see `sidebarOpening`), read by the window when a
    /// document has opened.
    public internal(set) var sidebarOpeningTab: SidebarOpeningTab = .contents

    /// The active viewport size of the PDF scroll view, tracked for accurate zoom-to-fit calculations.
    public var currentViewportSize: CGSize?

    /// True for an EPUB, XPS, CBZ or FB2 document, which MuPDF reads but can't save. It keeps
    /// text selection, links and search: only the tools that write to the file are unavailable (markup, measurement, redaction, page
    /// edits, saving). Also true in a Compare Documents pane, which is for reading only.
    public var isReadOnlyDocument: Bool { document?.isPDF == false || isComparePane }

    /// True for one of the two panes of a Compare Documents tab (see `DocumentCompareSession`):
    /// read-only, and not the window's document, so loading doesn't set the window's title or
    /// add to Open Recent. Implies `isTransientWindow`.
    public internal(set) var isComparePane = false {
        didSet { if isComparePane { isTransientWindow = true } }
    }

    /// What a Compare Documents pane highlights: the words that differ, a marker where the other
    /// document has text this one doesn't, and the change chosen with Next/Previous Change.
    @Published public internal(set) var compareMarks = CompareMarks()

    /// The comparison when this is a Compare Documents tab, whose document is the revision.
    public internal(set) var compareSession: DocumentCompareSession?

    /// The comparison this document is one side of, in either pane of a Compare Documents tab:
    /// for menu commands, which go to whichever pane was clicked last.
    public internal(set) weak var compareContext: DocumentCompareSession?

    /// The scroll view showing this document, once it's on screen.
    public internal(set) weak var hostScrollView: NSScrollView?

    /// True from when a document starts opening in this window until it's open or has failed. The
    /// window has no document yet, but it isn't an empty Start window.
    public internal(set) var isLoadingDocument = false

    public func rotateClockwise() {
        viewRotationDegrees = (viewRotationDegrees + 90) % 360
        leaveTwoPageMode()
        recomputeEffectiveLayout()
    }

    public func rotateCounterclockwise() {
        viewRotationDegrees = (viewRotationDegrees + 270) % 360
        leaveTwoPageMode()
        recomputeEffectiveLayout()
    }

    /// Chooses a markup or measurement tool, or puts it down again, back to Select, when it's
    /// already chosen: clicking the active tool's button works as Escape does.
    public func toggleTool(_ mode: CanvasMode) {
        if canvasMode == mode {
            canvasMode = .select
            pendingSignatureData = nil
        } else {
            canvasMode = mode
        }
    }

    /// Whether the sidebar showed before Two-Page Mode hid it, to bring it back after.
    private(set) var sidebarVisibleBeforeTwoPage: Bool?

    /// Ends Two-Page Mode, if it's on, bringing the sidebar back as it was.
    private func leaveTwoPageMode() {
        guard isTwoPageMode else { return }
        isTwoPageMode = false
        if let wasVisible = sidebarVisibleBeforeTwoPage {
            isSidebarVisible = wasVisible
        }
        sidebarVisibleBeforeTwoPage = nil
    }

    public func toggleTwoPageMode() {
        let savedPage = currentPageIndex
        if isTwoPageMode {
            leaveTwoPageMode()
        } else {
            // A spread needs the window's width; the sidebar comes back after.
            isTwoPageMode = true
            sidebarVisibleBeforeTwoPage = isSidebarVisible
            isSidebarVisible = false
            viewRotationDegrees = 0
        }
        recomputeEffectiveLayout()
        currentPageIndex = savedPage
        if isTwoPageMode {
            zoomToFitPage()
        }
    }

    func recomputeEffectiveLayout() {
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
            if isMarkupBarVisible && isReadOnlyDocument {
                isMarkupBarVisible = false
            } else if isMarkupBarVisible {
                isMeasurementBarVisible = false
                isRedactionBarVisible = false
            } else {
                if canvasMode == .draw || canvasMode == .text || canvasMode == .callout || canvasMode == .stamp || canvasMode == .eraser || canvasMode == .note || canvasMode == .shape {
                    canvasMode = .select
                }
                pendingSignatureData = nil
            }
        }
    }
    @Published public var canvasMode: CanvasMode = .select {
        didSet {
            // Every other mode adds, changes or removes something in the file.
            if canvasMode != .select && isReadOnlyDocument { canvasMode = .select }
        }
    }
    @Published public var selectedAnnotationColor: AnnotationColor = .yellow
    @Published public var drawStrokeWidth: CGFloat = 2.5
    @Published public var selectedFontSize: CGFloat = 13.0
    @Published public var pendingSignatureData: Data? = nil
    @Published public var selectedLineEnding: PDFLineEnding = .closedArrow
    /// The PDF's largest standard arcs, for clouds that look like clouds.
    @Published public var selectedCloudArcSize: PDFCloudArcSize = .large
    @Published public var selectedShape: PDFShapeKind = .rectangle
    /// What the Shapes tool's lines end with: None for a plain line.
    @Published public var selectedShapeLineEnding: PDFLineEnding = .openArrow
    @Published public var isShowingAnnotationsTable: Bool = false
    /// The annotation being replaced, between beginReplacingAnnotation and finishReplacingAnnotation.
    var annotationBeingReplaced: PDFAnnotation?
    /// What replaced `annotationBeingReplaced`, once it's written.
    var annotationReplacement: PDFAnnotation?
    /// Undo and Redo for annotations added, changed and removed this session. The window hands
    /// it to Edit > Undo (see `PDFViewerWindowDelegate`).
    public let undoManager = UndoManager()
    /// Bumped when annotations or their replies change; see `noteAnnotationsChanged`.
    @Published public internal(set) var annotationChange = AnnotationChange()
    /// Every page's annotations with their replies, for the Comments sidebar, which only shows
    /// its tab when there are some. Nil while the whole document is being read.
    @Published public internal(set) var annotationThreadsByPage: [Int: [PDFAnnotationThread]]? {
        didSet {
            if let threads = annotationThreadsByPage { hasAnnotationThreads = !threads.isEmpty }
        }
    }
    /// Whether the last read found any annotations; kept while the document is read again, so
    /// the Comments tab doesn't disappear meanwhile.
    @Published public private(set) var hasAnnotationThreads = false
    /// The document's layers, for the Layers sidebar, which only shows its tab when there are some.
    @Published public internal(set) var layers: [PDFLayer] = []
    /// The document's embedded files, for the Attachments tab, which shows only when there are some.
    @Published public internal(set) var attachments: [PDFAttachment] = []
    /// Bumped when layers are shown or hidden, so pictures drawn before that are thrown away.
    var layerGeneration = 0
    /// Whether each layer is shown, by object number, for annotations on them.
    @Published public internal(set) var layerVisibility: [Int: Bool] = [:]
    /// The layer, by object number, that annotations made from now on go on; nil for none.
    @Published public internal(set) var annotationLayer: Int?
    /// The ways the document offers its layers to be shown, default first; empty when it offers
    /// only its default, so the Layers tab offers no choice.
    @Published public internal(set) var layerConfigurations: [PDFLayerConfiguration] = []
    /// The one chosen (`PDFLayerConfiguration.id`), -1 for the default.
    @Published public internal(set) var layerConfiguration = -1
    /// Layers have been shown or hidden since it was chosen.
    @Published public internal(set) var isLayerConfigurationChanged = false
    /// How it showed the layers, by object number, to tell whether they've been changed since.
    var layerConfigurationVisibility: [Int: Bool] = [:]
    /// While Undo puts an annotation back, the layer it was on (see `restoreAnnotation`).
    var restoringAnnotationLayer: Int??
    var annotationThreadsTask: Task<Void, Never>?
    /// The annotation the Comments sidebar last asked to scroll to.
    @Published public internal(set) var annotationReveal: AnnotationReveal?
    /// The outline entry's heading last asked to be shown (see `jumpToOutlineEntry`).
    @Published public internal(set) var outlineJump: OutlineJump?
    /// The place a SyncTeX forward search last asked to be shown and highlighted (see
    /// `showSyncTeXLocation`).
    @Published public internal(set) var syncTeXReveal: SyncTeXReveal?
    /// Whether the document has a SyncTeX file beside it, so ⇧⌘-click and Show in Editor work.
    @Published public internal(set) var hasSyncTeX = false
    /// The document's parsed SyncTeX file, made when first needed and again when TeX rewrites it.
    var syncTeXIndex: SyncTeXIndex?
    /// Set while `handleExternalFileChange` reloads the file, so a failure doesn't show an alert.
    var isReloadingAfterExternalChange = false
    /// The file's modification date when it was loaded, to tell a build has replaced it since.
    var loadedFileModificationDate: Date?
    /// Annotations deleted this session that the renderer's copy of the file may still hold, by
    /// page and object number, so it leaves them out.
    var removedAnnotationNumbers: [Int: Set<Int>] = [:]
    /// What the renderer was last told to leave out (see `syncHiddenAnnotations`).
    var hiddenAnnotationNumbers: [Int: Set<Int>] = [:]
    private var pageAnnotationsCancellable: AnyCancellable?

    // Engineering Measurement & Takeoff
    @Published public var isMeasurementBarVisible: Bool = false {
        didSet {
            if isMeasurementBarVisible && isReadOnlyDocument {
                isMeasurementBarVisible = false
            } else if isMeasurementBarVisible {
                isMarkupBarVisible = false
                isRedactionBarVisible = false
                if canvasMode == .select || canvasMode == .draw || canvasMode == .text || canvasMode == .callout || canvasMode == .redact || canvasMode == .stamp || canvasMode == .note || canvasMode == .shape {
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
    var navigationHistory: [Int] = []
    var navigationHistoryIndex: Int = -1
    private var isNavigatingHistory: Bool = false

    // Thumbnail Cache for Outline/Thumbnails View
    @Published public var thumbnailImages: [Int: NSImage] = [:]
    /// Changed whenever pages are edited, which can take attachments on them with them.
    @Published public var thumbnailVersion: UUID = UUID() {
        didSet { refreshAttachments() }
    }
    @Published public var selectedThumbnailPageIndices: Set<Int> = [0]
    @Published public var draggedThumbnailPageIndex: Int? = nil
    @Published public var draggedThumbnailPageIndices: Set<Int> = []
    @Published public var activeThumbnailDropSlot: Int? = nil
    var selectionAnchorPageIndex: Int = 0
    var dragWatchdogTimer: Timer?
    var dragEventMonitor: Any?
    var thumbnailsLoading: Set<Int> = []
    
    // Search State
    @Published public var searchQuery: String = ""
    @Published public var searchOptions: SearchOptions = SearchOptions()
    @Published public var searchResults: [SearchResult] = []
    @Published public internal(set) var searchResultsByPage: [Int: [SearchResult]] = [:]
    @Published public var isSearching: Bool = false
    @Published public var activeSearchMatchIndex: Int = 0
    @Published public var activeSearchMatchId: UUID? = nil
    @Published public var searchScrollRevision: Int = 0
    @Published public var activeScrollTargetId: String? = nil
    @Published public var searchJumpToken: Int = 0
    @Published public var hasNavigatedToActiveSearchMatch: Bool = false
    public var autoNavigateOnSearchResults: Bool = false
    /// This document's recent searches, most recent first (see recordRecentSearch).
    @Published public internal(set) var recentSearches: [String] = []
    
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
    @Published public var ocrResults: [Int: PDFOCRPageResult] = [:] {
        didSet { ocrTextPages.removeAll() }
    }
    /// `ocrResults` as selection reads them. Selecting runs on every mouse move while dragging.
    var ocrTextPages: [Int: StructuredPage] = [:]
    @Published public var isRunningOCR: Bool = false
    var activeOCRCount: Int = 0 {
        didSet {
            let running = activeOCRCount > 0
            if isRunningOCR != running {
                isRunningOCR = running
            }
        }
    }
    @Published public var detectedScannedPages: Set<Int> = []
    /// Incremented when page indices change to invalidate in-flight OCR requests.
    var ocrGeneration = 0
    
    // MARK: - Edit & Redact Toolbar State
    @Published public var isRedactionBarVisible: Bool = false {
        didSet {
            if isRedactionBarVisible && isReadOnlyDocument {
                isRedactionBarVisible = false
            } else if isRedactionBarVisible {
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

    var redactionSearchTask: Task<Void, Never>?
    /// Whether a markup, measurement or redaction toolbar is showing under the title bar.
    var isDocumentToolbarVisible: Bool { isMarkupBarVisible || isMeasurementBarVisible || isRedactionBarVisible }
    /// The document whose redaction alert has been accepted; it's shown once per open document.
    weak var redactionNoticeDocument: PDFDocumentCore?

    // Agent Tab: semantic search (always available on-device) plus optional on-device
    // synthesis (Apple Intelligence-gated) over the currently open document only — see
    // DocumentAgentService.swift and SemanticSearch.swift.
    @Published public var agentQuestion: String = ""
    @Published public var agentIndexState: AgentIndexState = .idle
    @Published public var agentIsAnswering: Bool = false
    @Published public var agentConversation: [AgentTurn] = []

    let agentEmbedder = TextEmbedder()
    let agentConversationEngine = DocumentAgentConversation()
    var agentIndexBuilder: SemanticIndexBuilder?
    var agentChunks: [EmbeddedChunk] = []
    var agentIndexingTask: Task<Void, Never>?
    // Retrieval pool sizes for Agent questions.
    private static let embeddingCandidatePoolSize = 24
    private static let lexicalCandidatePoolSize = 10
    /// Candidates offered to the on-device model, which keeps as many as fit its context.
    static let onDeviceCandidatePassages = 24
    /// Passages listed as the result when no model is available to answer.
    static let passagesShownWithoutSynthesis = 6
    // Reused so the Agent tab's lazily-built index doesn't need to re-prompt for a password
    // already entered once to open the document (see promptForPasswordAndRetry).
    var currentDocumentPassword: String?
    // Watches the open file for external changes and reloads it.
    var fileChangeWatcher: FileChangeWatcher?
    var workingCopyPath: String?

    /// A fresh path for a working copy, in the temporary folder. PRIVACY.md documents the name, so
    /// people can find copies left behind by a crash.
    static func newWorkingCopyPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("VectorPDF-working-\(UUID().uuidString).pdf").path
    }

    func cleanupWorkingCopy() {
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
    let renderActor = PDFRenderActor(cacheCapacity: 12)
    let searchActor = PDFSearchActor()
    var searchTask: Task<Void, Never>?
    var debouncedWidgetTasks: [String: Task<Void, Never>] = [:]
    var pendingWidgetValues: [String: (pageIndex: Int, widgetIndex: Int, value: String)] = [:]
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

    @Published public var translationTargetText: String? = nil
    @Published public var isPresentingTranslation: Bool = false
    var cachedOutlineDestinationKeys: (document: ObjectIdentifier, keys: Set<String>)?

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

        // @Published sends before the change, with the new value.
        pageAnnotationsCancellable = $pageAnnotations
            .sink { [weak self] annotations in
                MainActor.assumeIsolated { self?.syncHiddenAnnotations(annotations) }
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
                    if !self.isTransientWindow {
                        self.recentSearches = saved.recentSearches ?? []
                    }
                }
            }
        }

        // Another tab or window on the same document changed its recent searches.
        NotificationCenter.default.addObserver(
            forName: ReadingStateManager.recentSearchesDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let sender = (note.object as AnyObject?).map(ObjectIdentifier.init)
            let key = note.userInfo?["canonicalKey"] as? String
            MainActor.assumeIsolated {
                guard let self = self, sender != ObjectIdentifier(self), !self.isTransientWindow,
                      let doc = self.document, CloudStorageHelper.canonicalKey(for: doc.filePath) == key else { return }
                self.recentSearches = ReadingStateManager.shared.state(for: doc.filePath)?.recentSearches ?? []
            }
        }
    }

    nonisolated static func modificationDate(ofFileAt path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    public func loadDocument(from path: String, password: String? = nil) async {
        if isDocumentEdited && document?.filePath != path {
            let canProceed = promptSaveBeforeClosingIfNeeded()
            guard canProceed else { return }
        }

        isLoadingDocument = true
        defer { isLoadingDocument = false }

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

            // Reloading the same file (it changed on disk, as after a LaTeX build) keeps the view
            // as the user had it, rather than as for a newly opened document.
            let isReload = document?.filePath == actualPath
            let keptLayout = (rotation: viewRotationDegrees, isTwoPage: isTwoPageMode,
                              sidebarBeforeTwoPage: sidebarVisibleBeforeTwoPage, isSidebarVisible: isSidebarVisible)
            let modified = Self.modificationDate(ofFileAt: actualPath)
            let doc = try await Task.detached(priority: .userInitiated) {
                try PDFDocumentCore(filePath: actualPath, password: password)
            }.value
            self.loadedFileModificationDate = modified
            self.syncTeXIndex = nil
            let hasSyncTeX = !isComparePane && SyncTeXFile.find(forPDF: doc.filePath) != nil
            if self.hasSyncTeX != hasSyncTeX { self.hasSyncTeX = hasSyncTeX }
            // Park render requests until renderActor has opened the new file.
            isRenderActorReady = false
            pagesAwaitingRenderActor.removeAll()
            pagesCurrentlyRendering.removeAll()
            self.document = doc
            self.layers = doc.layers()
            self.attachments = doc.attachments()
            self.layerVisibility = doc.layerVisibility()
            self.layerConfigurations = doc.layerConfigurations()
            self.layerConfiguration = doc.layerConfiguration
            self.layerConfigurationVisibility = self.layerVisibility
            self.isLayerConfigurationChanged = false
            self.annotationLayer = nil
            self.layerGeneration += 1
            self.currentDocumentPassword = password
            let fileURL = URL(fileURLWithPath: actualPath)
            let fileName = fileURL.lastPathComponent
            self.documentTitle = fileName
            PDFViewerAppCoordinator.shared.registerActive(self)
            if !isComparePane {
                PDFViewerAppCoordinator.shared.noteRecentDocument(fileURL)
            }

            // Set representedURL and window title on this tab's window
            if !isComparePane, let window = currentWindow ?? NSApplication.shared.keyWindow {
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
            self.forgetAnnotationEdits()
            if self.isReadOnlyDocument {
                // Left open from a PDF this window showed before.
                self.isMarkupBarVisible = false
                self.isMeasurementBarVisible = false
                self.isRedactionBarVisible = false
                self.canvasMode = .select
            }
            self.noteAnnotationsChanged(onPage: nil)
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
            self.viewRotationDegrees = isReload ? keptLayout.rotation : 0
            self.isTwoPageMode = isReload && keptLayout.isTwoPage
            self.sidebarVisibleBeforeTwoPage = isReload ? keptLayout.sidebarBeforeTwoPage : nil
            self.recomputeEffectiveLayout()
            // The sidebar as the user last left it for this document, or as suits the document.
            let isShort = doc.pageCount <= Self.shortDocumentPageCount
            let opening = Self.sidebarOpening(
                pageCount: doc.pageCount,
                hasOutline: !doc.outline.isEmpty,
                hasLayers: !self.layers.isEmpty,
                // Only a short document is asked: a long one opens with the sidebar anyway.
                hasAnnotations: isShort && (0..<doc.pageCount).contains { !doc.annotationThreads(pageIndex: $0).isEmpty },
                hasAttachments: !self.attachments.isEmpty,
                savedChoice: isTransientWindow ? nil : ReadingStateManager.shared.state(for: actualPath)?.sidebarVisible
            )
            if isReload {
                self.isSidebarVisible = keptLayout.isSidebarVisible
            } else {
                self.sidebarOpeningTab = opening.tab
                self.isSidebarVisible = opening.isVisible
            }

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
            self.recentSearches = []
            if !isTransientWindow, let saved = ReadingStateManager.shared.state(for: actualPath) {
                self.currentPageIndex = min(max(saved.lastPageIndex, 0), max(doc.pageCount - 1, 0))
                self.zoomScale = saved.zoomScale
                self.activeSnapshots = saved.snapshots
                self.recentSearches = saved.recentSearches ?? []
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
            // A reload that fails (a build caught writing the file) keeps what's shown; the next
            // change on disk tries again.
            guard !isReloadingAfterExternalChange else { return }
            self.showErrorAlert(
                title: "Failed to Open Document",
                message: "“\((path as NSString).lastPathComponent)” could not be opened: \(error.localizedDescription)"
            )
        }
    }

    /// Called when the open file changes on disk — reloads it live, asking first if this window
    /// has unsaved edits that would otherwise be silently discarded.
    func handleExternalFileChange(path: String) async {
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

        // A PDF still being written (pdfTeX writes as it goes) is left for its next change; one
        // that stays unfinished is loaded anyway, a moment later.
        if !Self.pdfLooksComplete(atPath: path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let sizeNow = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
            // Still growing: its next change brings this back.
            guard document?.filePath == path, Self.pdfLooksComplete(atPath: path) || sizeNow == size else { return }
        }
        isReloadingAfterExternalChange = true
        defer { isReloadingAfterExternalChange = false }
        await loadDocument(from: path, password: currentDocumentPassword)
    }

    /// Whether the file ends as a finished PDF does, with `%%EOF` in its last kilobyte. Other
    /// formats always count as finished.
    nonisolated static func pdfLooksComplete(atPath path: String) -> Bool {
        guard path.lowercased().hasSuffix(".pdf") else { return true }
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end > 0 else { return false }
        try? handle.seek(toOffset: end > 1024 ? end - 1024 : 0)
        guard let tail = try? handle.readToEnd() else { return false }
        return tail.range(of: Data("%%EOF".utf8)) != nil
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
    
    /// Renders a page if it hasn't been; with `replacing`, again, keeping the old picture on
    /// screen until the new one is ready.
    public func renderPage(_ pageIndex: Int, replacing: Bool = false) async {
        guard replacing || !hasCurrentRender(of: pageIndex), !pagesCurrentlyRendering.contains(pageIndex) else { return }
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
        let startLayers = layerGeneration
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
            if document === startDocument, effectiveZoom == startZoom, layerGeneration == startLayers {
                // Sized from the page's native bounds, not from the bitmap: the actor may have
                // clamped the render scale (see PDFRenderActor.maxRenderDimension), which would
                // otherwise shrink the image's point size at high zoom.
                let nsImage = NSImage(
                    cgImage: rendered.image,
                    size: NSSize(width: rendered.nativeBounds.width * startZoom, height: rendered.nativeBounds.height * startZoom)
                )
                renderedPages[pageIndex] = nsImage
                renderedPageZooms[pageIndex] = startZoom
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
        if isStale && !isLiveZooming {
            await renderPage(pageIndex)
        }
    }

    /// Whether the page has a bitmap rendered at the current zoom. One from before a zoom still
    /// draws, stretched, until this is true.
    public func hasCurrentRender(of pageIndex: Int) -> Bool {
        renderedPages[pageIndex] != nil && renderedPageZooms[pageIndex] == effectiveZoom
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
    
    /// Goes to an outline entry's heading: leaves the view where it is if the heading is already
    /// on screen, or scrolls it to near the top if not. Entries pointing at a page but no place
    /// on it go to the top of the page.
    public func jumpToOutlineEntry(_ node: PDFOutlineNode) {
        guard let page = node.targetPage else { return }
        guard let doc = document, page >= 0, page < doc.pageCount,
              let y = node.targetY, y.isFinite else {
            jumpToPage(page)
            return
        }
        loadPageMetadata(page)
        outlineJump = OutlineJump(
            token: (outlineJump?.token ?? 0) &+ 1,
            pageIndex: page,
            rect: OutlineJump.headingRect(y: y, title: node.title, pageBounds: doc.pageBounds[page], page: pageStructuredData[page])
        )
        jumpToPage(page)
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

    func updateNavigationHistoryState() {
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

    public func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        viewModel?.undoManager
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
