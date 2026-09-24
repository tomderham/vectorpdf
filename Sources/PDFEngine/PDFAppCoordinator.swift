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
    case automatic
    case onDevice
    case privateCloudCompute

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .onDevice: return "On-Device"
        case .privateCloudCompute: return "Private Cloud Compute"
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
    @Published public var documentTitle: String = ""
    @Published public var canZoomIn: Bool = false
    @Published public var canZoomOut: Bool = false
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
    private static let pdfColorAppearanceKey = "com.vectorpdf.app.pdfColorAppearance"

    /// Controls visibility of the Agent sidebar tab.
    @Published public var showAgentTab: Bool = true {
        didSet {
            UserDefaults.standard.set(showAgentTab, forKey: Self.showAgentTabKey)
        }
    }
    private static let showAgentTabKey = "com.vectorpdf.app.showAgentTab"

    /// Backend synthesis preference for Agent questions.
    @Published public var agentSynthesisPreference: AgentSynthesisPreference = .automatic {
        didSet {
            UserDefaults.standard.set(agentSynthesisPreference.rawValue, forKey: Self.agentSynthesisPreferenceKey)
        }
    }
    private static let agentSynthesisPreferenceKey = "com.vectorpdf.app.agentSynthesisPreference"

    /// Defines how 100% scale is interpreted. Defaults to .physical ("Size on screen equals size on printout", matching Preview).
    @Published public var scaleMode: PDFScaleMode = .physical {
        didSet {
            UserDefaults.standard.set(scaleMode.rawValue, forKey: Self.scaleModeKey)
        }
    }
    private static let scaleModeKey = "com.vectorpdf.app.scaleMode"

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
    /// `open` command). On a cold launch, `.openFilePathCommand`'s notification can be posted
    /// before SwiftUI's WindowGroup has mounted any view to observe it, so it's silently dropped —
    /// this is the fallback the app's first window checks once, in its own initial `.task`.
    /// Already-running-app opens keep working via the live notification.
    public var pendingOpenFilePath: String?

    /// Reads and clears `pendingOpenFilePath` in one step, so only the first window to check it
    /// consumes it.
    public func consumePendingOpenFilePath() -> String? {
        defer { pendingOpenFilePath = nil }
        return pendingOpenFilePath
    }

    /// Preferred browser bundle identifier for opening external links ("system" uses macOS default).
    @Published public var preferredBrowserBundleID: String = "system" {
        didSet {
            UserDefaults.standard.set(preferredBrowserBundleID, forKey: Self.preferredBrowserKey)
        }
    }
    private static let preferredBrowserKey = "com.vectorpdf.app.preferredBrowser"

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
        }
        if let scaleRaw = UserDefaults.standard.string(forKey: Self.scaleModeKey),
           let mode = PDFScaleMode(rawValue: scaleRaw) {
            scaleMode = mode
        }
        if let browser = UserDefaults.standard.string(forKey: Self.preferredBrowserKey) {
            preferredBrowserBundleID = browser
        }
    }

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
            PDFViewerViewModel.active = nil
            return
        }
        // Re-registering the same, already-active view model is a legitimate no-op call (e.g. a
        // click in an already-key window) — skip tearing down and recreating docCancellable's
        // subscription below for it.
        guard viewModel !== _activeViewModel else { return }
        PDFViewerViewModel.active = viewModel
        activeViewModel = viewModel
        updateDocumentStatus()
        
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
            }
    }

    // Mirrors the clamp range in PDFViewerViewModel.zoomIn/zoomOut/setZoom — kept as one pair of
    // constants here since both sides need to agree on where "at the limit" is.
    static let minZoomScale: CGFloat = 0.25
    static let maxZoomScale: CGFloat = 4.0

    public func updateDocumentStatus() {
        let hasDoc = (activeViewModel?.document != nil)
        self.hasActiveDocument = hasDoc
        self.documentTitle = activeViewModel?.documentTitle ?? ""
        self.canZoomIn = hasDoc && ((activeViewModel?.zoomScale ?? 1.0) < Self.maxZoomScale)
        self.canZoomOut = hasDoc && ((activeViewModel?.zoomScale ?? 1.0) > Self.minZoomScale)
        self.activeAnchors = activeViewModel?.activeSnapshots ?? []
    }

    // MARK: - Reading State Lifecycle
    //
    // Tracks every non-transient (i.e. not a snapshot/reference window) view model currently open,
    // purely so their reading state (page/zoom/snapshots) can be flushed to disk on app quit —
    // loadDocument's own save-on-switch and PDFViewerMainView's save-on-window-close cover the two
    // other exit paths, but neither fires for "still reading this document when you just quit the
    // app," which is the single most common case this needs to handle.
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

    public func flushAllReadingStates() {
        for box in trackedViewModels {
            box.viewModel?.saveReadingStateIfNeeded()
        }
    }

#if VECTORPDF_MACOS27_SDK
    public var pccStatusDescription: String {
        if DocumentAgentConversation.hasPrivateCloudComputeEntitlement() {
            return "Private Cloud Compute entitlement is active."
        } else {
            return "Private Cloud Compute requires Apple's managed entitlement ('com.apple.developer.private-cloud-compute') with an Apple Developer provisioning profile. Automatic mode safely uses On-Device compute."
        }
    }
#endif
}

/// The app's Settings window (⌘,).
public struct AppSettingsView: View {
    @ObservedObject private var coordinator = PDFViewerAppCoordinator.shared
    @ObservedObject private var updater = GitHubUpdater.shared

    public init() {}

    public var body: some View {
        Form {
            Toggle("Use Agent (macOS 26 or above)", isOn: $coordinator.showAgentTab)
                .padding(.bottom, 12)

#if VECTORPDF_MACOS27_SDK
            if #available(macOS 27.0, *), coordinator.showAgentTab {
                Picker("AI Synthesis Engine", selection: $coordinator.agentSynthesisPreference) {
                    ForEach(AgentSynthesisPreference.allCases, id: \.self) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .pickerStyle(.menu)

                Text(coordinator.pccStatusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
#endif

            // Independent of the app's own UI theme (which always follows the system) — lets
            // someone keep the app in Dark Mode for comfort while still seeing a document's true,
            // un-inverted colors when color accuracy matters, e.g. filling out a color-coded form.
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

            Divider()
                .padding(.vertical, 8)

            Toggle("Automatically check for updates", isOn: $updater.automaticUpdateChecks)
                .padding(.bottom, 6)

            HStack {
                if let lastCheck = updater.lastUpdateCheckDate {
                    Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Last checked: Never")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Check Now") {
                    updater.checkForUpdates(isManualCheck: true)
                }
                .disabled(updater.isChecking || updater.isDownloading)
            }
        }
        .padding(20)
        .frame(width: 420)
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
    private let userDefaultsKey = "com.vectorpdf.app.favorites"

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

