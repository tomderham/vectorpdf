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
import UniformTypeIdentifiers
#if canImport(Translation)
import Translation
#endif

// Notifications used for app lifecycle events
extension Notification.Name {
    public static let openFilePathCommand = Notification.Name("openFilePathCommand")
    public static let focusSearchCommand = Notification.Name("focusSearchCommand")
    public static let focusAnchorsCommand = Notification.Name("focusAnchorsCommand")
    public static let formWidgetDidChange = Notification.Name("formWidgetDidChange")
    public static let showDocumentPropertiesCommand = Notification.Name("showDocumentPropertiesCommand")
    public static let showSplitPDFCommand = Notification.Name("showSplitPDFCommand")
    public static let showRedactionPanelCommand = Notification.Name("showRedactionPanelCommand")
    public static let showMeasurementToolbarCommand = Notification.Name("showMeasurementToolbarCommand")
    public static let calibrateScaleCommand = Notification.Name("calibrateScaleCommand")
    public static let showTakeoffSummaryCommand = Notification.Name("showTakeoffSummaryCommand")
}



/// An individual button inside a toolbar pill or group.
/// Follows standard macOS Preview button styling with hover and active selection states.
private struct PillBarButton<Label: View>: View {
    @Environment(\.controlActiveState) private var controlActiveState
    let action: () -> Void
    var isSelected: Bool = false
    var helpText: String? = nil
    @ViewBuilder let label: Label
    @State private var isHovered = false

    private var isWindowKey: Bool {
        controlActiveState == .key
    }

    var body: some View {
        let btn = Button(action: action) {
            label
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(
                    isSelected
                        ? (isWindowKey ? Color.white : (isHovered ? Color.primary : Color.secondary))
                        : (isHovered ? Color.primary : (isWindowKey ? Color.primary : Color.secondary))
                )
                .frame(width: 32, height: 28)
                .background(
                    Circle()
                        .fill(
                            isSelected
                                ? (isWindowKey ? Color.accentColor : Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                                : ((isHovered && isWindowKey) ? Color.primary.opacity(0.08) : Color.clear)
                        )
                        .frame(width: 26, height: 26)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }

        if let help = helpText {
            btn.help(help)
        } else {
            btn
        }
    }
}

/// Groups two toolbar buttons into a single capsule, matching Preview's segmented pill style.
private struct AdaptiveToolbarPair<Left: View, Right: View>: View {
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right

    var body: some View {
        ToolbarPillContainer {
            HStack(spacing: 0) {
                left

                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: 16)
                    .allowsHitTesting(false)

                right
            }
        }
    }
}

/// Standalone, reusable macOS SwiftUI PDF Document Viewer
public struct PDFViewerMainView: View {
    @StateObject public var viewModel: PDFViewerViewModel
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @ObservedObject private var appCoordinator = PDFViewerAppCoordinator.shared
    @ObservedObject private var tabGroupManager = TabGroupManager.shared
    @ObservedObject private var snapshotWindowManager = SnapshotWindowManager.shared
    private enum OverviewMode: String, CaseIterable, Identifiable {
        case outline = "Outline"
        case thumbnails = "Thumbnails"
        var id: String { rawValue }
    }

    @State private var selectedSidebarTab: Int = 0
    // Rebuilds the segmented control after initial appearance to ensure segment images render.
    @State private var sidebarModePickerRenderKey = false
    @State private var hasScheduledSidebarModePickerRebuild = false
    @State private var overviewMode: OverviewMode = .outline
    @State private var sidebarVisibility: NavigationSplitViewVisibility
    @State private var tocSearchQuery: String = ""
    @FocusState private var isAgentInputFocused: Bool
    @State private var undoToastMessage: String? = nil
    @State private var undoAction: (() -> Void)? = nil
    public let initialFilePath: String?
    public let initialTarget: SnapshotTarget?
    public let onOpenNewTab: ((URL) -> Void)?
    public let onOpenNewWindow: ((URL) -> Void)?
    /// The saved Tab Group this window was opened as an instance of, if any.
    public let groupOrigin: UUID?
    /// True only for windows opened by SnapshotWindowManager.
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
        let resolvedPath = initialURL?.path ?? initialFilePath
        self.initialFilePath = resolvedPath
        self.initialTarget = initialTarget
        self.onOpenNewTab = onOpenNewTab
        self.onOpenNewWindow = onOpenNewWindow
        self.isSnapshotWindow = isSnapshotWindow
        self.groupOrigin = groupOrigin
        self._sidebarVisibility = State(initialValue: .all)

        let initialTitle: String = {
            if let target = initialTarget {
                let name = resolvedPath != nil ? URL(fileURLWithPath: resolvedPath!).lastPathComponent : "Document"
                return "\(name) — \(target.label)"
            }
            if let path = resolvedPath {
                return URL(fileURLWithPath: path).lastPathComponent
            }
            return "VectorPDF"
        }()
        let vm = PDFViewerViewModel()
        vm.documentTitle = initialTitle
        self._viewModel = StateObject(wrappedValue: vm)
    }

    private func bannerDetailText(for target: SnapshotTarget) -> String {
        let pageLabel = "Page \(target.targetPage + 1)"
        let cleanLabel = target.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanLabel.isEmpty || cleanLabel == pageLabel {
            return "— \(pageLabel)"
        } else if cleanLabel.hasPrefix(pageLabel) {
            return "— \(cleanLabel)"
        } else {
            return "— \(pageLabel): \(cleanLabel)"
        }
    }

    /// Identifier bar for snapshot windows. Clicking it returns to the initial snapshot position.
    @ViewBuilder
    private var snapshotWindowBanner: some View {
        let isSaved = initialTarget.map { target in
            let path = viewModel.document?.filePath ?? initialFilePath ?? ""
            let inState = ReadingStateManager.shared.state(for: path)?.snapshots.contains(where: { $0.id == target.id }) ?? false
            return inState || viewModel.activeSnapshots.contains(where: { $0.id == target.id })
        } ?? false
        let bannerTitle = "Anchor"

        HStack(spacing: 8) {
            HStack(spacing: 6) {
                if isSaved {
                    Image.anchorIcon
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "macwindow.badge.plus")
                        .foregroundStyle(Color.accentColor)
                }
                Text(bannerTitle)
                    .font(.caption.weight(.semibold))
                if let target = initialTarget {
                    Text(bannerDetailText(for: target))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let target = initialTarget {
                    viewModel.jumpToSnapshot(target)
                }
            }
            .help("Click to jump back to this anchor")

            Spacer()

            SnapshotBannerCloseButton(action: {
                let current = viewModel.currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
                SnapshotWindowManager.shared.closeChildrenOfCurrentParent(for: current)
            })
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
        Divider()
    }

    /// The document canvas — identical for both the normal (sidebar) layout's `detail:`
    /// and the sidebar-less snapshot-window layout.
    @ViewBuilder
    private var documentCanvas: some View {
        PDFVirtualizedScrollView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if viewModel.isMarkupBarVisible {
                        PDFMarkupToolbarView(viewModel: viewModel)
                        Divider()
                    }
                    if viewModel.isMeasurementBarVisible {
                        PDFMeasurementToolbarView(viewModel: viewModel)
                        Divider()
                    }
                    if viewModel.isRedactionBarVisible {
                        PDFRedactionToolbarView(viewModel: viewModel)
                        Divider()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let doc = viewModel.document, doc.pageCount > 1 {
                    FloatingReaderHUD(viewModel: viewModel, pageCount: doc.pageCount)
                        .padding(.bottom, 16)
                }
            }
            .toolbarBackground(Color(nsColor: .topWindowBarColor), for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
    }

    private let maxVisibleFavorites = 5
    private let maxVisibleTabGroups = 3

    /// Start screen displayed when no document is loaded.
    @ViewBuilder
    private var startScreen: some View {
        let visibleFavorites = Array(favoritesManager.favorites.prefix(maxVisibleFavorites))
        let visibleTabGroups = Array(tabGroupManager.groups.prefix(maxVisibleTabGroups))
        let totalItems = favoritesManager.favorites.count + tabGroupManager.groups.count

        // Show recents only if space permits (total items <= 4) and recents exist
        let recentURLs: [URL] = {
            guard totalItems <= 4 else { return [] }
            let favPaths = Set(favoritesManager.favorites.map(\.path))
            return NSDocumentController.shared.recentDocumentURLs
                .filter { $0.pathExtension.lowercased() == "pdf" && !favPaths.contains($0.path) }
                .prefix(3)
                .map { $0 }
        }()

        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    HeroDropZoneView(
                        onChooseFile: {
                            viewModel.promptOpenFile()
                        },
                        onDropURLs: { urls in
                            guard let url = urls.first else { return }
                            Task { @MainActor in
                                await viewModel.loadDocument(from: url.path)
                            }
                        }
                    )
                    .padding(.top, 28)

                    if totalItems == 0 && recentURLs.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "star")
                                .font(.system(size: 20))
                                .foregroundStyle(.tertiary)
                            Text("No Favorites Yet")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text("Open a PDF and click the star in the toolbar to pin it here for quick access.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 280)
                        }
                        .padding(.top, 16)
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            if !visibleTabGroups.isEmpty {
                                startScreenSection("Tab Groups") {
                                    ForEach(visibleTabGroups) { group in
                                        StartScreenRow(
                                            title: group.name,
                                            subtitle: "\(group.documentPaths.count) tab\(group.documentPaths.count == 1 ? "" : "s")",
                                            systemImage: "square.grid.2x2",
                                            onOpen: { tabGroupManager.open(group, replacing: viewModel.currentWindow) },
                                            onRemove: {
                                                if let removed = tabGroupManager.removeGroup(group.id) {
                                                    triggerUndoToast("Deleted Tab Group \"\(group.name)\"") {
                                                        tabGroupManager.insertGroup(removed.group, at: removed.index)
                                                    }
                                                }
                                            },
                                            removeLabel: "Delete Tab Group"
                                        )
                                    }
                                    if tabGroupManager.groups.count > maxVisibleTabGroups {
                                        Text("Showing \(maxVisibleTabGroups) of \(tabGroupManager.groups.count) tab groups • See all in the Favorites menu")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.leading, 4)
                                    }
                                }
                            }

                            if !visibleFavorites.isEmpty {
                                startScreenSection("Favorites") {
                                    ForEach(visibleFavorites) { fav in
                                        let parentDir = URL(fileURLWithPath: fav.path).deletingLastPathComponent().lastPathComponent
                                        StartScreenRow(
                                            title: fav.title,
                                            subtitle: parentDir.isEmpty ? nil : parentDir,
                                            systemImage: "doc.text",
                                            filePath: fav.path,
                                            onOpen: { viewModel.openDocumentPreferringNewWindow(atPath: fav.path) },
                                            onOpenInNewTab: {
                                                if let onNewTab = viewModel.onOpenNewTab {
                                                    onNewTab(URL(fileURLWithPath: fav.path))
                                                }
                                            },
                                            onOpenInNewWindow: { viewModel.openDocumentPreferringNewWindow(atPath: fav.path) },
                                            onRemove: {
                                                if let removed = favoritesManager.removeFavorite(path: fav.path) {
                                                    triggerUndoToast("Removed \"\(fav.title)\" from Favorites") {
                                                        favoritesManager.insertFavorite(removed.document, at: removed.index)
                                                    }
                                                }
                                            },
                                            removeLabel: "Remove from Favorites"
                                        )
                                    }
                                    if favoritesManager.favorites.count > maxVisibleFavorites {
                                        Text("Showing \(maxVisibleFavorites) of \(favoritesManager.favorites.count) favorites • See all in the Favorites menu")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.leading, 4)
                                    }
                                }
                            }

                            if !recentURLs.isEmpty {
                                startScreenSection("Recent Documents") {
                                    ForEach(recentURLs, id: \.self) { url in
                                        let parentDir = url.deletingLastPathComponent().lastPathComponent
                                        StartScreenRow(
                                            title: url.lastPathComponent,
                                            subtitle: parentDir.isEmpty ? nil : parentDir,
                                            systemImage: "clock",
                                            filePath: url.path,
                                            onOpen: {
                                                Task { await viewModel.loadDocument(from: url.path) }
                                            },
                                            onOpenInNewTab: {
                                                if let onNewTab = viewModel.onOpenNewTab {
                                                    onNewTab(url)
                                                }
                                            },
                                            onOpenInNewWindow: {
                                                viewModel.openDocumentPreferringNewWindow(atPath: url.path)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: 480)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 640, idealWidth: 1150, maxWidth: .infinity, minHeight: 460, idealHeight: 780, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let msg = undoToastMessage, let action = undoAction {
                UndoToastView(message: msg) {
                    action()
                    withAnimation {
                        undoToastMessage = nil
                        undoAction = nil
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    private func triggerUndoToast(_ message: String, undo: @escaping () -> Void) {
        withAnimation {
            undoToastMessage = message
            undoAction = undo
        }
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                if undoToastMessage == message {
                    withAnimation {
                        undoToastMessage = nil
                        undoAction = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func startScreenSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                // Snapshot windows omit the sidebar.
                VStack(spacing: 0) {
                    snapshotWindowBanner
                    documentCanvas
                }
                .frame(minWidth: 600, idealWidth: 960, minHeight: 450, idealHeight: 720)
                .toolbar {
                    documentToolbarContent
                }
                .toolbarBackground(Color(nsColor: .topWindowBarColor), for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .navigationTitle("")
            } else if viewModel.document == nil {
                startScreen
                    .toolbar {
                        documentToolbarContent
                    }
                    .toolbarBackground(Color(nsColor: .topWindowBarColor), for: .windowToolbar)
                    .toolbarBackground(.visible, for: .windowToolbar)
                    .navigationTitle("")
            } else {
                navigationSplitBody
            }
        }
        .toolbarBackground(Color(nsColor: .topWindowBarColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .frame(
            minWidth: isSnapshotWindow ? 540 : 640,
            idealWidth: isSnapshotWindow ? 960 : 1440,
            maxWidth: isSnapshotWindow ? nil : .infinity,
            minHeight: isSnapshotWindow ? 420 : 480,
            idealHeight: isSnapshotWindow ? 720 : 960,
            maxHeight: isSnapshotWindow ? nil : .infinity
        )
        .background(
            WindowAccessor(
                onWindow: { window in
                    viewModel.currentWindow = window
                    viewModel.updateTitlebarHeight()
                    if viewModel.windowDelegate == nil {
                        let del = PDFViewerWindowDelegate(viewModel: viewModel)
                        viewModel.windowDelegate = del
                        window.delegate = del
                    } else if window.delegate == nil {
                        window.delegate = viewModel.windowDelegate
                    }
                    if window.isKeyWindow {
                        PDFViewerViewModel.active = viewModel
                        PDFViewerAppCoordinator.shared.registerActive(viewModel)
                    }
                    if let doc = viewModel.document {
                        window.title = viewModel.documentTitle
                        window.representedURL = URL(fileURLWithPath: doc.filePath)
                    } else {
                        window.title = "VectorPDF"
                    }
                    TabBarAppearanceHelper.refreshTabs(for: window)
                },
                onWindowAttach: { window in
                    // Apply window chrome configuration synchronously on attach.
                    window.isMovableByWindowBackground = true
                    window.titlebarAppearsTransparent = true
                    window.toolbarStyle = .unified
                    window.titleVisibility = .hidden
                    window.backgroundColor = .topWindowBarColor
                    if !isSnapshotWindow {
                        window.minSize = NSSize(width: 640, height: 480)
                        window.tabbingMode = .preferred
                        if window.tabGroup?.isTabBarVisible != true {
                            window.toggleTabBar(nil)
                        }
                    } else {
                        window.tabbingMode = .disallowed
                    }
                }
            )
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
            // Flush reading state when window closes.
            if let win = notif.object as? NSWindow, win == viewModel.currentWindow {
                viewModel.saveReadingStateIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notif in
            if let win = notif.object as? NSWindow, win == viewModel.currentWindow {
                PDFViewerViewModel.active = viewModel
                PDFViewerAppCoordinator.shared.registerActive(viewModel)
                viewModel.updateTitlebarHeight()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { notif in
            if let win = notif.object as? NSWindow, win == viewModel.currentWindow {
                viewModel.updateTitlebarHeight()
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleFileDrop)
        .onReceive(NotificationCenter.default.publisher(for: .openFilePathCommand)) { notif in
            guard viewModel.currentWindow?.isKeyWindow == true || viewModel.currentWindow == nil else { return }
            if let path = notif.object as? String {
                Task {
                    await viewModel.loadDocument(from: path)
                    if let doc = viewModel.document {
                        overviewMode = doc.outline.isEmpty ? .thumbnails : .outline
                        sidebarVisibility = doc.pageCount <= 1 ? .detailOnly : .all
                    }
                    DocumentWindowing.closeStandaloneEmptyStartWindows(except: viewModel.currentWindow)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchCommand)) { _ in
            guard viewModel.currentWindow?.isKeyWindow == true || viewModel.currentWindow == nil else { return }
            sidebarVisibility = .all
            viewModel.isSidebarVisible = true
            selectedSidebarTab = 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAnchorsCommand)) { _ in
            guard viewModel.currentWindow?.isKeyWindow == true || viewModel.currentWindow == nil else { return }
            sidebarVisibility = .all
            viewModel.isSidebarVisible = true
            selectedSidebarTab = 2
        }
        .onChange(of: viewModel.document?.filePath) { oldPath, newPath in
            guard let newPath = newPath, newPath != oldPath, let doc = viewModel.document else { return }
            overviewMode = doc.outline.isEmpty ? .thumbnails : .outline
            selectedSidebarTab = 0
            tocSearchQuery = ""
            sidebarVisibility = doc.pageCount <= 1 ? .detailOnly : .all
        }
        .onChange(of: viewModel.isTwoPageMode) { _, isTwoPage in
            withAnimation(.easeInOut(duration: 0.2)) {
                if isTwoPage {
                    sidebarVisibility = .detailOnly
                } else {
                    sidebarVisibility = (viewModel.document?.pageCount ?? 0) <= 1 ? .detailOnly : .all
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if isTwoPage {
                    viewModel.zoomToFitWidth()
                }
            }
        }
        .onChange(of: sidebarVisibility) { _, newVisibility in
            let isVisible = (newVisibility != .detailOnly)
            if viewModel.isSidebarVisible != isVisible {
                viewModel.isSidebarVisible = isVisible
            }
        }
        .onChange(of: viewModel.isSidebarVisible) { _, isVisible in
            let targetVisibility: NavigationSplitViewVisibility = isVisible ? .all : .detailOnly
            if sidebarVisibility != targetVisibility {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarVisibility = targetVisibility
                }
            }
        }
        .modifier(ViewerSheetsModifier(viewModel: viewModel))
        .task {
            // Check for buffered cold-launch open-file path.
            if let path = initialFilePath ?? PDFViewerAppCoordinator.shared.consumePendingOpenFilePath() {
                await viewModel.loadDocument(from: path)
                if let target = initialTarget {
                    viewModel.jumpToSnapshot(target)
                }
                if let doc = viewModel.document {
                    overviewMode = doc.outline.isEmpty ? .thumbnails : .outline
                    sidebarVisibility = doc.pageCount <= 1 ? .detailOnly : .all
                }
                DocumentWindowing.closeStandaloneEmptyStartWindows(except: viewModel.currentWindow)
            }
        }
        .modifier(TranslationPresentationHelper(viewModel: viewModel))
        .overlay {
            if viewModel.isDownloadingFromCloud {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "icloud.and.arrow.down.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.accentColor)
                        Text(viewModel.cloudDownloadStatusMessage ?? "Downloading from iCloud Drive…")
                            .font(.headline)
                        ProgressView()
                            .controlSize(.regular)
                        Button("Cancel") {
                            viewModel.cancelCloudDownload()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 10)
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var navigationSplitBody: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            // Sidebar
            VStack(spacing: 0) {
                HStack {
                    Picker("Sidebar Mode", selection: $selectedSidebarTab) {
                        Image(systemName: "list.bullet")
                            .imageScale(.medium)
                            .tag(0)
                            .help("Outline & Thumbnails")
                        Image(systemName: "magnifyingglass")
                            .imageScale(.medium)
                            .tag(1)
                            .help("Search Document (Cmd+F)")
                        Image.anchorIcon
                            .imageScale(.medium)
                            .tag(2)
                            .help("Anchors")
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
                    .segmentedControlTooltips([
                        "Outline & Thumbnails",
                        "Search Document (Cmd+F)",
                        "Anchors"
                    ] + (appCoordinator.showAgentTab ? ["Ask About This Document"] : []))
                    .onChange(of: selectedSidebarTab) { _, newValue in
                        if newValue == 3 {
                            viewModel.startAgentIndexingIfNeeded()
                        }
                    }
                    .onChange(of: viewModel.agentIndexState) { _, newState in
                        // Rebuild index on content change if Agent tab is visible.
                        if newState == .idle && selectedSidebarTab == 3 {
                            viewModel.startAgentIndexingIfNeeded()
                        }
                    }
                    .onChange(of: appCoordinator.showAgentTab) { _, stillShown in
                        // Fall back to Table of Contents if selected sidebar tab becomes unavailable.
                        if !stillShown && selectedSidebarTab == 3 {
                            selectedSidebarTab = 0
                        }
                    }
                    .id(sidebarModePickerRenderKey)
                    .onAppear {
                        guard !hasScheduledSidebarModePickerRebuild else { return }
                        hasScheduledSidebarModePickerRebuild = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            sidebarModePickerRenderKey.toggle()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)

                Divider()
                
                if selectedSidebarTab == 0 {
                    // Outline & Thumbnails Tab
                    if let doc = viewModel.document {
                        if doc.outline.isEmpty {
                            PDFThumbnailGridView(viewModel: viewModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            VStack(spacing: 0) {
                                Picker("Overview Mode", selection: $overviewMode) {
                                    Text("Outline").tag(OverviewMode.outline)
                                    Text("Thumbnails").tag(OverviewMode.thumbnails)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .controlSize(.small)
                                .segmentedControlTooltips(["Outline", "Thumbnails"])
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)

                                Divider()

                                if overviewMode == .outline {
                                    HStack(spacing: 6) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)

                                        TextField("Search outline...", text: $tocSearchQuery)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 11))

                                        if !tocSearchQuery.isEmpty {
                                            Button {
                                                tocSearchQuery = ""
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color(nsColor: .controlBackgroundColor))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                    )
                                    .padding(.horizontal, 10)
                                    .padding(.top, 4)
                                    .padding(.bottom, 6)

                                    Divider()

                                    PDFOutlineNSView(
                                        outline: doc.outline,
                                        // Rebuild outline on page edits.
                                        documentIdentity: "\(doc.filePath)#\(viewModel.thumbnailVersion)",
                                        searchQuery: tocSearchQuery,
                                        currentPage: viewModel.currentPageIndex,
                                        viewModel: viewModel
                                    ) { targetPage in
                                        viewModel.jumpToPage(targetPage)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
                                    PDFThumbnailGridView(viewModel: viewModel)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        ContentUnavailableView("No Document", systemImage: "doc", description: Text("No document is currently open"))
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

                        if viewModel.isRunningOCR {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Recognizing text in scanned pages...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .cornerRadius(6)
                            .padding(.horizontal, 8)
                        } else if !viewModel.detectedScannedPages.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "text.viewfinder")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(viewModel.detectedScannedPages.count) scanned page(s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Run OCR") {
                                    Task {
                                        await viewModel.runOCROnAllScannedPages()
                                    }
                                }
                                .buttonStyle(.borderless)
                                .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .cornerRadius(6)
                            .padding(.horizontal, 8)
                        }
                        let hasQuery = !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        let shouldShowCount = !viewModel.searchResults.isEmpty || (hasQuery && !viewModel.isSearching && !viewModel.isRunningOCR)
                        if shouldShowCount {
                            HStack {
                                Text(viewModel.searchResults.isEmpty ? "0 results" : "\(viewModel.activeSearchMatchIndex + 1) of \(viewModel.searchResults.count)")
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
                                
                                if !viewModel.searchResults.isEmpty {
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
                            }
                            .padding(.horizontal, 8)
                        }
                        
                        Divider()
                        
                        // Use ScrollView/LazyVStack to avoid table view reentrancy while search results stream in.
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 3) {
                                    ForEach(viewModel.searchPageGroups) { group in
                                        SearchPageSeparatorView(
                                            pageIndex: group.pageIndex,
                                            count: group.matches.count
                                        )
                                        
                                        ForEach(group.matches) { match in
                                            SearchResultRowView(
                                                match: match,
                                                isActive: viewModel.isActiveMatch(match)
                                            )
                                            .onTapGesture {
                                                DispatchQueue.main.async {
                                                    viewModel.navigateToMatch(match, shouldScrollList: false)
                                                }
                                            }
                                            .contextMenu {
                                                Button {
                                                    viewModel.addSnapshot(from: match)
                                                } label: {
                                                    Label {
                                                        Text("Create Anchor")
                                                    } icon: {
                                                        Image.anchorIcon
                                                    }
                                                }

                                                Button {
                                                    viewModel.addSnapshotAndOpenInNewWindow(from: match)
                                                } label: {
                                                    Label {
                                                        Text("Create Anchor and Open in New Window")
                                                    } icon: {
                                                        Image.anchorIcon
                                                    }
                                                }

                                                Divider()

                                                Button {
                                                    viewModel.openSnapshotInNewWindow(from: match)
                                                } label: {
                                                    Label("Open in New Window", systemImage: "macwindow.badge.plus")
                                                }
                                            }
                                            .id(match.id)
                                        }
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
                    // Anchors Tab
                    VStack(spacing: 0) {
                        if viewModel.activeSnapshots.isEmpty {
                            ContentUnavailableView {
                                Label {
                                    Text("No Anchors")
                                } icon: {
                                    Image.anchorIcon
                                }
                            } description: {
                                Text("Select text, or hold ⌥ while dragging to lasso an area, to create an anchor.")
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            HStack {
                                Text("\(viewModel.activeSnapshots.count) Anchor\(viewModel.activeSnapshots.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    viewModel.addAnchorForCurrentPage()
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Add Anchor (⌘B)")

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

                            Divider()

                            HStack(alignment: .top, spacing: 5) {
                                Image(systemName: "info.circle")
                                    .font(.caption2)
                                    .padding(.top, 1)
                                Text("Select text, or hold ⌥ while dragging to lasso an area, to create an anchor.")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if selectedSidebarTab == 3 {
                    // Agent Tab: semantic search and on-device synthesis for the current document.
                    VStack(spacing: 0) {
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
                                                            Text(LocalizedStringKey(formatAgentAnswerCitations(turn.answerText)))
                                                                .font(.callout)
                                                                .textSelection(.enabled)
                                                                .environment(\.openURL, OpenURLAction { url in
                                                                    if url.scheme == "pdfpage", let host = url.host, let pageNum = Int(host), pageNum > 0 {
                                                                        viewModel.jumpToPage(pageNum - 1)
                                                                        return .handled
                                                                    }
                                                                    return .systemAction
                                                                })
                                                        } else if let error = turn.errorMessage {
                                                            Text(error)
                                                                .font(.caption)
                                                                .foregroundStyle(.orange)
                                                        } else if turn.passages.isEmpty {
                                                            Text("No relevant passages found.")
                                                                .font(.caption)
                                                                .foregroundStyle(.secondary)
                                                        } else if turn.providerUsed != nil {
                                                            // Handle empty synthesis response.
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
                                                            let citedPages = extractCitedPageIndices(from: turn.answerText)
                                                            DisclosureGroup("Sources (\(turn.passages.count))") {
                                                                VStack(alignment: .leading, spacing: 6) {
                                                                    ForEach(turn.passages) { passage in
                                                                        AgentSourcePassageView(
                                                                            passage: passage,
                                                                            isCited: citedPages.contains(passage.pageIndex)
                                                                        ) {
                                                                            viewModel.jumpToPage(passage.pageIndex)
                                                                        }
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
                                        // Animate only when appending new turn, not during streaming chunks.
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
                                    Text("Ask anything…")
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
                                    .onKeyPress(phases: .down) { keyPress in
                                        guard keyPress.key == .return else { return .ignored }
                                        if keyPress.modifiers.contains(.shift) || keyPress.modifiers.contains(.option) {
                                            return .ignored
                                        }
                                        submitAgentQuestionIfPossible()
                                        return .handled
                                    }
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
                                    submitAgentQuestionIfPossible()
                                }
                                .help("Send (Return, Shift+Return for newline)")
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
            // Extend sidebar material through toolbar region.
            .toolbarBackground(.hidden, for: .windowToolbar)
        } detail: {
            documentCanvas
        }
        .toolbar {
            documentToolbarContent
        }
        .toolbarBackground(Color(nsColor: .topWindowBarColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .navigationTitle("")
    }

    @ToolbarContentBuilder
    private var documentToolbarContent: some ToolbarContent {
            ToolbarItem(placement: .navigation) {
                ToolbarTitleView(viewModel: viewModel)
            }

            ToolbarItem(placement: .automatic) {
                EditableZoomField(viewModel: viewModel)
                    .disabled(viewModel.document == nil)
            }
            
            // Rotate group
            ToolbarItem(placement: .automatic) {
                AdaptiveToolbarPair {
                    PillBarButton(action: {
                        viewModel.rotateCounterclockwise()
                    }, helpText: "Rotate Left — view only, doesn't change the saved PDF.") {
                        Image(systemName: "rotate.left")
                    }
                } right: {
                    PillBarButton(action: {
                        viewModel.rotateClockwise()
                    }, helpText: "Rotate Right — view only, doesn't change the saved PDF.") {
                        Image(systemName: "rotate.right")
                    }
                }
                .disabled(viewModel.document == nil)
            }

            ToolbarItem(placement: .automatic) {
                ToolbarPillContainer {
                    PillBarButton(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.toggleTwoPageMode()
                        }
                    }, isSelected: viewModel.isTwoPageMode, helpText: "Two-Page Mode — shows pages side by side in book spread format with cover page on the right. Search, text selection, and form fields are unavailable while active.") {
                        Image(systemName: "rectangle.split.2x1")
                    }
                }
                .disabled(viewModel.document == nil)
            }

            // Markup / Measurement toggle group
            ToolbarItem(placement: .automatic) {
                AdaptiveToolbarPair {
                    PillBarButton(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.isMarkupBarVisible.toggle()
                        }
                    }, isSelected: viewModel.isMarkupBarVisible, helpText: "Markup Toolbar (⇧⌘A)") {
                        Image(systemName: "pencil.tip.crop.circle")
                    }
                } right: {
                    PillBarButton(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.toggleMeasurementBar()
                        }
                    }, isSelected: viewModel.isMeasurementBarVisible, helpText: "Measurement Toolbar (⇧⌘M)") {
                        Image(systemName: "ruler")
                    }
                }
                .disabled(viewModel.document == nil)
            }
            
            if let doc = viewModel.document {
                ToolbarItem(placement: .status) {
                    EditablePagePill(viewModel: viewModel, pageCount: doc.pageCount)
                }
            }
    }

    private func submitAgentQuestionIfPossible() {
        guard !viewModel.agentQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              viewModel.agentIndexState == .ready,
              !viewModel.agentIsAnswering else { return }
        viewModel.askAgentQuestion()
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

private struct SearchPageSeparatorView: View {
    let pageIndex: Int
    let count: Int
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            
            Text("Page \(pageIndex + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primary)
            
            Spacer()
            
            Text("\(count) \(count == 1 ? "item" : "items")")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

private struct SearchResultRowView: View {
    let match: SearchResult
    let isActive: Bool
    
    var body: some View {
        Text(match.snippet)
            .font(.caption)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isActive ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 0.75)
                    )
            )
            .contentShape(Rectangle())
    }
}

/// Converts citation references like `[Page 4]`, `[Pages 4-5]`, or `[p. 4]` into clickable markdown links `[Page 4](pdfpage://4)`.
public func formatAgentAnswerCitations(_ text: String) -> String {
    let pattern = #"(?i)\[(?:pages?|pp?\.)\s*(\d+)(?:[–-]\d+)?\]"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "[Page $1](pdfpage://$1)")
}

/// Extracts the unique 0-indexed page indices cited in the text (e.g. "[Page 4]" -> 3).
public func extractCitedPageIndices(from text: String) -> Set<Int> {
    let pattern = #"(?i)\[(?:pages?|pp?\.)\s*(\d+)(?:[–-]\d+)?\]"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = regex.matches(in: text, options: [], range: range)
    var pages = Set<Int>()
    for match in matches {
        if match.numberOfRanges >= 2, let r = Range(match.range(at: 1), in: text), let p = Int(text[r]), p > 0 {
            pages.insert(p - 1)
        }
    }
    return pages
}

private struct AgentSourcePassageView: View {
    let passage: AgentPassage
    var isCited: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Page \(passage.pageIndex + 1)")
                        .font(.caption.bold())
                    if isCited {
                        Text("Cited")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
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
                .fill(isCited ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isCited ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

private struct SnapshotBannerCloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "xmark.rectangle")
                Text("Close all Child Windows")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(isHovered ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(isHovered ? 0.12 : 0.06))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Close all anchor windows opened from the parent document")
    }
}

private struct ViewerSheetsModifier: ViewModifier {
    @ObservedObject var viewModel: PDFViewerViewModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $viewModel.isShowingDocumentProperties) {
                PDFDocumentPropertiesView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isShowingSplitPDF) {
                PDFSplitPDFView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isShowingCalibrationSheet) {
                ScaleCalibrationSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isShowingTakeoffTable) {
                TakeoffSummaryView(viewModel: viewModel)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showDocumentPropertiesCommand)) { _ in
                guard viewModel.currentWindow?.isKeyWindow == true || viewModel.currentWindow == nil else { return }
                viewModel.showDocumentProperties()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSplitPDFCommand)) { _ in
                guard viewModel.currentWindow?.isKeyWindow == true || viewModel.currentWindow == nil else { return }
                viewModel.showSplitPDF()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showRedactionPanelCommand)) { _ in
                guard viewModel.currentWindow?.isKeyWindow == true || viewModel.currentWindow == nil else { return }
                viewModel.toggleRedactionBar()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showMeasurementToolbarCommand)) { _ in
                guard viewModel.currentWindow?.isKeyWindow == true || viewModel.currentWindow == nil else { return }
                viewModel.toggleMeasurementBar()
            }
            .onReceive(NotificationCenter.default.publisher(for: .calibrateScaleCommand)) { _ in
                guard viewModel.currentWindow?.isKeyWindow == true || viewModel.currentWindow == nil else { return }
                viewModel.isShowingCalibrationSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showTakeoffSummaryCommand)) { _ in
                guard viewModel.currentWindow?.isKeyWindow == true || viewModel.currentWindow == nil else { return }
                viewModel.isShowingTakeoffTable = true
            }
    }
}

private struct TranslationPresentationHelper: ViewModifier {
    @ObservedObject var viewModel: PDFViewerViewModel

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            content
                .translationPresentation(
                    isPresented: $viewModel.isPresentingTranslation,
                    text: viewModel.translationTargetText ?? ""
                )
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Principal toolbar title view displaying the compact document name with right-click context menu
public struct ToolbarTitleView: NSViewRepresentable {
    @Environment(\.controlActiveState) private var controlActiveState
    @ObservedObject var viewModel: PDFViewerViewModel

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }

    private var isWindowKey: Bool {
        controlActiveState == .key
    }

    public func makeNSView(context: Context) -> TitleContainerView {
        let view = TitleContainerView()
        view.viewModel = viewModel
        view.updateTitle(viewModel.documentTitle)
        view.updateFocusState(isKey: isWindowKey)
        return view
    }

    public func updateNSView(_ nsView: TitleContainerView, context: Context) {
        nsView.viewModel = viewModel
        nsView.updateTitle(viewModel.documentTitle)
        nsView.updateFocusState(isKey: isWindowKey)
    }
}

public final class TitleContainerView: NSControl {
    weak var viewModel: PDFViewerViewModel?
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setup() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.font = NSFont.systemFont(ofSize: 13.0, weight: .bold)
        titleLabel.textColor = .textColor
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    func updateFocusState(isKey: Bool) {
        titleLabel.textColor = isKey ? .textColor : .secondaryLabelColor
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            updateFocusState(isKey: window.isKeyWindow)
            NotificationCenter.default.addObserver(self, selector: #selector(handleWindowFocusChange), name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(handleWindowFocusChange), name: NSWindow.didResignKeyNotification, object: window)
        }
    }

    @objc private func handleWindowFocusChange(_ notification: Notification) {
        updateFocusState(isKey: window?.isKeyWindow ?? false)
    }

    func updateTitle(_ title: String) {
        titleLabel.stringValue = title
        toolTip = viewModel?.document?.filePath ?? title
        invalidateIntrinsicContentSize()
    }

    public override var intrinsicContentSize: NSSize {
        let labelSize = titleLabel.intrinsicContentSize
        let maxWidth: CGFloat = 380
        let width = min(max(labelSize.width + 12, 40), maxWidth)
        return NSSize(width: width, height: 28)
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(point) {
            return self
        }
        return nil
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        DocumentContextMenuHelper.buildMenu(for: viewModel)
    }

    public override func rightMouseDown(with event: NSEvent) {
        if let menu = DocumentContextMenuHelper.buildMenu(for: viewModel) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

/// Helper that builds the standard document / tab-group / favorites context menu for toolbar and titlebar right-clicks.
@MainActor
public enum DocumentContextMenuHelper {
    public static func buildMenu(for viewModel: PDFViewerViewModel?) -> NSMenu? {
        guard let viewModel else { return nil }
        let menu = NSMenu(title: "Document")

        if let groupOrigin = viewModel.groupOrigin, let group = TabGroupManager.shared.group(withId: groupOrigin) {
            let item = NSMenuItem(title: "Update Group “\(group.name)” with Open Tabs", action: #selector(ActionTarget.handleUpdateGroup(_:)), keyEquivalent: "")
            item.target = ActionTarget.shared
            item.representedObject = viewModel
            if let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil) {
                item.image = image
            }
            menu.addItem(item)
        }

        if viewModel.currentWindowTabCount > 1 {
            let item = NSMenuItem(title: "Save All Open Tabs as a Group...", action: #selector(ActionTarget.handleSaveTabsAsGroup(_:)), keyEquivalent: "")
            item.target = ActionTarget.shared
            item.representedObject = viewModel
            if let image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: nil) {
                item.image = image
            }
            menu.addItem(item)
        }

        if let doc = viewModel.document {
            let isFav = FavoritesManager.shared.isFavorite(path: doc.filePath)
            let favTitle = isFav ? "Remove This PDF from Favorites" : "Add This PDF to Favorites"
            let item = NSMenuItem(title: favTitle, action: #selector(ActionTarget.handleToggleFavorite(_:)), keyEquivalent: "")
            item.target = ActionTarget.shared
            item.representedObject = viewModel
            if let image = NSImage(systemSymbolName: isFav ? "star.slash" : "star", accessibilityDescription: nil) {
                item.image = image
            }
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let tabGroups = TabGroupManager.shared.groups
        let tabGroupsMenu = NSMenu(title: "Tab Groups")
        let tabGroupsItem = NSMenuItem(title: "Tab Groups", action: nil, keyEquivalent: "")
        tabGroupsItem.submenu = tabGroupsMenu

        if tabGroups.isEmpty {
            let emptyItem = NSMenuItem(title: "No Saved Tab Groups", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            tabGroupsMenu.addItem(emptyItem)
        } else {
            for group in tabGroups {
                let groupSubmenu = NSMenu(title: group.name)
                let groupItem = NSMenuItem(title: "\(group.name) (\(group.documentPaths.count))", action: nil, keyEquivalent: "")
                groupItem.submenu = groupSubmenu

                let openItem = NSMenuItem(title: "Open", action: #selector(ActionTarget.handleOpenGroup(_:)), keyEquivalent: "")
                openItem.target = ActionTarget.shared
                openItem.representedObject = group
                groupSubmenu.addItem(openItem)

                let deleteItem = NSMenuItem(title: "Delete Tab Group", action: #selector(ActionTarget.handleDeleteGroup(_:)), keyEquivalent: "")
                deleteItem.target = ActionTarget.shared
                deleteItem.representedObject = group
                groupSubmenu.addItem(deleteItem)

                tabGroupsMenu.addItem(groupItem)
            }
        }
        menu.addItem(tabGroupsItem)

        let favorites = FavoritesManager.shared.favorites
        let favsMenu = NSMenu(title: "Favorites")
        let favsItem = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
        favsItem.submenu = favsMenu

        if favorites.isEmpty {
            let emptyItem = NSMenuItem(title: "No Favorites Added", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            favsMenu.addItem(emptyItem)
        } else {
            for fav in favorites {
                let favSubmenu = NSMenu(title: fav.title)
                let singleFavItem = NSMenuItem(title: fav.title, action: nil, keyEquivalent: "")
                singleFavItem.submenu = favSubmenu

                let openItem = NSMenuItem(title: "Open", action: #selector(ActionTarget.handleOpenFavorite(_:)), keyEquivalent: "")
                openItem.target = ActionTarget.shared
                openItem.representedObject = (fav.path, viewModel)
                favSubmenu.addItem(openItem)

                let removeItem = NSMenuItem(title: "Remove from Favorites", action: #selector(ActionTarget.handleRemoveFavorite(_:)), keyEquivalent: "")
                removeItem.target = ActionTarget.shared
                removeItem.representedObject = fav.path
                favSubmenu.addItem(removeItem)

                favsMenu.addItem(singleFavItem)
            }
        }
        menu.addItem(favsItem)

        return menu
    }

    @MainActor
    private final class ActionTarget: NSObject {
        static let shared = ActionTarget()

        @objc func handleUpdateGroup(_ sender: NSMenuItem) {
            guard let vm = sender.representedObject as? PDFViewerViewModel else { return }
            vm.updateGroupFromCurrentTabs()
        }

        @objc func handleSaveTabsAsGroup(_ sender: NSMenuItem) {
            guard let vm = sender.representedObject as? PDFViewerViewModel else { return }
            vm.promptSaveCurrentWindowAsGroup()
        }

        @objc func handleToggleFavorite(_ sender: NSMenuItem) {
            guard let vm = sender.representedObject as? PDFViewerViewModel,
                  let doc = vm.document else { return }
            FavoritesManager.shared.toggleFavorite(path: doc.filePath, title: vm.documentTitle)
        }

        @objc func handleOpenGroup(_ sender: NSMenuItem) {
            guard let group = sender.representedObject as? TabGroup else { return }
            TabGroupManager.shared.open(group, replacing: PDFViewerViewModel.active?.currentWindow)
        }

        @objc func handleDeleteGroup(_ sender: NSMenuItem) {
            guard let group = sender.representedObject as? TabGroup else { return }
            TabGroupManager.shared.removeGroup(group.id)
        }

        @objc func handleOpenFavorite(_ sender: NSMenuItem) {
            if let (path, vm) = sender.representedObject as? (String, PDFViewerViewModel) {
                vm.openDocumentPreferringNewWindow(atPath: path)
            } else if let path = sender.representedObject as? String {
                PDFViewerViewModel.active?.openDocumentPreferringNewWindow(atPath: path)
            }
        }

        @objc func handleRemoveFavorite(_ sender: NSMenuItem) {
            guard let path = sender.representedObject as? String else { return }
            FavoritesManager.shared.removeFavorite(path: path)
        }
    }
}
