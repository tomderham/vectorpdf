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

/// How PDF page content renders relative to the app's own light/dark UI theme (which always
/// follows the system) — see PDFViewerAppCoordinator.pdfColorAppearance.
public enum PDFColorAppearance: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark
    case sepia

    public var displayName: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .sepia: return "Sepia"
        }
    }
}

/// Information about an installed web browser for opening external links.
public struct InstalledBrowser: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let appURL: URL?

    public init(id: String, name: String, appURL: URL? = nil) {
        self.id = id
        self.name = name
        self.appURL = appURL
    }
}

/// Backend preference for Agent synthesis.
public enum AgentSynthesisPreference: String, CaseIterable, Codable, Sendable {
    case onDevice
    case privateCloudCompute
    /// An OpenAI-compatible service with the person's own API key (see OnlineModelService).
    case onlineModel

    public var displayName: String {
        switch self {
        case .onDevice: return "On-Device"
        case .privateCloudCompute: return "Private Cloud Compute"
        case .onlineModel: return "Online Model (your API key)"
        }
    }
}

/// Defines how 100% scale is interpreted, matching macOS Preview settings:
/// - physical: "Size on screen equals size on printout" (Preview default)
/// - pointToPoint: "1 point equals 1 screen point" (72 DPI)
public enum PDFScaleMode: String, CaseIterable, Codable, Sendable {
    case physical
    case pointToPoint

    public var displayName: String {
        switch self {
        case .physical: return "Size on Screen Equals Size on Printout"
        case .pointToPoint: return "1 Point Equals 1 Screen Point"
        }
    }
}

/// Global coordinator that tracks the active PDF document and publishes updates to SwiftUI App menus.
@MainActor
public final class PDFViewerAppCoordinator: ObservableObject {
    public static let shared = PDFViewerAppCoordinator()

    private weak var _activeViewModel: PDFViewerViewModel?
    public var activeViewModel: PDFViewerViewModel? {
        get { _activeViewModel }
        set {
            // Avoid redundant publishing if active view model has not changed
            guard _activeViewModel !== newValue else { return }
            objectWillChange.send()
            _activeViewModel = newValue
            updateDocumentStatus()
        }
    }

    @Published public var hasActiveDocument: Bool = false
    /// Whether the active document has unsaved changes, for File > Revert to Saved.
    @Published public var isActiveDocumentEdited: Bool = false
    @Published public var documentTitle: String = ""
    @Published public var canZoomIn: Bool = false
    @Published public var canZoomOut: Bool = false
    @Published public var hasActiveSelection: Bool = false
    /// Whether the active document has layers annotations can go on, for Edit > Rename and
    /// Delete Layer.
    @Published public var hasActiveLayers: Bool = false
    /// Whether the active document is a PDF with scanned pages, for File > Save with Recognized Text.
    @Published public var canSaveActiveRecognizedText: Bool = false
    @Published public var isSpeaking: Bool = false
    /// Published live anchors list of the active document, updating SwiftUI Commands immediately.
    @Published public var activeAnchors: [SnapshotTarget] = []
    /// Bumped whenever a document is opened to signal SwiftUI Commands to refresh recent documents.
    @Published public var recentDocumentsRevision: Int = 0
    /// Global appearance override for rendered PDF content.
    @Published public var pdfColorAppearance: PDFColorAppearance = .system {
        didSet {
            UserDefaults.standard.set(pdfColorAppearance.rawValue, forKey: Self.pdfColorAppearanceKey)
        }
    }
    private static let pdfColorAppearanceKey = "com.thomasderham.vectorpdf.pdfColorAppearance"

    /// Controls visibility of the Agent sidebar tab.
    @Published public var showAgentTab: Bool = true {
        didSet {
            UserDefaults.standard.set(showAgentTab, forKey: Self.showAgentTabKey)
        }
    }
    private static let showAgentTabKey = "com.thomasderham.vectorpdf.showAgentTab"

    /// Backend synthesis preference for Agent questions.
    @Published public var agentSynthesisPreference: AgentSynthesisPreference = .onDevice {
        didSet {
            UserDefaults.standard.set(agentSynthesisPreference.rawValue, forKey: Self.agentSynthesisPreferenceKey)
        }
    }
    private static let agentSynthesisPreferenceKey = "com.thomasderham.vectorpdf.agentSynthesisPreference"

    /// Service used by the online model engine. Its API key is in the keychain (APIKeyStore).
    @Published public var onlineModelService: OnlineModelService = .openAI {
        didSet {
            UserDefaults.standard.set(onlineModelService.rawValue, forKey: Self.onlineModelServiceKey)
        }
    }
    private static let onlineModelServiceKey = "com.thomasderham.vectorpdf.onlineModelService"

    /// Chosen model name for each service, keyed by OnlineModelService raw value.
    @Published public var onlineModelNames: [String: String] = [:] {
        didSet {
            UserDefaults.standard.set(onlineModelNames, forKey: Self.onlineModelNamesKey)
        }
    }
    private static let onlineModelNamesKey = "com.thomasderham.vectorpdf.onlineModelNames"

    /// The online model to use, or nil until a model and an API key are set for the chosen service.
    public var onlineModelConfiguration: OnlineModelConfiguration? {
        let service = onlineModelService
        guard let model = onlineModelNames[service.rawValue], !model.isEmpty,
              let key = APIKeyStore.key(for: service) else { return nil }
        return OnlineModelConfiguration(service: service, model: model, apiKey: key)
    }

    // MARK: Aids for working on the page: status bar, rulers, guides, grid and navigator

    /// The strip under the page with the pointer's position, the page's size and the figures of
    /// a measurement being drawn. Off unless chosen, so reading stays uncluttered.
    @Published public var showsStatusBar = false {
        didSet { UserDefaults.standard.set(showsStatusBar, forKey: Self.showsStatusBarKey) }
    }
    /// The units of the status bar, rulers, grid and Inspector.
    @Published public var readoutUnit: ReadoutUnit = Locale.current.measurementSystem == .us ? .inches : .millimeters {
        didSet { UserDefaults.standard.set(readoutUnit.rawValue, forKey: Self.readoutUnitKey) }
    }
    @Published public var showsRulers = false {
        didSet { UserDefaults.standard.set(showsRulers, forKey: Self.showsRulersKey) }
    }
    @Published public var showsGrid = false {
        didSet { UserDefaults.standard.set(showsGrid, forKey: Self.showsGridKey) }
    }
    /// Points between the grid's lines.
    @Published public var gridSpacing: Double = Locale.current.measurementSystem == .us ? 36 : 72 / 25.4 * 10 {
        didSet { UserDefaults.standard.set(gridSpacing, forKey: Self.gridSpacingKey) }
    }
    /// Whether measuring and drawing snap to guides, and to the grid while it shows.
    @Published public var snapsToGuidesAndGrid = true {
        didSet { UserDefaults.standard.set(snapsToGuidesAndGrid, forKey: Self.snapsToGuidesAndGridKey) }
    }
    /// The miniature of the page with the part on screen, for finding your way at high zoom.
    @Published public var showsNavigator = false {
        didSet { UserDefaults.standard.set(showsNavigator, forKey: Self.showsNavigatorKey) }
    }
    /// Whether the sidebar's Document tab lists form fields, links and named destinations.
    /// Off by default: most documents have links, and a form being filled in doesn't need its
    /// fields listed, so the tab would appear for nearly everything.
    @Published public var showsDocumentStructureInSidebar = false {
        didSet { UserDefaults.standard.set(showsDocumentStructureInSidebar, forKey: Self.showsDocumentStructureKey) }
    }
    private static let showsDocumentStructureKey = "com.thomasderham.vectorpdf.showsDocumentStructureInSidebar"
    private static let showsStatusBarKey = "com.thomasderham.vectorpdf.showsStatusBar"
    private static let readoutUnitKey = "com.thomasderham.vectorpdf.readoutUnit"
    private static let showsRulersKey = "com.thomasderham.vectorpdf.showsRulers"
    private static let showsGridKey = "com.thomasderham.vectorpdf.showsGrid"
    private static let gridSpacingKey = "com.thomasderham.vectorpdf.gridSpacing"
    private static let snapsToGuidesAndGridKey = "com.thomasderham.vectorpdf.snapsToGuidesAndGrid"
    private static let showsNavigatorKey = "com.thomasderham.vectorpdf.showsNavigator"

    private func restoreWorkingAids() {
        let defaults = UserDefaults.standard
        func bool(_ key: String) -> Bool? { defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key) }
        if let value = bool(Self.showsStatusBarKey) { showsStatusBar = value }
        if let raw = defaults.string(forKey: Self.readoutUnitKey), let unit = ReadoutUnit(rawValue: raw) { readoutUnit = unit }
        if let value = bool(Self.showsRulersKey) { showsRulers = value }
        if let value = bool(Self.showsGridKey) { showsGrid = value }
        if defaults.object(forKey: Self.gridSpacingKey) != nil {
            let spacing = defaults.double(forKey: Self.gridSpacingKey)
            if spacing.isFinite, spacing >= 1, spacing <= 2000 { gridSpacing = spacing }
        }
        if let value = bool(Self.snapsToGuidesAndGridKey) { snapsToGuidesAndGrid = value }
        if let value = bool(Self.showsNavigatorKey) { showsNavigator = value }
        if let value = bool(Self.showsDocumentStructureKey) { showsDocumentStructureInSidebar = value }
    }

    /// Defines how 100% scale is interpreted. Defaults to .physical ("Size on screen equals size on printout", matching Preview).
    @Published public var scaleMode: PDFScaleMode = .physical {
        didSet {
            UserDefaults.standard.set(scaleMode.rawValue, forKey: Self.scaleModeKey)
        }
    }
    private static let scaleModeKey = "com.thomasderham.vectorpdf.scaleMode"

    /// Computes the physical display scale factor (points per inch / 72.0) for a given screen.
    /// On a Retina MacBook (127.5 DPI), this returns ~1.77. On a 109 DPI display, ~1.51.
    public static func physicalScale(for screen: NSScreen?) -> CGFloat {
        guard let screen = screen else { return 1.0 }
        guard let screenNum = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return 1.0
        }
        let mmSize = CGDisplayScreenSize(screenNum)
        guard mmSize.width > 0 else { return 1.0 }
        let inchWidth = mmSize.width / 25.4
        let pointsWidth = screen.frame.width
        guard inchWidth > 0 else { return 1.0 }
        let pointsDPI = Double(pointsWidth) / inchWidth
        let scale = pointsDPI / 72.0
        return max(0.5, CGFloat(scale))
    }

    private var docCancellable: AnyCancellable?

    /// Set by AppDelegate when macOS asks the app to open a file (Finder double-click, Dock drop,
    /// `open` command) before `applicationDidFinishLaunching` has run — that method consumes this
    /// to open straight into the requested document instead of an empty start window. On an
    /// already-running app, the equivalent open request is handled live instead (no window to
    /// race against), via `DocumentWindowing.openDocumentHandlingEmptyStart`.
    public var pendingOpenFilePath: String?

    /// Reads and clears `pendingOpenFilePath` in one step, so only the first window to check it
    /// consumes it.
    public func consumePendingOpenFilePath() -> String? {
        defer { pendingOpenFilePath = nil }
        return pendingOpenFilePath
    }

    /// Further files from the same cold-launch open request (several PDFs opened together from
    /// Finder), opened once the first window exists.
    public var pendingAdditionalOpenFilePaths: [String] = []

    /// Buffers a file opened before launch finished: the first becomes `pendingOpenFilePath`,
    /// any others queue up behind it instead of replacing it.
    public func enqueuePendingOpenFilePath(_ path: String) {
        if pendingOpenFilePath == nil {
            pendingOpenFilePath = path
        } else {
            pendingAdditionalOpenFilePaths.append(path)
        }
    }

    /// Preferred browser bundle identifier for opening external links ("system" uses macOS default).
    @Published public var preferredBrowserBundleID: String = "system" {
        didSet {
            UserDefaults.standard.set(preferredBrowserBundleID, forKey: Self.preferredBrowserKey)
        }
    }
    private static let preferredBrowserKey = "com.thomasderham.vectorpdf.preferredBrowser"

    /// Text Smart Search looks past in every document (see `IgnoredSearchPattern`).
    @Published public var ignoredSearchPatterns: [IgnoredSearchPattern] = [] {
        didSet {
            guard ignoredSearchPatterns != oldValue else { return }
            if let data = try? JSONEncoder().encode(ignoredSearchPatterns) {
                UserDefaults.standard.set(data, forKey: Self.ignoredSearchPatternsKey)
            }
            // Searches already showing results pick up the change.
            for viewModel in trackedViewModels.compactMap(\.viewModel) where !viewModel.searchQuery.isEmpty {
                viewModel.performSearch()
            }
        }
    }
    private static let ignoredSearchPatternsKey = "com.thomasderham.vectorpdf.ignoredSearchPatterns"

    /// The enabled, valid ignored patterns' expressions, for `SearchOptions.ignoredPatterns`.
    public var enabledIgnoredSearchPatterns: [String] {
        ignoredSearchPatterns.filter { $0.isEnabled && $0.validationError == nil }.map(\.pattern)
    }

    /// Scans the system for installed web browsers capable of opening http/https links.
    public var installedBrowsers: [InstalledBrowser] {
        var results: [InstalledBrowser] = [
            InstalledBrowser(id: "system", name: "System Default", appURL: nil)
        ]
        guard let dummyURL = URL(string: "https://apple.com") else { return results }
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: dummyURL)
        var seenBundleIDs = Set<String>()
        for appURL in appURLs {
            if let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier {
                if seenBundleIDs.insert(bundleID).inserted {
                    let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                        ?? bundle.infoDictionary?["CFBundleName"] as? String
                        ?? appURL.deletingPathExtension().lastPathComponent
                    results.append(InstalledBrowser(id: bundleID, name: name, appURL: appURL))
                }
            }
        }
        return results
    }

    /// Opens an external URL according to the user's preferred browser setting.
    public func openExternalURL(_ url: URL) {
        if preferredBrowserBundleID != "system",
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preferredBrowserBundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.ignoredSearchPatternsKey),
           let patterns = try? JSONDecoder().decode([IgnoredSearchPattern].self, from: data) {
            ignoredSearchPatterns = patterns
        }
        if let raw = UserDefaults.standard.string(forKey: Self.pdfColorAppearanceKey),
           let restored = PDFColorAppearance(rawValue: raw) {
            pdfColorAppearance = restored
        }
        if UserDefaults.standard.object(forKey: Self.showAgentTabKey) != nil {
            showAgentTab = UserDefaults.standard.bool(forKey: Self.showAgentTabKey)
        }
        if let prefRaw = UserDefaults.standard.string(forKey: Self.agentSynthesisPreferenceKey),
           let pref = AgentSynthesisPreference(rawValue: prefRaw) {
            agentSynthesisPreference = pref
        } else if Self.canUsePrivateCloudCompute {
            agentSynthesisPreference = .privateCloudCompute
        }
        if let raw = UserDefaults.standard.string(forKey: Self.onlineModelServiceKey),
           let service = OnlineModelService(rawValue: raw) {
            onlineModelService = service
        }
        if let names = UserDefaults.standard.dictionary(forKey: Self.onlineModelNamesKey) as? [String: String] {
            onlineModelNames = names
        }
        if let scaleRaw = UserDefaults.standard.string(forKey: Self.scaleModeKey),
           let mode = PDFScaleMode(rawValue: scaleRaw) {
            scaleMode = mode
        }
        if let browser = UserDefaults.standard.string(forKey: Self.preferredBrowserKey) {
            preferredBrowserBundleID = browser
        }
        restoreWorkingAids()
        speechCancellable = PDFSpeechCoordinator.shared.$isSpeaking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speaking in
                self?.isSpeaking = speaking
            }
        for name in [Notification.Name.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
                     NSWindow.didBecomeKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateUndoState() }
            }
        }
    }

    // MARK: - Edit > Undo and Redo

    /// The undo manager Edit > Undo uses: the first responder's, as AppKit's own item would.
    public var keyUndoManager: UndoManager? {
        NSApp.keyWindow?.firstResponder?.undoManager ?? NSApp.keyWindow?.undoManager
    }

    /// What Edit > Undo and Redo show. SwiftUI's own items don't reach the undo managers of
    /// these AppKit windows, so the menu has its own, refreshed from this.
    @Published public private(set) var undoState = UndoState()

    public struct UndoState: Equatable {
        public var undoTitle = "Undo"
        public var redoTitle = "Redo"
        public var canUndo = false
        public var canRedo = false
    }

    private func updateUndoState() {
        let manager = keyUndoManager
        let state = UndoState(
            undoTitle: manager?.undoMenuItemTitle ?? "Undo",
            redoTitle: manager?.redoMenuItemTitle ?? "Redo",
            canUndo: manager?.canUndo ?? false,
            canRedo: manager?.canRedo ?? false
        )
        // Typing closes an undo group per keystroke; only republish, and rebuild the menus, on a change.
        if state != undoState { undoState = state }
    }

    private var speechCancellable: AnyCancellable?
    private var selCancellable: AnyCancellable?

    /// Registers `url` with the system's shared recent-documents list (File > Open Recent, and
    /// the Dock icon's right-click menu) — the same list every other recent-items-aware app uses,
    /// so it inherits its size limit from AppKit/system configuration rather than us imposing one.
    public func noteRecentDocument(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        recentDocumentsRevision += 1
    }
    
    public func registerActive(_ viewModel: PDFViewerViewModel?) {
        guard let viewModel = viewModel else {
            activeViewModel = nil
            hasActiveDocument = false
            isActiveDocumentEdited = false
            hasActiveSelection = false
            hasActiveLayers = false
            canSaveActiveRecognizedText = false
            PDFViewerViewModel.active = nil
            docCancellable = nil
            selCancellable = nil
            return
        }
        // Re-registering the same, already-active view model is a legitimate no-op call (e.g. a
        // click in an already-key window) — skip tearing down and recreating docCancellable's
        // subscription below for it.
        guard viewModel !== _activeViewModel else { return }
        PDFViewerViewModel.active = viewModel
        activeViewModel = viewModel
        updateDocumentStatus()
        
        selCancellable = viewModel.$activeSelection
            .sink { [weak self] sel in
                self?.hasActiveSelection = (sel != nil)
            }
        
        docCancellable = viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak viewModel] _ in
                guard let self = self, let vm = viewModel else { return }
                let hasDoc = (vm.document != nil)
                if self.hasActiveDocument != hasDoc || self.documentTitle != vm.documentTitle || self.canZoomIn != (hasDoc && vm.zoomScale < Self.maxZoomScale) || self.canZoomOut != (hasDoc && vm.zoomScale > Self.minZoomScale) {
                    self.hasActiveDocument = hasDoc
                    self.documentTitle = vm.documentTitle
                    self.canZoomIn = hasDoc && (vm.zoomScale < Self.maxZoomScale)
                    self.canZoomOut = hasDoc && (vm.zoomScale > Self.minZoomScale)
                }
                if self.activeAnchors != vm.activeSnapshots {
                    self.activeAnchors = vm.activeSnapshots
                }
                let hasSel = (vm.activeSelection != nil)
                if self.hasActiveSelection != hasSel {
                    self.hasActiveSelection = hasSel
                }
                if self.isActiveDocumentEdited != vm.isDocumentEdited {
                    self.isActiveDocumentEdited = vm.isDocumentEdited
                }
                let hasLayers = !vm.annotationLayers.isEmpty
                if self.hasActiveLayers != hasLayers {
                    self.hasActiveLayers = hasLayers
                }
                if self.canSaveActiveRecognizedText != vm.canSaveRecognizedText {
                    self.canSaveActiveRecognizedText = vm.canSaveRecognizedText
                }
            }
    }

    // Mirrors the clamp range in PDFViewerViewModel.zoomIn/zoomOut/setZoom — kept as one pair of
    // constants here since both sides need to agree on where "at the limit" is.
    static let minZoomScale: CGFloat = 0.25
    static let maxZoomScale: CGFloat = 4.0

    public func updateDocumentStatus() {
        let hasDoc = (activeViewModel?.document != nil)
        self.hasActiveDocument = hasDoc
        self.isActiveDocumentEdited = activeViewModel?.isDocumentEdited ?? false
        self.documentTitle = activeViewModel?.documentTitle ?? ""
        self.canZoomIn = hasDoc && ((activeViewModel?.zoomScale ?? 1.0) < Self.maxZoomScale)
        self.canZoomOut = hasDoc && ((activeViewModel?.zoomScale ?? 1.0) > Self.minZoomScale)
        self.activeAnchors = activeViewModel?.activeSnapshots ?? []
        self.hasActiveSelection = (activeViewModel?.activeSelection != nil)
        self.hasActiveLayers = !(activeViewModel?.annotationLayers.isEmpty ?? true)
        self.canSaveActiveRecognizedText = activeViewModel?.canSaveRecognizedText ?? false
    }

    // MARK: - Document View Model Registry
    // Every non-transient document view model, weakly held: flushed on app quit, and looked up by
    // window to reach the other tabs of a tab group.
    private final class WeakViewModelBox {
        weak var viewModel: PDFViewerViewModel?
        init(_ viewModel: PDFViewerViewModel) { self.viewModel = viewModel }
    }
    private var trackedViewModels: [WeakViewModelBox] = []

    public func trackForReadingStateFlush(_ viewModel: PDFViewerViewModel) {
        trackedViewModels.removeAll { $0.viewModel == nil }
        guard !trackedViewModels.contains(where: { $0.viewModel === viewModel }) else { return }
        trackedViewModels.append(WeakViewModelBox(viewModel))
    }

    /// Every open document view model.
    public var openViewModels: [PDFViewerViewModel] {
        trackedViewModels.compactMap(\.viewModel)
    }

    public func flushAllReadingStates() {
        for box in trackedViewModels {
            box.viewModel?.saveReadingStateIfNeeded()
        }
    }

    /// The document view model hosted in `window`, if any.
    public func viewModel(for window: NSWindow) -> PDFViewerViewModel? {
        trackedViewModels.lazy.compactMap(\.viewModel).first { $0.currentWindow === window }
    }

    /// A document tab showing the file at `path` (symlinks and `..` resolved), preferring the
    /// front-most; compare panes and transient windows don't count.
    public func viewModel(showingFileAt path: String) -> PDFViewerViewModel? {
        let wanted = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        let matching = trackedViewModels.compactMap(\.viewModel).filter { viewModel in
            guard !viewModel.isComparePane, !viewModel.isTransientWindow, viewModel.currentWindow != nil,
                  let filePath = viewModel.document?.filePath else { return false }
            return URL(fileURLWithPath: filePath).resolvingSymlinksInPath().standardizedFileURL.path == wanted
        }
        guard matching.count > 1 else { return matching.first }
        let order = NSApp.orderedWindows
        return matching.min { a, b in
            (order.firstIndex { $0 === a.currentWindow } ?? .max) < (order.firstIndex { $0 === b.currentWindow } ?? .max)
        }
    }

    /// View models of every tab in `viewModel`'s window tab group, in tab order. Just
    /// `[viewModel]` when it isn't tabbed (or has no window yet).
    public func tabGroupViewModels(of viewModel: PDFViewerViewModel) -> [PDFViewerViewModel] {
        guard let window = viewModel.currentWindow, let tabs = window.tabbedWindows, tabs.count > 1 else {
            return [viewModel]
        }
        return tabs.compactMap { $0 === window ? viewModel : self.viewModel(for: $0) }
    }

    /// Brings `viewModel`'s tab to the front and scrolls it to `target`. With
    /// `revealingAllTabAnchors`, its sidebar also switches to every tab's anchors, so a list the
    /// user is working through in one tab stays in view in the next.
    public func activate(_ viewModel: PDFViewerViewModel, jumpingTo target: SnapshotTarget, revealingAllTabAnchors: Bool = false) {
        if revealingAllTabAnchors {
            NotificationCenter.default.post(name: .showAllTabAnchorsCommand, object: viewModel)
        }
        if let window = viewModel.currentWindow {
            if let group = window.tabGroup, group.selectedWindow !== window {
                group.selectedWindow = window
            }
            window.makeKeyAndOrderFront(nil)
        }
        viewModel.jumpToSnapshot(target)
    }

    /// Whether this build is signed with Apple's PCC entitlement. Developer ID builds never are.
    static var canUsePrivateCloudCompute: Bool {
#if VECTORPDF_MACOS27_SDK
        DocumentAgentConversation.hasPrivateCloudComputeEntitlement()
#else
        false
#endif
    }

    /// Engines to offer in Settings: PCC only where the build can use it.
    public var availableSynthesisPreferences: [AgentSynthesisPreference] {
        AgentSynthesisPreference.allCases.filter { $0 != .privateCloudCompute || Self.canUsePrivateCloudCompute }
    }
}

/// Manages the floating, modal behavior of the Settings window to keep it on top of document windows
/// and prevent accidental clicks into background windows while settings are being adjusted.
@MainActor
public final class SettingsModalManager {
    public static let shared = SettingsModalManager()
    private var eventMonitor: Any?
    private var closeObserver: NSObjectProtocol?
    private weak var currentSettingsWindow: NSWindow?

    private init() {}

    public func configure(window: NSWindow) {
        currentSettingsWindow = window
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior.insert([.fullScreenAuxiliary, .transient])

        if closeObserver == nil {
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.cleanup()
                }
            }
        }

        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
                guard let self = self, let settingsWin = self.currentSettingsWindow else { return event }

                // Allow menu bar interactions and non-window events
                guard let evWin = event.window else { return event }

                // Check if the event is destined for the settings window or any of its attached sheets/child windows
                if evWin == settingsWin || evWin.sheetParent == settingsWin || settingsWin.sheets.contains(evWin) || settingsWin.childWindows?.contains(evWin) == true {
                    return event
                }

                // If it's a key event like Escape, Command-W, or Command-Comma, allow closing settings
                if event.type == .keyDown {
                    if event.keyCode == 53 { // Escape
                        settingsWin.performClose(nil)
                        return nil
                    }
                    if event.modifierFlags.contains(.command) {
                        let chars = event.charactersIgnoringModifiers ?? ""
                        if chars == "w" || chars == "," {
                            settingsWin.performClose(nil)
                            return nil
                        }
                    }
                }

                // Any click outside the settings window and its sheets is intercepted modally
                if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
                    NSSound.beep()
                    settingsWin.makeKeyAndOrderFront(nil)
                    return nil
                }

                return event
            }
        }
    }

    public func cleanup() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        currentSettingsWindow = nil
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
            }
        }
    }
}

/// The app's Settings window (⌘,): a pane per tab, each a grouped form so labels, controls and
/// explanations get room of their own.
public struct AppSettingsView: View {
    @AppStorage("settingsSelectedPane") private var selectedPane = "general"

    public init() {}

    public var body: some View {
        TabView(selection: $selectedPane) {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            AgentSettingsPane()
                .tabItem { Label("Agent", systemImage: "sparkles") }
                .tag("agent")
            AdvancedSettingsPane()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag("advanced")
            DataSettingsPane()
                .tabItem { Label("Data", systemImage: "externaldrive") }
                .tag("data")
        }
        .background(
            SettingsWindowAccessor { window in
                SettingsModalManager.shared.configure(window: window)
            }
        )
        .onDisappear {
            SettingsModalManager.shared.cleanup()
        }
    }
}

/// Every pane is the same width; the window takes each pane's height when its tab is chosen.
private extension View {
    func settingsPane(height: CGFloat) -> some View {
        formStyle(.grouped)
            .frame(width: 500, height: height)
    }
}

/// A label with a line of secondary text under it, as System Settings shows.
private struct SettingsLabel: View {
    let title: String
    let detail: String?

    init(_ title: String, detail: String?) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        Text(title)
        if let detail {
            Text(detail)
        }
    }
}

/// Settings > General: annotations, how documents look, updates.
struct GeneralSettingsPane: View {
    @ObservedObject private var coordinator = PDFViewerAppCoordinator.shared
    @ObservedObject private var updater = GitHubUpdater.shared
    @ObservedObject private var signatureStore = SignatureStore.shared
    @State private var isShowingSignatureEditor = false
    @AppStorage(PDFViewerViewModel.annotationAuthorDefaultsKey) private var annotationAuthor = ""

    var body: some View {
        Form {
            Section("Annotations") {
                TextField("Annotation Author", text: $annotationAuthor, prompt: Text(NSFullUserName()))
                stampRow
            }

            Section {
                // Independent of system UI theme.
                Picker("PDF Color", selection: $coordinator.pdfColorAppearance) {
                    ForEach(PDFColorAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                Picker("Open Links In", selection: $coordinator.preferredBrowserBundleID) {
                    ForEach(coordinator.installedBrowsers) { browser in
                        Text(browser.name).tag(browser.id)
                    }
                }
                Toggle(isOn: $coordinator.showsDocumentStructureInSidebar) {
                    SettingsLabel(
                        "List form fields, links and destinations in the sidebar",
                        detail: "In the Document tab, with layers and attachments. The tab then also appears for documents that have any of these."
                    )
                }
            } header: {
                Text("Viewing")
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $updater.automaticUpdateChecks)
                LabeledContent {
                    Button("Check Now") {
                        updater.checkForUpdates(isManualCheck: true)
                    }
                    .disabled(updater.isChecking || updater.isDownloading)
                } label: {
                    SettingsLabel(
                        "Check for Updates",
                        detail: "Last checked: " + (updater.lastUpdateCheckDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    )
                }
            }
        }
        .settingsPane(height: 500)
        .sheet(isPresented: $isShowingSignatureEditor) {
            SignatureCaptureView { image in
                isShowingSignatureEditor = false
                if let image = image, let data = image.pdfStampPNGData {
                    signatureStore.save(data: data)
                }
            }
        }
    }

    private var stampRow: some View {
        LabeledContent {
            if let data = signatureStore.savedSignatureData, let img = NSImage(data: data) {
                HStack(spacing: 10) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 40)
                        .padding(4)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    VStack(alignment: .trailing, spacing: 4) {
                        Button("Modify…") { isShowingSignatureEditor = true }
                        Button("Delete", role: .destructive) { signatureStore.clear() }
                    }
                    .controlSize(.small)
                }
            } else {
                Button("Create Signature…") { isShowingSignatureEditor = true }
            }
        } label: {
            SettingsLabel(
                "Handwritten Signature",
                detail: signatureStore.savedSignatureData == nil ? "None saved. It's a picture to put on pages, not a digital signature." : nil
            )
        }
    }
}

/// Settings > Agent: whether the Agent tab is shown, and what writes its answers.
struct AgentSettingsPane: View {
    @ObservedObject private var coordinator = PDFViewerAppCoordinator.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $coordinator.showAgentTab) {
                    SettingsLabel("Use Agent", detail: "Adds the Ask About This Document tab to the sidebar. Needs macOS 26 or later.")
                }
            }

#if VECTORPDF_MACOS27_SDK
            if #available(macOS 27.0, *), coordinator.showAgentTab {
                Section {
                    Picker("AI Synthesis Engine", selection: $coordinator.agentSynthesisPreference) {
                        ForEach(coordinator.availableSynthesisPreferences, id: \.self) { pref in
                            Text(pref.displayName).tag(pref)
                        }
                    }
                    .pickerStyle(.menu)

                    if coordinator.agentSynthesisPreference == .onlineModel {
                        OnlineModelSettingsView()
                    }
                } footer: {
                    switch coordinator.agentSynthesisPreference {
                    case .onlineModel:
                        Text("Your questions and the passages used to answer them are sent to \(coordinator.onlineModelService.displayName) with your key, and billed to your account. If it can't answer, VectorPDF answers on-device.")
                            .settingsFooter()
                    case .privateCloudCompute:
                        Text("Your questions and the passages used to answer them are sent to Apple's Private Cloud Compute. If it can't answer, VectorPDF answers on-device.")
                            .settingsFooter()
                    case .onDevice:
                        Text("Answers are written on this Mac. Nothing is sent anywhere.")
                            .settingsFooter()
                    }
                }
            }
#endif
        }
        .settingsPane(height: agentPaneHeight)
    }

    private var agentPaneHeight: CGFloat {
#if VECTORPDF_MACOS27_SDK
        if #available(macOS 27.0, *), coordinator.showAgentTab {
            return coordinator.agentSynthesisPreference == .onlineModel ? 410 : 220
        }
#endif
        return 140
    }
}

extension Text {
    /// Explanatory text under a section, wrapping rather than being cut off.
    func settingsFooter() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Settings > Advanced: Smart Search's ignored patterns, and LaTeX.
struct AdvancedSettingsPane: View {
    @ObservedObject private var coordinator = PDFViewerAppCoordinator.shared
    @State private var isShowingIgnoredPatterns = false

    var body: some View {
        Form {
            Section("Search") {
                LabeledContent {
                    Button("Edit…") { isShowingIgnoredPatterns = true }
                } label: {
                    SettingsLabel(
                        "Ignored Search Patterns",
                        detail: coordinator.ignoredSearchPatterns.isEmpty
                            ? "None"
                            : "\(coordinator.enabledIgnoredSearchPatterns.count) of \(coordinator.ignoredSearchPatterns.count) on"
                    )
                }
            }

            Section("LaTeX") {
                LaTeXSettingsView()
            }
        }
        .settingsPane(height: 230)
        .sheet(isPresented: $isShowingIgnoredPatterns) {
            IgnoredSearchPatternsView()
        }
    }
}

/// Settings > Data: iCloud sync, how much space VectorPDF's data takes, and ways to clear it.
struct DataSettingsPane: View {
    @ObservedObject private var readingState = ReadingStateManager.shared
    @State private var usage: StoredData.Usage?
    @State private var confirming: Confirmation?
    @State private var blockedMessage: String?

    private enum Confirmation: Identifiable {
        case readingHistory, removeAll
        var id: Self { self }
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func refresh() async {
        usage = await StoredData.usage()
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { readingState.isCloudSyncEnabled },
                    set: { readingState.setCloudSyncEnabled($0) }
                )) {
                    SettingsLabel(
                        "Sync reading positions with iCloud",
                        detail: "Last page, zoom, anchors, and recent searches, through your own iCloud account. Documents are not uploaded."
                    )
                }
            }

            Section {
                row("Agent indexes", detail: usage.map { size($0.agentIndexBytes) }) {
                    Button("Clear") {
                        Task {
                            await StoredData.clearAgentIndexes()
                            await refresh()
                        }
                    }
                    .disabled((usage?.agentIndexBytes ?? 0) == 0)
                }
                row("Reading history", detail: usage.map {
                    let docs = $0.documentCount == 1 ? "1 document" : "\($0.documentCount) documents"
                    return "\(docs), \(size($0.thumbnailBytes)) of anchor thumbnails"
                }) {
                    Button("Clear…") { confirming = .readingHistory }
                        .disabled(usage.map { $0.documentCount == 0 && $0.thumbnailBytes == 0 } ?? true)
                }
                row("Temporary files", detail: usage.map { size($0.temporaryBytes) }) {
                    EmptyView()
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Agent indexes let the Agent tab answer without reading a document again. Temporary files left by a crash are deleted the next time VectorPDF opens.")
                    .settingsFooter()
            }

            Section {
                LabeledContent {
                    Button("Remove All…") {
                        if let blocker = StoredData.removeAllBlocker {
                            blockedMessage = blocker
                        } else {
                            confirming = .removeAll
                        }
                    }
                } label: {
                    SettingsLabel(
                        "Remove All VectorPDF Data",
                        detail: "Also removes your settings, then quits. Your documents aren't touched."
                    )
                }
            }
        }
        .settingsPane(height: 460)
        .task { await refresh() }
        .alert(item: $confirming) { which in
            switch which {
            case .readingHistory:
                return Alert(
                    title: Text("Clear reading history?"),
                    message: Text("Every document's last page, zoom, anchors and recent searches are forgotten, on this Mac and in iCloud. Open documents lose their anchors too."),
                    primaryButton: .destructive(Text("Clear")) {
                        StoredData.clearReadingHistory()
                        Task { await refresh() }
                    },
                    secondaryButton: .cancel()
                )
            case .removeAll:
                return Alert(
                    title: Text("Remove all VectorPDF data and quit?"),
                    message: Text("Removes reading history (also from iCloud), Agent indexes, anchor thumbnails, temporary files, the tour's copy, saved API keys, favorites, tab groups, your stamp and all settings. Your documents aren't touched."),
                    primaryButton: .destructive(Text("Remove and Quit")) {
                        Task { await StoredData.removeAllAndQuit() }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .alert("Can't Remove Data Yet", isPresented: Binding(
            get: { blockedMessage != nil },
            set: { if !$0 { blockedMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(blockedMessage ?? "")
        }
    }

    private func row<Action: View>(_ title: String, detail: String?, @ViewBuilder action: () -> Action) -> some View {
        LabeledContent {
            action()
        } label: {
            SettingsLabel(title, detail: detail ?? "Calculating…")
        }
    }
}

/// Represents a persistently saved favorite PDF
public struct FavoriteDocument: Codable, Identifiable, Equatable {
    public var id: String { path }
    public let path: String
    public let title: String
    public let dateAdded: Date
    
    public init(path: String, title: String, dateAdded: Date = Date()) {
        self.path = path
        self.title = title
        self.dateAdded = dateAdded
    }
}

/// Persistent favorites manager for quick-access document opening
@MainActor
public final class FavoritesManager: ObservableObject {
    public static let shared = FavoritesManager()
    private let userDefaultsKey = "com.thomasderham.vectorpdf.favorites"

    @Published public private(set) var favorites: [FavoriteDocument] = []

    public init() {
        loadFavorites()
    }
    
    public func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let list = try? JSONDecoder().decode([FavoriteDocument].self, from: data) {
            self.favorites = list
        }
    }
    
    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    public func isFavorite(path: String) -> Bool {
        favorites.contains { $0.path == path }
    }
    
    public func addFavorite(path: String, title: String) {
        guard !isFavorite(path: path) else { return }
        favorites.insert(FavoriteDocument(path: path, title: title), at: 0)
        saveFavorites()
    }
    
    @discardableResult
    public func removeFavorite(path: String) -> (document: FavoriteDocument, index: Int)? {
        guard let idx = favorites.firstIndex(where: { $0.path == path }) else { return nil }
        let removed = favorites.remove(at: idx)
        saveFavorites()
        return (removed, idx)
    }

    public func insertFavorite(_ doc: FavoriteDocument, at index: Int = 0) {
        guard !isFavorite(path: doc.path) else { return }
        let insertIdx = min(max(0, index), favorites.count)
        favorites.insert(doc, at: insertIdx)
        saveFavorites()
    }
    
    public func toggleFavorite(path: String, title: String) {
        if isFavorite(path: path) {
            removeFavorite(path: path)
        } else {
            addFavorite(path: path, title: title)
        }
    }
}

