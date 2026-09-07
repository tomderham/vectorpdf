import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PDFKit

// Notifications used for app lifecycle events
extension Notification.Name {
    public static let openFilePathCommand = Notification.Name("openFilePathCommand")
    public static let focusSearchCommand = Notification.Name("focusSearchCommand")
    public static let formWidgetDidChange = Notification.Name("formWidgetDidChange")
}

/// Standalone, reusable macOS SwiftUI PDF Document Viewer
public struct PDFViewerMainView: View {
    @StateObject public var viewModel = PDFViewerViewModel()
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @ObservedObject private var appCoordinator = PDFViewerAppCoordinator.shared
    @ObservedObject private var tabGroupManager = TabGroupManager.shared
    @ObservedObject private var snapshotWindowManager = SnapshotWindowManager.shared
    @State private var selectedSidebarTab: Int = 0
    @State private var gestureBaseZoom: CGFloat = 1.0
    @State private var sidebarVisibility: NavigationSplitViewVisibility
    @FocusState private var isAgentInputFocused: Bool
    public let initialFilePath: String?
    public let initialTarget: SnapshotTarget?
    public let onOpenNewTab: ((URL) -> Void)?
    public let onOpenNewWindow: ((URL) -> Void)?
    /// The saved Tab Group this window was opened as an instance of, if any — lets the toolbar
    /// offer "Update Group" (overwrite that group's document list with whatever tabs this window
    /// currently has) instead of only ever "Save as a new Group."
    public let groupOrigin: UUID?
    /// True only for windows opened by SnapshotWindowManager. Omits the sidebar UI
    /// in favor of a focused top banner identifying the snapshot target.
    public let isSnapshotWindow: Bool

    public init(
        initialFilePath: String? = nil,
        initialURL: URL? = nil,
        initialTarget: SnapshotTarget? = nil,
        isSnapshotWindow: Bool = false,
        groupOrigin: UUID? = nil,
        onOpenNewTab: ((URL) -> Void)? = nil,
        onOpenNewWindow: ((URL) -> Void)? = nil
    ) {
        self.initialFilePath = initialURL?.path ?? initialFilePath
        self.initialTarget = initialTarget
        self.onOpenNewTab = onOpenNewTab
        self.onOpenNewWindow = onOpenNewWindow
        self.isSnapshotWindow = isSnapshotWindow
        self.groupOrigin = groupOrigin
        // Every window/tab that ends up showing a real document starts with the sidebar open —
        // ToC/Search/Snapshots are useful immediately, not just after manually revealing them.
        // The one place this doesn't matter is the blank Start screen (no document loaded yet),
        // which doesn't render a sidebar at all regardless of this value (see body below); once
        // a document loads into that same window/tab, it inherits this same open default.
        self._sidebarVisibility = State(initialValue: .all)
    }

    /// Small persistent identifier bar for snapshot windows, replacing the sidebar's normal role
    /// of making a window's purpose obvious — visible regardless of window size or focus, unlike
    /// a title bar string that's easy to skim past. Clicking it jumps back to (and re-highlights)
    /// the exact snapshot position, same as when the window first opened — useful after scrolling
    /// or zooming away from it while looking around.
    @ViewBuilder
    private var snapshotWindowBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "macwindow.badge.plus")
                .foregroundStyle(Color.accentColor)
            Text("Snapshot Window")
                .font(.caption.weight(.semibold))
            if let target = initialTarget {
                Text("— \(target.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
        .contentShape(Rectangle())
        .onTapGesture {
            if let target = initialTarget {
                viewModel.jumpToSnapshot(target)
            }
        }
        .help("Click to jump back to this snapshot")
        Divider()
    }

    /// The document canvas plus its pinch-to-zoom gesture — identical for both the normal
    /// (sidebar) layout's `detail:` and the sidebar-less snapshot-window layout.
    @ViewBuilder
    private var documentCanvas: some View {
        PDFVirtualizedScrollView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        if gestureBaseZoom == 1.0 {
                            gestureBaseZoom = viewModel.zoomScale
                        }
                        let targetZoom = gestureBaseZoom * scale
                        let clamped = min(max(targetZoom, 0.5), 4.0)
                        viewModel.zoomScale = clamped
                    }
                    .onEnded { scale in
                        let targetZoom = gestureBaseZoom * scale
                        let clamped = min(max(targetZoom, 0.5), 4.0)
                        gestureBaseZoom = 1.0
                        viewModel.setZoom(clamped)
                    }
            )
            .overlay(alignment: .bottom) {
                if let doc = viewModel.document, doc.pageCount > 1 {
                    FloatingReaderHUD(viewModel: viewModel, pageCount: doc.pageCount)
                        .padding(.bottom, 16)
                }
            }
    }

    /// Shown in place of the sidebar+canvas whenever this window/tab has no document loaded —
    /// Favorites and Tab Groups give an immediate way to get somewhere without going to the menu
    /// bar, rather than a blank page and an empty "No Outline" sidebar.
    @ViewBuilder
    private var startScreen: some View {
        VStack(spacing: 20) {
            Button {
                viewModel.promptOpenFile()
            } label: {
                Label("Open PDF...", systemImage: "folder")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 40)

            if favoritesManager.favorites.isEmpty && tabGroupManager.groups.isEmpty {
                // Nothing saved yet — the lists below have nothing to show, and pointing at
                // "the star icon above" would be actively wrong here anyway: with no document
                // open, that menu has no "Add to Favorites" action at all (there's nothing to
                // favorite yet). The Open PDF button above is the only path forward, so leave it
                // at that rather than describing a menu item that doesn't apply.
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !tabGroupManager.groups.isEmpty {
                            startScreenSection("Tab Groups") {
                                ForEach(tabGroupManager.groups) { group in
                                    StartScreenRow(
                                        title: group.name,
                                        subtitle: "\(group.documentPaths.count) tab\(group.documentPaths.count == 1 ? "" : "s")",
                                        systemImage: "square.grid.2x2",
                                        onOpen: { tabGroupManager.open(group) },
                                        onRemove: { tabGroupManager.removeGroup(group.id) }
                                    )
                                }
                            }
                        }
                        if !favoritesManager.favorites.isEmpty {
                            startScreenSection("Favorites") {
                                ForEach(favoritesManager.favorites) { fav in
                                    StartScreenRow(
                                        title: fav.title,
                                        subtitle: nil,
                                        systemImage: "doc.text",
                                        onOpen: { viewModel.openDocumentPreferringNewWindow(atPath: fav.path) },
                                        onRemove: { favoritesManager.removeFavorite(path: fav.path) }
                                    )
                                }
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 480)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // No separate .onDrop here — body already applies one to the whole view (see below),
        // which covers this screen too.
    }

    @ViewBuilder
    private func startScreenSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// User-facing label for which backend answered an Agent turn — see AgentSynthesisProvider.
    private func providerLabel(for provider: AgentSynthesisProvider) -> String {
        switch provider {
        case .onDevice: return "Answered on-device"
        case .privateCloudCompute: return "Answered via Private Cloud Compute"
        }
    }

    public var body: some View {
        Group {
            if isSnapshotWindow {
                // No NavigationSplitView at all — see `isSnapshotWindow`'s doc comment for why
                // snapshot windows don't get a sidebar (not even a hidden, revealable one).
                VStack(spacing: 0) {
                    snapshotWindowBanner
                    documentCanvas
                }
            } else if viewModel.document == nil {
                // Display Favorites and Tab Groups when no document is open
                startScreen
            } else {
                navigationSplitBody
            }
        }
        .toolbar {
            documentToolbarContent
        }
        .navigationTitle(viewModel.documentTitle)
        .background(
            WindowAccessor { window in
                viewModel.currentWindow = window
                if !isSnapshotWindow {
                    window.tabbingMode = .preferred
                    if window.tabGroup?.isTabBarVisible != true {
                        window.toggleTabBar(nil)
                    }
                } else {
                    window.tabbingMode = .disallowed
                }
                if window.isKeyWindow {
                    PDFViewerViewModel.active = viewModel
                    PDFViewerAppCoordinator.shared.registerActive(viewModel)
                }
                if let doc = viewModel.document {
                    window.representedURL = URL(fileURLWithPath: doc.filePath)
                }
            }
        )
        .onAppear {
            PDFViewerViewModel.active = viewModel
            PDFViewerAppCoordinator.shared.registerActive(viewModel)
            if let onOpenNewTab = onOpenNewTab {
                viewModel.onOpenNewTab = onOpenNewTab
            }
            if let onOpenNewWindow = onOpenNewWindow {
                viewModel.onOpenNewWindow = onOpenNewWindow
            }
            viewModel.groupOrigin = groupOrigin
            viewModel.isTransientWindow = isSnapshotWindow
            if !isSnapshotWindow {
                PDFViewerAppCoordinator.shared.trackForReadingStateFlush(viewModel)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notif in
            // Flush this window's reading position the moment it closes — the other two save
            // points (loadDocument's save-on-switch, and the app-quit flush in
            // PDFViewerAppCoordinator) don't cover "closed this specific window/tab while the
            // rest of the app stays open."
            if let win = notif.object as? NSWindow, win == viewModel.currentWindow {
                viewModel.saveReadingStateIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notif in
            if let win = notif.object as? NSWindow, win == viewModel.currentWindow {
                PDFViewerViewModel.active = viewModel
                PDFViewerAppCoordinator.shared.registerActive(viewModel)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleFileDrop)
        .onReceive(NotificationCenter.default.publisher(for: .openFilePathCommand)) { notif in
            guard viewModel.currentWindow?.isKeyWindow == true || viewModel.currentWindow == nil else { return }
            if let path = notif.object as? String {
                Task {
                    await viewModel.loadDocument(from: path)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchCommand)) { _ in
            guard viewModel.currentWindow?.isKeyWindow == true || viewModel.currentWindow == nil else { return }
            sidebarVisibility = .all
            selectedSidebarTab = 1
        }
        .task {
            // Falls back to a buffered cold-launch open-file path (see
            // PDFViewerAppCoordinator.pendingOpenFilePath) when this window wasn't given one
            // explicitly — covers Finder double-click launching the app fresh, where
            // .openFilePathCommand's notification has no observer mounted yet to receive it.
            if let path = initialFilePath ?? PDFViewerAppCoordinator.shared.consumePendingOpenFilePath() {
                await viewModel.loadDocument(from: path)
                if let target = initialTarget {
                    viewModel.jumpToSnapshot(target)
                }
            }
        }
    }

    @ViewBuilder
    private var navigationSplitBody: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            // Sidebar
            VStack(spacing: 0) {
                Picker("Sidebar Mode", selection: $selectedSidebarTab) {
                    Image(systemName: "list.bullet")
                        .imageScale(.medium)
                        .tag(0)
                        .help("Table of Contents")
                    Image(systemName: "magnifyingglass")
                        .imageScale(.medium)
                        .tag(1)
                        .help("Search Document (Cmd+F)")
                    Image(systemName: "camera.viewfinder")
                        .imageScale(.medium)
                        .tag(2)
                        .help("Snapshots & References")
                    if appCoordinator.showAgentTab {
                        Image(systemName: "sparkles")
                            .imageScale(.medium)
                            .tag(3)
                            .help("Ask About This Document")
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.regular)
                .padding(8)
                .onChange(of: selectedSidebarTab) { _, newValue in
                    if newValue == 3 {
                        viewModel.startAgentIndexingIfNeeded()
                    }
                }
                .onChange(of: appCoordinator.showAgentTab) { _, stillShown in
                    // The picker's Agent segment just vanished out from under a selected tag —
                    // fall back to Table of Contents rather than leaving the sidebar on a tag
                    // with no matching segment.
                    if !stillShown && selectedSidebarTab == 3 {
                        selectedSidebarTab = 0
                    }
                }

                Divider()
                
                if selectedSidebarTab == 0 {
                    // Table of Contents - Virtualized Native AppKit NSOutlineView
                    if let doc = viewModel.document, !doc.outline.isEmpty {
                        PDFOutlineNSView(outline: doc.outline, documentIdentity: doc.filePath) { targetPage in
                            viewModel.jumpToPage(targetPage)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("No Outline", systemImage: "text.justify.leading", description: Text("This document has no Table of Contents"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if selectedSidebarTab == 1 {
                    // Search Tab with Streaming Results & Navigation
                    VStack(spacing: 8) {
                        HStack {
                            NativeSearchField(
                                text: $viewModel.searchQuery,
                                placeholder: "Search document...",
                                onCommit: {
                                    viewModel.performSearch()
                                },
                                onNext: {
                                    viewModel.submitSearch()
                                },
                                onPrevious: {
                                    viewModel.previousSearchMatch()
                                }
                            )
                            
                            if viewModel.isSearching {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            SearchOptionsMenu(viewModel: viewModel)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        
                        if !viewModel.searchResults.isEmpty {
                            HStack {
                                Text("\(viewModel.activeSearchMatchIndex + 1) of \(viewModel.searchResults.count)")
                                    .font(.caption2.monospacedDigit().weight(.medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(.ultraThinMaterial)
                                            .overlay(
                                                Capsule(style: .continuous)
                                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                                            )
                                    )
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                HStack(spacing: 2) {
                                    Button {
                                        viewModel.previousSearchMatch()
                                    } label: {
                                        Image(systemName: "chevron.up")
                                            .font(.caption2.weight(.semibold))
                                            .frame(width: 20, height: 20)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Previous Match (Shift+Cmd+G)")
                                    
                                    Button {
                                        viewModel.nextSearchMatch()
                                    } label: {
                                        Image(systemName: "chevron.down")
                                            .font(.caption2.weight(.semibold))
                                            .frame(width: 20, height: 20)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Next Match (Cmd+G)")
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                                        )
                                )
                            }
                            .padding(.horizontal, 8)
                        }
                        
                        Divider()
                        
                        // Plain ScrollView/LazyVStack, not List(selection:): on macOS, List(selection:)
                        // is backed by a real NSTableView, and while results are actively streaming in,
                        // flushSearchBuffer() repeatedly appends to and fully re-sorts `searchResults`
                        // (see PDFViewerViewModel.swift) — a structural table mutation landing on the
                        // same timeline as a user click's selection change is a reentrant pair of
                        // operations on the same underlying table view, regardless of how the click
                        // handler itself is dispatched. SearchResultRowView already does fully custom
                        // active/inactive styling below, so List's built-in selection UI added no
                        // visual value here — only this risk. Matches the same pattern already used
                        // for the Snapshots list a little further down in this file.
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 2) {
                                    ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, match in
                                        SearchResultRowView(
                                            match: match,
                                            isActive: viewModel.isActiveMatch(match)
                                        )
                                        .onTapGesture {
                                            DispatchQueue.main.async {
                                                viewModel.navigateToMatch(at: index, shouldScrollList: false)
                                            }
                                        }
                                        .id(match.id)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                            }
                            .onChange(of: viewModel.searchScrollRevision) { _, _ in
                                if let targetId = viewModel.activeSearchMatchId {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        proxy.scrollTo(targetId, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if selectedSidebarTab == 2 {
                    // Snapshots & Cross-References Tab
                    VStack(spacing: 0) {
                        // Shown whenever any snapshot window is open, independent of whether
                        // the Snapshots list itself is empty — a window can outlive its card
                        // (e.g. the list was cleared, or the window came from a link/selection
                        // that was never saved as a card at all), so this can't just live inside
                        // the non-empty-list branch below.
                        if snapshotWindowManager.hasOpenWindows {
                            HStack {
                                Image(systemName: "macwindow.on.rectangle")
                                    .foregroundStyle(.secondary)
                                Text("\(snapshotWindowManager.openWindowCount) Window\(snapshotWindowManager.openWindowCount == 1 ? "" : "s") Open")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Close All Windows") {
                                    snapshotWindowManager.closeAll()
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            Divider()
                        }

                        if viewModel.activeSnapshots.isEmpty {
                            ContentUnavailableView(
                                "No Snapshots",
                                systemImage: "camera.viewfinder",
                                description: Text("Select text or Option-drag an area, then right-click \u{2192} \"Create Snapshot\" to save it here.")
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            HStack {
                                Text("\(viewModel.activeSnapshots.count) Snapshot\(viewModel.activeSnapshots.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Clear All") {
                                    withAnimation {
                                        viewModel.clearAllSnapshots()
                                    }
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            
                            Divider()
                            
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(viewModel.activeSnapshots) { snap in
                                        SnapshotCardView(snap: snap, viewModel: viewModel)
                                    }
                                }
                                .padding(8)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if selectedSidebarTab == 3 {
                    // Agent Tab — semantic search over the current document only, plus an
                    // optional on-device synthesized answer where Apple Intelligence is available.
                    // Retrieval (the passage list) works regardless; synthesis is best-effort and
                    // silently absent when unsupported/disabled — see DocumentAgentService.swift.
                    VStack(spacing: 0) {
                        // Results area fills all available space above the input bar — standard
                        // chat/agent layout, not a top-anchored one-shot search field.
                        Group {
                        switch viewModel.agentIndexState {
                        case .idle:
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .building(let pagesDone, let totalPages):
                            VStack(spacing: 4) {
                                ProgressView(value: totalPages > 0 ? Double(pagesDone) / Double(totalPages) : 0)
                                Text("Indexing page \(pagesDone) of \(totalPages)…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .unavailable(let message):
                            ContentUnavailableView {
                                Label("Agent Unavailable", systemImage: "sparkles")
                            } description: {
                                Text(message)
                            } actions: {
                                Button("Retry") {
                                    viewModel.retryAgentIndexing()
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .ready:
                            VStack(spacing: 0) {
                                if !viewModel.isAgentSynthesisAvailable() {
                                    Text("On-device answer generation isn't available here — showing the best-matching passages instead.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.top, 6)
                                }

                                if viewModel.agentConversation.isEmpty {
                                    ContentUnavailableView(
                                        "Ask About This Document",
                                        systemImage: "sparkles",
                                        description: Text("Ask a simple question about the document's content. The Agent looks for answers in the whole document, but can make mistakes - check the sources to verify.")
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
                                    HStack {
                                        Spacer()
                                        Button {
                                            viewModel.startNewAgentConversation()
                                        } label: {
                                            Label("New Conversation", systemImage: "square.and.pencil")
                                        }
                                        .buttonStyle(.plain)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        // Disabled while an answer is actively streaming
                                        .disabled(viewModel.agentIsAnswering)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.top, 4)

                                    ScrollViewReader { proxy in
                                        ScrollView {
                                            LazyVStack(alignment: .leading, spacing: 16) {
                                                ForEach(viewModel.agentConversation) { turn in
                                                    VStack(alignment: .leading, spacing: 8) {
                                                        Text(turn.question)
                                                            .font(.callout.bold())
                                                            .textSelection(.enabled)

                                                        if turn.answerText.isEmpty && turn.isStreaming {
                                                            ProgressView()
                                                                .controlSize(.small)
                                                        } else if !turn.answerText.isEmpty {
                                                            Text(turn.answerText)
                                                                .font(.callout)
                                                                .textSelection(.enabled)
                                                        } else if turn.passages.isEmpty {
                                                            Text("No relevant passages found.")
                                                                .font(.caption)
                                                                .foregroundStyle(.secondary)
                                                        } else if let error = turn.errorMessage {
                                                            Text(error)
                                                                .font(.caption)
                                                                .foregroundStyle(.orange)
                                                        } else {
                                                            // Passages came back but synthesis produced nothing — most
                                                            // often the conversation has grown too long for the model's
                                                            // context window (see DocumentAgentConversation's doc comment).
                                                            // Surfaced explicitly rather than leaving this turn looking
                                                            // like it's just missing a response for no reason.
                                                            Text("Unable to respond; the conversational length limit might be reached. Try starting a new conversation or check the sources below.")
                                                                .font(.caption)
                                                                .foregroundStyle(.orange)
                                                        }

                                                        if let note = turn.statusNote {
                                                            Text(note)
                                                                .font(.caption2)
                                                                .foregroundStyle(.secondary)
                                                        }

                                                        if let provider = turn.providerUsed {
                                                            Text(providerLabel(for: provider))
                                                                .font(.caption2)
                                                                .foregroundStyle(.tertiary)
                                                        }

                                                        if !turn.passages.isEmpty {
                                                            DisclosureGroup("Sources (\(turn.passages.count))") {
                                                                VStack(alignment: .leading, spacing: 6) {
                                                                    ForEach(turn.passages) { passage in
                                                                        Button {
                                                                            viewModel.jumpToPage(passage.pageIndex)
                                                                        } label: {
                                                                            VStack(alignment: .leading, spacing: 2) {
                                                                                Text("Page \(passage.pageIndex + 1)")
                                                                                    .font(.caption.bold())
                                                                                // Trimmed rather than shown in full — this is meant as a quick
                                                                                // reminder of what the source covers, not a substitute for reading
                                                                                // it; tapping jumps straight to the actual page for that.
                                                                                Text(passage.text)
                                                                                    .font(.caption)
                                                                                    .foregroundStyle(.secondary)
                                                                                    .lineLimit(3)
                                                                                    .truncationMode(.tail)
                                                                            }
                                                                             .frame(maxWidth: .infinity, alignment: .leading)
                                                                        }
                                                                        .buttonStyle(.plain)
                                                                        .padding(6)
                                                                        .background(
                                                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                                                .fill(Color.primary.opacity(0.04))
                                                                                .overlay(
                                                                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                                                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                                                                                )
                                                                        )
                                                                    }
                                                                }
                                                                .padding(.top, 4)
                                                            }
                                                            .font(.caption)
                                                        }
                                                    }
                                                    .id(turn.id)
                                                    Divider()
                                                }
                                            }
                                            .padding(10)
                                        }
                                        // Unanimated during streaming (fires on every partial chunk —
                                        // animating each one would be jittery); animated only when a
                                        // whole new turn is appended.
                                        .onChange(of: viewModel.agentConversation.last?.answerText) { _, _ in
                                            if let lastId = viewModel.agentConversation.last?.id {
                                                proxy.scrollTo(lastId, anchor: .bottom)
                                            }
                                        }
                                        .onChange(of: viewModel.agentConversation.count) { _, _ in
                                            if let lastId = viewModel.agentConversation.last?.id {
                                                withAnimation {
                                                    proxy.scrollTo(lastId, anchor: .top)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Divider()

                        // Input bar, pinned to the bottom.
                        VStack(alignment: .trailing, spacing: 6) {
                            ZStack(alignment: .topLeading) {
                                if viewModel.agentQuestion.isEmpty {
                                    Text("Ask a question about this document…")
                                        .font(.body)
                                        .foregroundStyle(Color(nsColor: .placeholderTextColor))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }

                                TextEditor(text: $viewModel.agentQuestion)
                                    .font(.body)
                                    .scrollContentBackground(.hidden)
                                    .scrollIndicators(.hidden)
                                    .focused($isAgentInputFocused)
                                    .frame(height: 72)
                                    .padding(4)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        isAgentInputFocused ? Color.accentColor : Color.primary.opacity(0.15),
                                        lineWidth: isAgentInputFocused ? 1.5 : 1.0
                                    )
                            )

                            HStack {
                                if viewModel.agentIsAnswering {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Spacer()
                                Button("Ask") {
                                    viewModel.askAgentQuestion()
                                }
                                // Return alone inserts a newline in the multi-line box above (the
                                // normal, expected behavior for a text editor); Cmd+Return submits.
                                .keyboardShortcut(.return, modifiers: .command)
                                .disabled(
                                    viewModel.agentQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || viewModel.agentIndexState != .ready
                                    || viewModel.agentIsAnswering
                                )
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            documentCanvas
        }
    }

    @ToolbarContentBuilder
    private var documentToolbarContent: some ToolbarContent {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 6) {
                    Button {
                        viewModel.promptOpenFile()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Open PDF File (Cmd+O)")
                    
                    Menu {
                        // The two "save something for later" actions, paired together with
                        // scope stated explicitly in the label — "this PDF" vs. "all open tabs" —
                        // rather than one living up here and the other buried below the lists,
                        // which read as unrelated even though they're really two variants of the
                        // same idea.
                        if let doc = viewModel.document {
                            let isFav = favoritesManager.isFavorite(path: doc.filePath)
                            Button {
                                favoritesManager.toggleFavorite(path: doc.filePath, title: viewModel.documentTitle)
                            } label: {
                                Label(isFav ? "Remove This PDF from Favorites" : "Add This PDF to Favorites", systemImage: isFav ? "star.slash" : "star")
                            }
                        }

                        if let groupOrigin = viewModel.groupOrigin, let group = tabGroupManager.group(withId: groupOrigin) {
                            Button {
                                viewModel.updateGroupFromCurrentTabs()
                            } label: {
                                Label("Update Group “\(group.name)” with Open Tabs", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }

                        if viewModel.currentWindowTabCount > 1 {
                            Button {
                                viewModel.promptSaveCurrentWindowAsGroup()
                            } label: {
                                Label("Save All Open Tabs as a Group...", systemImage: "square.grid.2x2.fill")
                            }
                        }

                        Divider()

                        if favoritesManager.favorites.isEmpty {
                            Text("No Favorites Added")
                        } else {
                            Section("Favorites") {
                                // A submenu (not a flat button) so "open" and "remove" are two
                                // distinct, unambiguous choices — a flat list of buttons had no
                                // room for a delete action at all here (only the Start screen
                                // did), and once one's added, sharing a single click between
                                // "open this" and "remove this" isn't a good idea anyway.
                                ForEach(favoritesManager.favorites) { fav in
                                    Menu {
                                        Button {
                                            viewModel.openDocumentPreferringNewWindow(atPath: fav.path)
                                        } label: {
                                            Label("Open", systemImage: "doc.text")
                                        }
                                        Button(role: .destructive) {
                                            favoritesManager.removeFavorite(path: fav.path)
                                        } label: {
                                            Label("Remove from Favorites", systemImage: "star.slash")
                                        }
                                    } label: {
                                        Text(fav.title)
                                    }
                                }
                            }
                        }

                        if !tabGroupManager.groups.isEmpty {
                            Divider()
                            Section("Tab Groups") {
                                ForEach(tabGroupManager.groups) { group in
                                    Menu {
                                        Button {
                                            tabGroupManager.open(group)
                                        } label: {
                                            Label("Open", systemImage: "square.grid.2x2")
                                        }
                                        Button(role: .destructive) {
                                            tabGroupManager.removeGroup(group.id)
                                        } label: {
                                            Label("Delete Group", systemImage: "trash")
                                        }
                                    } label: {
                                        Text("\(group.name) (\(group.documentPaths.count))")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: (viewModel.document != nil && favoritesManager.isFavorite(path: viewModel.document!.filePath)) ? "star.fill" : "star")
                            .foregroundColor((viewModel.document != nil && favoritesManager.isFavorite(path: viewModel.document!.filePath)) ? .yellow : .secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help("Favorites & Tab Groups")
                }
            }
            
            ToolbarItem(placement: .automatic) {
                EditableZoomField(viewModel: viewModel)
                    .disabled(viewModel.document == nil)
            }
            
            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.rotateCounterclockwise()
                } label: {
                    Image(systemName: "rotate.left")
                }
                .disabled(viewModel.document == nil)
                .help("Rotate Left — view only, doesn't change the saved PDF. Search, text selection, and form fields are unavailable while rotated.")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.rotateClockwise()
                } label: {
                    Image(systemName: "rotate.right")
                }
                .disabled(viewModel.document == nil)
                .help("Rotate Right — view only, doesn't change the saved PDF. Search, text selection, and form fields are unavailable while rotated.")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.toggleTwoPageMode()
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .symbolVariant(viewModel.isTwoPageMode ? .fill : .none)
                }
                .disabled(viewModel.document == nil)
                .help("Two-Page Mode — shows pages side by side for reading. Search, text selection, and form fields are unavailable while active.")
            }

            ToolbarItem(placement: .automatic) {
                Picker("Selection Mode", selection: $viewModel.selectionMode) {
                    Label("Text", systemImage: "text.cursor").tag(SelectionMode.readingOrder)
                    Label("Area", systemImage: "rectangle.dashed").tag(SelectionMode.rectangularArea)
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.document == nil)
                .help("Selection Tool: Text Flow or Rectangular Area (Hold Option while dragging for Area)")
            }
            
            if let doc = viewModel.document {
                ToolbarItem(placement: .status) {
                    EditablePagePill(viewModel: viewModel, pageCount: doc.pageCount)
                }
            }
    }

    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let fileURL: URL?
            if let u = item as? URL {
                fileURL = u
            } else if let d = item as? Data {
                fileURL = URL(dataRepresentation: d, relativeTo: nil)
            } else {
                fileURL = nil
            }
            guard let url = fileURL, url.pathExtension.lowercased() == "pdf" else { return }
            let docPath = url.path
            Task { @MainActor in
                if self.viewModel.document == nil {
                    await self.viewModel.loadDocument(from: docPath)
                } else if let onNewTab = self.viewModel.onOpenNewTab {
                    onNewTab(url)
                } else {
                    await self.viewModel.loadDocument(from: docPath)
                }
            }
        }
        return true
    }
}

private struct SearchResultRowView: View {
    let match: SearchResult
    let isActive: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Page \(match.pageIndex + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                Spacer()
            }
            Text(match.snippet)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isActive ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.04), lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
    }
}
