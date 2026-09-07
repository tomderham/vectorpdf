import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import PDFKit

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
    @Published public var currentPageIndex: Int = 0
    @Published public var zoomScale: CGFloat = 1.0
    @Published public var renderedPages: [Int: NSImage] = [:]
    /// Pages currently being rendered by renderActor — checked by renderPage(_:) so rapid repeated
    /// calls for the same not-yet-rendered page (e.g. draw(_:) firing on every scroll tick before
    /// the first render completes) queue at most one actual render request instead of piling up
    /// duplicates that the actor would just serialize through redundantly.
    private var pagesCurrentlyRendering: Set<Int> = []
    @Published public var documentTitle: String = "VectorPDF"

    // View Rotation: a whole-document, display-only rotation (doesn't touch the saved PDF) for
    // reading a page that came in sideways. Deliberately read-only while active — see
    // recomputeEffectiveLayout's doc comment and PDFCanvasView, which skips search-highlight,
    // selection, and form-widget rendering/interaction whenever this is non-zero, rather than
    // teaching every one of those independent rendering paths its own rotation math.
    @Published public private(set) var viewRotationDegrees: Int = 0
    /// Per-page Y offsets and total content height for vertical stacking, adjusted for rotation:
    /// at 0°/180° a page's on-screen footprint matches its native bounds, but at 90°/270° width
    /// and height are swapped, so the stacking spacing must swap too, or pages would overlap or
    /// leave oversized gaps. Equal to `document.pageYOffsets`/`totalHeight` at 0°/180° (i.e. always,
    /// for the common unrotated case). Every layout/hit-testing call site reads these instead of
    /// `document.pageYOffsets`/`totalHeight` directly, so scrolling and hit-testing stay correct
    /// regardless of rotation or Two-Page Mode.
    @Published public private(set) var effectivePageYOffsets: [CGFloat] = []
    @Published public private(set) var effectiveTotalHeight: CGFloat = 0

    private var isRotatedSideways: Bool { viewRotationDegrees == 90 || viewRotationDegrees == 270 }

    // Two-Page Mode: pages shown in side-by-side pairs for reading, instead of a single
    // continuous column. Read-only for the same reason as rotation (see viewRotationDegrees's doc
    // comment) and deliberately kept mutually exclusive with it, rather than trying to make the
    // two compose — see recomputeEffectiveLayout.
    @Published public private(set) var isTwoPageMode: Bool = false

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
        isTwoPageMode.toggle()
        if isTwoPageMode {
            viewRotationDegrees = 0
        }
        recomputeEffectiveLayout()
    }

    private func recomputeEffectiveLayout() {
        guard let doc = document else {
            effectivePageYOffsets = []
            effectiveTotalHeight = 0
            return
        }
        if isTwoPageMode {
            // Indexed by page, like every other branch here, but both pages of a pair share the
            // same offset (their row's Y) — pageFrame tells them apart by page parity (even = left,
            // odd = right) rather than by Y, since Y alone can't distinguish two pages in the same
            // row. Consecutive pairing (0,1), (2,3), ... — no special-cased standalone cover page,
            // per "keep it simple."
            let pageSpacing: CGFloat = 16.0
            var offsets = [CGFloat](repeating: 0, count: doc.pageBounds.count)
            var currentY: CGFloat = 0
            var i = 0
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
    /// Extra pages spanned by a reading-order selection that crosses a page boundary — empty for
    /// every ordinary single-page selection (the overwhelming majority). See
    /// handleCrossPageDragSelect and PageSelectionResult's doc comment for why this is additive
    /// rather than changing what `activeSelection` itself holds.
    @Published public var additionalSelectionPages: [PageSelectionResult] = []
    @Published public var selectionMode: SelectionMode = .readingOrder
    
    // Form Widgets & Editing State
    @Published public var pageFormWidgets: [Int: [PDFFormWidget]] = [:]
    @Published public var isDocumentEdited: Bool = false
    
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
    @Published public var hasNavigatedToActiveSearchMatch: Bool = false
    public var autoNavigateOnSearchResults: Bool = false
    
    // Cross References & Snapshots
    @Published public var activeSnapshots: [SnapshotTarget] = []
    @Published public var activeSnapshotTarget: SnapshotTarget? = nil

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
    // Retrieval pool sizes for askAgentQuestion — not principled, just values that work well for a
    // small on-device model's context window. maxPassagesForSynthesis is the default passed to
    // agentConversationEngine.recommendedPassageCount, which raises it when a larger-context
    // backend (e.g. Private Cloud Compute on macOS 27+) is actually in use — see
    // DocumentAgentService.swift. The candidate pools below stay fixed since their union already
    // comfortably covers the largest passage count recommendedPassageCount can return.
    private static let embeddingCandidatePoolSize = 24
    private static let lexicalCandidatePoolSize = 10
    private static let maxPassagesForSynthesis = 6
    // Reused so the Agent tab's lazily-built index doesn't need to re-prompt for a password
    // already entered once to open the document (see promptForPasswordAndRetry).
    private var currentDocumentPassword: String?
    // Watches the open file for external changes (e.g. edited/regenerated by another app) and
    // reloads it live — see handleExternalFileChange. Replacing this property (done every
    // loadDocument call) tears down the previous watcher via its deinit.
    private var fileChangeWatcher: FileChangeWatcher?

    // Background Concurrency Actors
    // Note: PDFRenderActor and PDFSearchActor each maintain their own cloned MuPDF context
    // and document instance to avoid multi-threaded data races on the C data structures.
    // Capacity matches maxRenderedPageCache's Two-Page Mode value below — display lists are just
    // recorded drawing commands, much lighter than a rasterized bitmap, so caching more is cheap.
    private let renderActor = PDFRenderActor(cacheCapacity: 12)
    private let searchActor = PDFSearchActor()
    private var searchTask: Task<Void, Never>?
    private let textSelector = SpatialTextSelector()

    // Strict bounded cache limits: keeps physical memory <= 60 MB in the normal single-column
    // layout. Two-Page Mode needs a higher cap, since up to 3 full rows (6 pages) plus draw(_:)'s
    // own ±1 page buffer can be on screen at once — a lower cap here would evict still-visible
    // pages on every prune, which draw(_:) would immediately re-render, flickering.
    private var maxRenderedPageCache: Int { isTwoPageMode ? 12 : 4 }
    private let maxStructuredDataCache: Int = 6
    
    // Tab and Window Scoping
    public static weak var active: PDFViewerViewModel?
    public weak var currentWindow: NSWindow?
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

    // Intentionally does NOT call PDFViewerAppCoordinator.shared.registerActive(self) here.
    // @StateObject's initializer runs as part of SwiftUI constructing the view graph — i.e.
    // during a view update — and registerActive() mutates several @Published properties on the
    // coordinator singleton in sequence, which is exactly what "Publishing changes from within
    // view updates is not allowed" describes and can corrupt AppKit/SwiftUI object lifecycle
    // bookkeeping. PDFViewerMainView's .onAppear calls registerActive(viewModel) instead, at a
    // safe time after the view is mounted.
    public init() {}

    public func loadDocument(from path: String, password: String? = nil) async {
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

        do {
            let doc = try await Task.detached(priority: .userInitiated) {
                try PDFDocumentCore(filePath: path, password: password)
            }.value
            self.document = doc
            self.currentDocumentPassword = password
            let fileURL = URL(fileURLWithPath: path)
            let fileName = fileURL.lastPathComponent
            self.documentTitle = fileName
            PDFViewerAppCoordinator.shared.registerActive(self)
            PDFViewerAppCoordinator.shared.noteRecentDocument(fileURL)

            // Set representedURL only on this tab's window
            if let window = currentWindow ?? NSApplication.shared.keyWindow {
                window.representedURL = fileURL
                window.isDocumentEdited = false
                if !isTransientWindow && window.tabGroup?.isTabBarVisible != true {
                    window.toggleTabBar(nil)
                }
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
            self.pageLinks = [:]
            self.pageStructuredData = [:]
            self.activeSelection = nil
            self.additionalSelectionPages = []
            self.currentPageIndex = 0
            self.zoomScale = 1.0
            // Rotation and Two-Page Mode are both per-document — a fresh document always starts
            // unrotated and single-column, and recomputeEffectiveLayout must run at least once for
            // any newly-loaded document regardless, since it's what populates effectivePageYOffsets/
            // effectiveTotalHeight in the first place.
            self.viewRotationDegrees = 0
            self.isTwoPageMode = false
            self.recomputeEffectiveLayout()

            // Agent tab state is entirely per-document — an in-progress or completed index for
            // whatever was open before is meaningless (and, worse, misleading) once the document
            // has switched.
            self.agentIndexingTask?.cancel()
            self.agentIndexingTask = nil
            self.agentIndexBuilder = nil
            self.agentChunks = []
            self.agentIndexState = .idle
            self.agentQuestion = ""
            self.agentConversation = []
            self.agentIsAnswering = false
            self.agentConversationEngine.reset()

            // Restore this document's remembered page/zoom/snapshots, if any — skipped for
            // transient windows, whose whole purpose is to show a specific *other* point in the
            // document regardless of where the reader last left off (and which, per
            // saveReadingStateIfNeeded, never write this state in the first place).
            if !isTransientWindow, let saved = ReadingStateManager.shared.state(for: path) {
                self.currentPageIndex = min(max(saved.lastPageIndex, 0), max(doc.pageCount - 1, 0))
                self.zoomScale = saved.zoomScale
                self.activeSnapshots = saved.snapshots
            }

            try await renderActor.openDocument(filePath: path, password: password)
            try await searchActor.openDocument(filePath: path, password: password)

            await renderPage(currentPageIndex)
            loadPageMetadata(currentPageIndex)

            // (Re-)armed on every successful load, including a reload triggered by this very
            // watcher — that's what picks the new file back up after handleExternalFileChange
            // calls back into loadDocument.
            armFileChangeWatcher(path: path)
        } catch PDFError.passwordRequired {
            await promptForPasswordAndRetry(path: path, wasIncorrect: false)
        } catch PDFError.incorrectPassword {
            await promptForPasswordAndRetry(path: path, wasIncorrect: true)
        } catch {
            print("Failed to load document: \(error)")
        }
    }

    /// Called when the open file changes on disk — reloads it live, asking first if this window
    /// has unsaved edits that would otherwise be silently discarded.
    private func handleExternalFileChange(path: String) async {
        // The document (or this whole window) may have moved on since this was scheduled — a
        // stale notification from a watcher that's since been replaced/torn down.
        guard document?.filePath == path else { return }

        if isDocumentEdited {
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
        pagesCurrentlyRendering.insert(pageIndex)
        defer { pagesCurrentlyRendering.remove(pageIndex) }
        do {
            let rendered = try await renderActor.renderPage(pageIndex: pageIndex, scale: zoomScale * 2.0)
            let cgImage = rendered.image
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
            renderedPages[pageIndex] = nsImage
            // Corrects this page's assumed placeholder geometry the first time its real bounds turn
            // out to differ (only ever does anything for documents > 60 pages — see
            // PDFDocumentCore.hasExactBounds) and refreshes the derived layout SwiftUI/the scroll
            // view actually reads whenever it does.
            if document?.recordActualPageBounds(rendered.nativeBounds, forPage: pageIndex) == true {
                recomputeEffectiveLayout()
            }
            loadPageMetadata(pageIndex)
            pruneCaches(around: pageIndex)
        } catch {
            print("Failed to render page \(pageIndex): \(error)")
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
    }
    
    public func jumpToPage(_ pageIndex: Int) {
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return }
        self.currentPageIndex = pageIndex
        pruneCaches(around: pageIndex)
        Task {
            await renderPage(pageIndex)
        }
    }
    
    public func nextPage() {
        guard let doc = document, currentPageIndex + 1 < doc.pageCount else { return }
        jumpToPage(currentPageIndex + 1)
    }
    
    public func previousPage() {
        guard currentPageIndex > 0 else { return }
        jumpToPage(currentPageIndex - 1)
    }
    
    // MARK: - Search Functionality
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
        activeSearchMatchIndex = (activeSearchMatchIndex + 1) % searchResults.count
        let match = searchResults[activeSearchMatchIndex]
        self.activeSearchMatchId = match.id
        self.searchScrollRevision += 1
        self.currentPageIndex = match.pageIndex
        self.activeScrollTargetId = match.id.uuidString
        pruneCaches(around: match.pageIndex)
        Task {
            await renderPage(match.pageIndex)
        }
    }
    
    public func previousSearchMatch() {
        guard !searchResults.isEmpty else { return }
        if !hasNavigatedToActiveSearchMatch {
            navigateToMatch(at: activeSearchMatchIndex, shouldScrollList: false)
            return
        }
        activeSearchMatchIndex = (activeSearchMatchIndex - 1 + searchResults.count) % searchResults.count
        let match = searchResults[activeSearchMatchIndex]
        self.activeSearchMatchId = match.id
        self.searchScrollRevision += 1
        self.currentPageIndex = match.pageIndex
        self.activeScrollTargetId = match.id.uuidString
        pruneCaches(around: match.pageIndex)
        Task {
            await renderPage(match.pageIndex)
        }
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
        pruneCaches(around: match.pageIndex)
        Task {
            await renderPage(match.pageIndex)
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

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            let stream = await searchActor.searchStream(query: query, nearPage: currentNear, options: options)
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

    /// Handles a reading-order drag that has moved onto a *different* page than where it started
    /// (e.g. dragging from partway down page 3 into page 4) — selects from whichever of the two
    /// points is on the earlier page down to the bottom of that page, the whole of any pages
    /// fully in between, and from the top of the later page down to the other point. Ordered by
    /// page number, not by which point the user actually dragged from, so dragging bottom-to-top
    /// across a page break reads the same as top-to-bottom.
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
    
    /// Copies the active rectangular selection as high-DPI image (PNG + TIFF + NSImage) to NSPasteboard.general
    public func copyActiveScreenshot() {
        guard let image = renderCroppedSelection() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        
        let objectsToCopy: [NSPasteboardWriting] = [image]
        
        if let tiffData = image.tiffRepresentation {
            if let rep = NSBitmapImageRep(data: tiffData),
               let pngData = rep.representation(using: .png, properties: [:]) {
                pb.setData(pngData, forType: .png)
            }
            pb.setData(tiffData, forType: .tiff)
        }
        
        // Also provide extracted text if available so text destinations receive text
        if let sel = activeSelection, !sel.result.text.isEmpty {
            pb.setString(sel.result.text, forType: .string)
        }
        
        pb.writeObjects(objectsToCopy)
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
    private func buildSnapshotTargetFromSelection() -> SnapshotTarget? {
        guard let sel = activeSelection else { return nil }
        let pageIdx = sel.pageIndex
        let bounds = (document?.pageBounds.indices.contains(pageIdx) == true)
            ? document!.pageBounds[pageIdx]
            : CGRect(x: 0, y: 0, width: 612, height: 792)
        let combinedText = activeSelectionCombinedText

        let labelText: String
        if !combinedText.isEmpty {
            let firstLine = combinedText.components(separatedBy: .newlines).first ?? combinedText
            labelText = String(firstLine.prefix(45))
        } else if sel.result.mode == .rectangularArea {
            labelText = "Area Snapshot (Page \(pageIdx + 1))"
        } else {
            // A reading-order selection with nothing extractable (visible highlight, empty
            // text) — rare, but possible; "Area Snapshot" would be actively misleading here.
            labelText = "Snapshot (Page \(pageIdx + 1))"
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

        let targetRect = sel.result.boundingRect
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
        
        let thumbImage = NSImage(cgImage: cropped, size: NSSize(width: min(cropW / scaleX, 260), height: min(cropH / scaleY, 140)))
        guard let tiff = thumbImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png
    }
    
    /// Opens `target` in a new, separate window (not a tab) positioned at that exact location —
    /// for keeping related sections of the same document visible side by side. Used both by
    /// saved snapshot cards and by Option-click / "Open in New Window" on cross-reference links,
    /// selections, and plain page locations. `currentWindow` (this document's own window) is
    /// passed as the source so the new window cascades near it and closes automatically if this
    /// window closes first.
    public func openSnapshotInNewWindow(_ target: SnapshotTarget) {
        guard let doc = document else { return }
        let source = currentWindow ?? NSApplication.shared.keyWindow
        SnapshotWindowManager.shared.open(url: URL(fileURLWithPath: doc.filePath), target: target, source: source)
    }

    /// Closes the snapshot window for `target`, if one is currently open. Snapshot cards use
    /// this to turn their window button into a Close action once its window is already open.
    public func closeSnapshotWindow(_ target: SnapshotTarget) {
        SnapshotWindowManager.shared.close(target.id)
    }

    public func jumpToSnapshot(_ snap: SnapshotTarget) {
        self.activeSnapshotTarget = snap
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
    // The 0.5/4.0 clamp bounds here match PDFViewerAppCoordinator.minZoomScale/maxZoomScale,
    // which the View menu's Zoom In/Out enablement is based on — keep both in sync.
    public func zoomIn() {
        let step: CGFloat = 0.25
        let epsilon: CGFloat = 0.001
        let nextStep = (floor((zoomScale + epsilon) / step) + 1.0) * step
        setZoom(min(round(nextStep * 100) / 100, 4.0))
    }

    public func zoomOut() {
        let step: CGFloat = 0.25
        let epsilon: CGFloat = 0.001
        let prevStep = (ceil((zoomScale - epsilon) / step) - 1.0) * step
        setZoom(max(round(prevStep * 100) / 100, 0.5))
    }
    
    public func resetZoom() {
        setZoom(1.0)
    }
    
    public func setZoom(_ newZoom: CGFloat) {
        zoomScale = newZoom
        renderedPages = [:]
        Task { await renderPage(currentPageIndex) }
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
        guard !paths.isEmpty else { return }

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

    public func promptOpenFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Open PDF"

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openDocumentPreferringNewWindow(atPath: url.path)
        }
        
        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            if window.attachedSheet == nil {
                panel.beginSheetModal(for: window, completionHandler: completion)
                return
            }
        }
        panel.begin(completionHandler: completion)
    }
    
    public func updateWidgetValue(pageIndex: Int, widgetIndex: Int, value: String) {
        guard let doc = document else { return }
        do {
            try doc.setFormWidgetValue(pageIndex: pageIndex, widgetIndex: widgetIndex, value: value)
            let refreshed = doc.loadFormWidgets(for: pageIndex)
            pageFormWidgets[pageIndex] = refreshed
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
            NotificationCenter.default.post(name: .formWidgetDidChange, object: nil)
        } catch {
            print("Failed to set form widget value: \(error)")
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
    /// external change.
    private func armFileChangeWatcher(path: String) {
        fileChangeWatcher = FileChangeWatcher(path: path) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleExternalFileChange(path: path)
            }
        }
    }

    public func saveDocument() {
        guard let doc = document else { return }
        // Suspend for our own write (an atomic replace, indistinguishable from an external change)
        // to avoid a pointless self-triggered reload; re-arm right after.
        fileChangeWatcher = nil
        defer { armFileChangeWatcher(path: doc.filePath) }
        do {
            try doc.save(to: doc.filePath)
            self.isDocumentEdited = false
            self.currentWindow?.isDocumentEdited = false
        } catch {
            print("Failed to save document: \(error)")
            let alert = NSAlert()
            alert.messageText = "Failed to Save Document"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            if let window = currentWindow ?? NSApplication.shared.keyWindow {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
        }
    }
    
    public func saveDocumentAs() {
        guard let doc = document else { return }
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
                    await self.loadDocument(from: url.path)
                } catch {
                    print("Failed to save document as: \(error)")
                    let alert = NSAlert()
                    alert.messageText = "Failed to Save Document"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    if let window = self.currentWindow ?? NSApplication.shared.keyWindow {
                        alert.beginSheetModal(for: window, completionHandler: nil)
                    } else {
                        alert.runModal()
                    }
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
    
    public func printDocument() {
        guard let doc = document else { return }
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
        
        guard let pdfDoc = PDFKit.PDFDocument(url: printURL) else {
            print("Failed to open PDF document for printing at \(printURL.path)")
            if let temp = temporaryFileURL {
                try? FileManager.default.removeItem(at: temp)
            }
            return
        }

        // This is a separate PDFKit.PDFDocument instance from our own MuPDF-backed one, so it
        // needs its own unlock — without this, printing a password-protected PDF silently fails
        // (or prints blank pages) since pdfDoc.isLocked stays true.
        if pdfDoc.isLocked, let password = currentDocumentPassword {
            _ = pdfDoc.unlock(withPassword: password)
        }

        let printInfo = NSPrintInfo.shared
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        
        guard let printOp = pdfDoc.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: true) else {
            print("Failed to initialize print operation")
            if let temp = temporaryFileURL {
                try? FileManager.default.removeItem(at: temp)
            }
            return
        }
        printOp.showsPrintPanel = true
        printOp.showsProgressPanel = true
        
        if let window = currentWindow ?? NSApplication.shared.keyWindow {
            printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            printOp.run()
        }
        
        if let temp = temporaryFileURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) {
                try? FileManager.default.removeItem(at: temp)
            }
        }
    }
    
    public func addSnapshotTarget(_ target: SnapshotTarget) {
        if !activeSnapshots.contains(where: { $0.id == target.id }) {
            activeSnapshots.append(target)
            saveReadingStateIfNeeded()
        }
    }

    public func removeSnapshotTarget(_ target: SnapshotTarget) {
        activeSnapshots.removeAll(where: { $0.id == target.id })
        target.deleteThumbnailFile()
        saveReadingStateIfNeeded()
    }

    public func clearAllSnapshots() {
        for target in activeSnapshots {
            target.deleteThumbnailFile()
        }
        activeSnapshots.removeAll()
        saveReadingStateIfNeeded()
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

    // MARK: - Agent Tab

    /// True when on-device answer synthesis (not just passage retrieval) can be attempted on this
    /// Mac — used by the UI to set expectations before a query is even run (e.g. "showing matching
    /// passages only" vs. an actual generated answer).
    public func isAgentSynthesisAvailable() -> Bool {
        agentConversationEngine.isSynthesisAvailable()
    }

    /// Lazily builds (or loads from an on-disk cache) the current document's semantic index.
    /// Deliberately not triggered on every document open — indexing a long document is real,
    /// possibly slow work most sessions never need — so this is called when the Agent sidebar tab
    /// is first shown instead. Safe to call repeatedly; a no-op once already building or ready.
    public func startAgentIndexingIfNeeded() {
        guard let doc = document, agentIndexState == .idle else { return }
        let path = doc.filePath
        let password = currentDocumentPassword

        agentIndexingTask?.cancel()
        agentIndexingTask = Task { [weak self] in
            guard let self else { return }

            // Every `await` below is a point where this task can resume *after* having been
            // cancelled (e.g. the user switched to a different document while this was in
            // flight) — each resumption is guarded so a stale task can never write index state
            // for a document that's no longer the one actually open, which would otherwise
            // silently clobber a newer document's freshly-reset Agent state.
            let cached = await SemanticIndexStore.shared.load(for: path)
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

            self.agentChunks = chunks
            self.agentIndexState = .ready
            self.agentIndexBuilder = nil

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

    /// Clears the visible conversation and drops the persistent on-device session, so the next
    /// question starts fresh instead of dragging along whatever topic came before — the retrieval
    /// index itself is untouched, so this doesn't re-trigger indexing.
    public func startNewAgentConversation() {
        agentConversation = []
        agentConversationEngine.reset()
    }

    /// Runs `agentQuestion` against the already-built semantic index, appending a new turn to
    /// `agentConversation`. Passages (which work on any Mac, see TextEmbedder) are filled in as
    /// soon as retrieval finishes; the synthesized answer streams in afterward, word by word, if
    /// on-device generation is available — the UI shows just the passages when it isn't.
    public func askAgentQuestion() {
        let question = agentQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, agentIndexState == .ready, !agentChunks.isEmpty else { return }

        agentQuestion = ""
        agentIsAnswering = true
        // Folded into the retrieval query (not the question shown to the user, and not what's sent
        // to the model) so a short follow-up like "go into more detail on that" still retrieves
        // sensibly — the embedding step has no other way to know what "that" refers to.
        let previousQuestion = agentConversation.last?.question
        let turnId = UUID()
        agentConversation.append(AgentTurn(id: turnId, question: question, isStreaming: true))

        let chunksSnapshot = agentChunks
        Task { [weak self] in
            guard let self else { return }
            let retrievalQuery = previousQuestion.map { "\($0)\n\(question)" } ?? question
            guard let queryVector = await self.agentEmbedder.embed(retrievalQuery) else {
                self.finishAgentTurn(id: turnId, text: "")
                return
            }
            // Two-signal retrieval: score every chunk on embedding similarity AND lexical relevance
            // independently, then rerank the *union* of the top candidates from each list — a chunk
            // with an exact term match can rank outside the top embedding matches (a precise
            // definition doesn't always embed close to a question about it) and lexical reranking
            // within the embedding-only pool alone could never reach it. Lexical scoring uses the
            // current question only (not the folded-in previous one used for the embedding step
            // above), since it should reflect exactly what's being asked right now.
            let embeddingScores = chunksSnapshot.map { cosineSimilarity(queryVector, $0.vector) }
            let lexicalScores = chunksSnapshot.map { lexicalRelevanceScore(query: question, text: $0.chunk.text) }
            let topByEmbedding = chunksSnapshot.indices.sorted { embeddingScores[$0] > embeddingScores[$1] }.prefix(Self.embeddingCandidatePoolSize)
            let topByLexical = chunksSnapshot.indices
                .filter { lexicalScores[$0] > 0 }
                .sorted { lexicalScores[$0] > lexicalScores[$1] }
                .prefix(Self.lexicalCandidatePoolSize)
            let candidateIndices = Set(topByEmbedding).union(topByLexical)
            let passageBudget = self.agentConversationEngine.recommendedPassageCount(onDeviceDefault: Self.maxPassagesForSynthesis)
            let ranked = candidateIndices
                .map { i in (embedded: chunksSnapshot[i], score: hybridRelevanceScore(embeddingScore: embeddingScores[i], lexicalScore: lexicalScores[i])) }
                .sorted { $0.score > $1.score }
                .prefix(passageBudget)
            let passages = ranked.map {
                AgentPassage(pageIndex: $0.embedded.chunk.pageIndex, text: $0.embedded.chunk.text, score: $0.score)
            }
            let initialProvider = self.agentConversationEngine.activeSynthesisProvider()
            self.updateAgentTurn(id: turnId) {
                $0.passages = passages
                $0.providerUsed = initialProvider
            }

            let result = await self.agentConversationEngine.streamAnswer(question: question, passages: passages) { [weak self] partial in
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

