import Foundation
import AppKit
import Combine

// MARK: - Semantic Version Comparison

/// Represents a parsed Semantic Version (SemVer 2.0) with support for pre-release metadata.
public struct SemanticVersion: Equatable, Comparable, Sendable {
    public let coreParts: [Int]
    public let prereleaseParts: [PrereleaseIdentifier]

    public enum PrereleaseIdentifier: Equatable, Comparable, Sendable {
        case numeric(Int)
        case alphanumeric(String)

        public static func < (lhs: PrereleaseIdentifier, rhs: PrereleaseIdentifier) -> Bool {
            switch (lhs, rhs) {
            case let (.numeric(l), .numeric(r)):
                return l < r
            case (.numeric, .alphanumeric):
                // In SemVer 2.0, numeric identifiers always have lower precedence than alphanumeric identifiers
                return true
            case (.alphanumeric, .numeric):
                return false
            case let (.alphanumeric(l), .alphanumeric(r)):
                return l.compare(r) == .orderedAscending
            }
        }
    }

    public init?(string: String) {
        var clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasPrefix("v") {
            clean = String(clean.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !clean.isEmpty else { return nil }

        // Strip build metadata after '+'
        let withoutBuild = clean.components(separatedBy: "+").first ?? clean

        // Split into core version and prerelease identifiers (separated by '-')
        let parts = withoutBuild.components(separatedBy: "-")
        let coreString = parts[0]

        let coreTokens = coreString.components(separatedBy: ".").filter { !$0.isEmpty }
        guard !coreTokens.isEmpty else { return nil }

        var parsedCore: [Int] = []
        for token in coreTokens {
            guard let val = Int(token) else { return nil }
            parsedCore.append(val)
        }
        self.coreParts = parsedCore

        if parts.count > 1 {
            let preString = parts.dropFirst().joined(separator: "-")
            let preTokens = preString.components(separatedBy: ".").filter { !$0.isEmpty }
            var parsedPre: [PrereleaseIdentifier] = []
            for token in preTokens {
                if let num = Int(token), token.allSatisfy({ $0.isNumber }) {
                    parsedPre.append(.numeric(num))
                } else {
                    parsedPre.append(.alphanumeric(token))
                }
            }
            self.prereleaseParts = parsedPre
        } else {
            self.prereleaseParts = []
        }
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        // 1. Compare core numbers left to right
        let maxCount = max(lhs.coreParts.count, rhs.coreParts.count)
        for i in 0..<maxCount {
            let lVal = i < lhs.coreParts.count ? lhs.coreParts[i] : 0
            let rVal = i < rhs.coreParts.count ? rhs.coreParts[i] : 0
            if lVal < rVal { return true }
            if lVal > rVal { return false }
        }

        // 2. Core numbers are identical: compare prerelease
        // A normal release has higher precedence than a pre-release of the same core version.
        if lhs.prereleaseParts.isEmpty && !rhs.prereleaseParts.isEmpty {
            return false // lhs > rhs
        }
        if !lhs.prereleaseParts.isEmpty && rhs.prereleaseParts.isEmpty {
            return true  // lhs < rhs
        }

        // Both have prerelease identifiers
        let minPre = min(lhs.prereleaseParts.count, rhs.prereleaseParts.count)
        for i in 0..<minPre {
            let lPre = lhs.prereleaseParts[i]
            let rPre = rhs.prereleaseParts[i]
            if lPre < rPre { return true }
            if rPre < lPre { return false }
        }

        // All compared identifiers are equal: larger set of pre-release fields has higher precedence
        return lhs.prereleaseParts.count < rhs.prereleaseParts.count
    }

    /// Compares two version strings and returns true if `latestTag` is strictly newer than `currentVersion`.
    public static func isNewerVersion(latestTag: String, currentVersion: String) -> Bool {
        guard let latest = SemanticVersion(string: latestTag),
              let current = SemanticVersion(string: currentVersion) else {
            return false
        }
        return current < latest
    }
}

// MARK: - GitHub Release Data Models

public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String?
    public let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case assets
    }
}

public struct GitHubAsset: Decodable, Sendable {
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

// MARK: - GitHubUpdater

@MainActor
public final class GitHubUpdater: ObservableObject {
    public static let shared = GitHubUpdater()

    public static let automaticUpdateChecksKey = "automaticUpdateChecks"
    public static let lastUpdateCheckKey = "lastUpdateCheck"

    @Published public var automaticUpdateChecks: Bool {
        didSet {
            UserDefaults.standard.set(automaticUpdateChecks, forKey: Self.automaticUpdateChecksKey)
        }
    }

    @Published public var lastUpdateCheckDate: Date? {
        didSet {
            if let date = lastUpdateCheckDate {
                UserDefaults.standard.set(date.timeIntervalSince1970 * 1000.0, forKey: Self.lastUpdateCheckKey)
            }
        }
    }

    @Published public var isChecking: Bool = false
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0

    public var onUpdateAvailable: ((_ version: String, _ downloadUrl: String) -> Void)?
    public var onDownloadProgress: ((Float) -> Void)?

    private var user: String = "tomderham"
    private var repo: String = "vectorpdf"
    private var appName: String = "VectorPDF"
    public private(set) var currentAppVersion: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"

    private var timer: Timer?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadSession: URLSession?
    private var downloadDelegate: DownloadProgressDelegate?
    private var progressWindow: NSWindow?
    private var progressIndicator: NSProgressIndicator?
    private var progressStatusLabel: NSTextField?

    public init() {
        if UserDefaults.standard.object(forKey: Self.automaticUpdateChecksKey) != nil {
            self.automaticUpdateChecks = UserDefaults.standard.bool(forKey: Self.automaticUpdateChecksKey)
        } else {
            self.automaticUpdateChecks = true
        }

        let lastCheckVal = UserDefaults.standard.double(forKey: Self.lastUpdateCheckKey)
        if lastCheckVal > 0 {
            self.lastUpdateCheckDate = Date(timeIntervalSince1970: lastCheckVal / 1000.0)
        } else {
            self.lastUpdateCheckDate = nil
        }
    }

    // MARK: - Lifecycle

    public func start(gitHubUser: String = "tomderham",
                      gitHubRepo: String = "vectorpdf",
                      applicationName: String = "VectorPDF",
                      currentVersion: String? = nil) {
        self.user = gitHubUser
        self.repo = gitHubRepo
        self.appName = applicationName

        if let version = currentVersion ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            self.currentAppVersion = version
        }

        // Hourly check timer (3600 seconds)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timerCallback()
            }
        }

        // Also check on launch if applicable
        checkIfTimeForUpdateCheck()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        downloadTask?.cancel()
        downloadTask = nil
        closeProgressWindow()
    }

    private func timerCallback() {
        if automaticUpdateChecks {
            checkIfTimeForUpdateCheck()
        }
    }

    public func checkIfTimeForUpdateCheck() {
        guard !isChecking && !isDownloading else { return }
        guard automaticUpdateChecks else { return }

        let now = Date()
        if let lastCheck = lastUpdateCheckDate {
            // Check if more than 24 hours (86,400 seconds) have passed
            if now.timeIntervalSince(lastCheck) >= 86400 {
                checkForUpdates(isManualCheck: false)
            }
        } else {
            // Never checked before: trigger initial check
            checkForUpdates(isManualCheck: false)
        }
    }

    // MARK: - Check For Updates

    public func checkForUpdates(isManualCheck: Bool = true) {
        guard !isChecking && !isDownloading else { return }
        isChecking = true

        guard let url = URL(string: "https://api.github.com/repos/\(user)/\(repo)/releases/latest") else {
            isChecking = false
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("\(appName)-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                await MainActor.run {
                    self.isChecking = false
                    self.handleGitHubResponse(data: data, response: response, isManualCheck: isManualCheck)
                }
            } catch {
                await MainActor.run {
                    self.isChecking = false
                    if isManualCheck {
                        self.showErrorAlert(
                            title: "Update Check Failed",
                            message: "\(self.appName) was unable to connect to GitHub to check for updates. Please check your internet connection."
                        )
                    }
                }
            }
        }
    }

    private func handleGitHubResponse(data: Data, response: URLResponse, isManualCheck: Bool) {
        // Record timestamp on valid HTTP response from GitHub
        self.lastUpdateCheckDate = Date()

        guard let httpResponse = response as? HTTPURLResponse else {
            if isManualCheck {
                showErrorAlert(
                    title: "Update Check Failed",
                    message: "\(appName) received an invalid response from GitHub."
                )
            }
            return
        }

        if httpResponse.statusCode == 200 {
            guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                if isManualCheck {
                    showErrorAlert(
                        title: "Update Check Failed",
                        message: "\(appName) was unable to parse the release information from GitHub."
                    )
                }
                return
            }

            var downloadUrl: String?
            for asset in release.assets {
                if asset.name.lowercased().hasSuffix(".dmg") {
                    downloadUrl = asset.browserDownloadUrl
                    break
                }
            }

            if SemanticVersion.isNewerVersion(latestTag: release.tagName, currentVersion: currentAppVersion) {
                if let onUpdateAvailable = onUpdateAvailable, let dl = downloadUrl {
                    onUpdateAvailable(release.tagName, dl)
                }
                handleUpdateFound(release: release, downloadUrl: downloadUrl)
            } else if isManualCheck {
                showInfoAlert(
                    title: "You're Up to Date",
                    message: "\(appName) v\(currentAppVersion) is currently the newest available version."
                )
            }
        } else {
            // API error or rate-limited (e.g. 403)
            if isManualCheck {
                showErrorAlert(
                    title: "Update Check Failed",
                    message: "\(appName) was unable to check for updates (GitHub API rate limit or error). Please try again later or check https://github.com/\(user)/\(repo)/releases directly."
                )
            }
        }
    }

    private func handleUpdateFound(release: GitHubRelease, downloadUrl: String?) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Update Available"
        alert.informativeText = "A new version (\(release.tagName)) of \(appName) is available. Would you like to download it?"
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let downloadUrl = downloadUrl {
                downloadUpdate(downloadUrl: downloadUrl)
            } else if let releaseUrl = release.htmlUrl, let url = URL(string: releaseUrl) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Download Handling

    public func downloadUpdate(downloadUrl: String) {
        guard let url = URL(string: downloadUrl) else { return }

        isDownloading = true
        downloadProgress = 0.0

        let tempDir = FileManager.default.temporaryDirectory
        let targetFile = tempDir.appendingPathComponent("\(appName)_Update.dmg")
        try? FileManager.default.removeItem(at: targetFile)

        showDownloadProgressWindow()

        let config = URLSessionConfiguration.default
        let delegate = DownloadProgressDelegate(updater: self)
        self.downloadDelegate = delegate
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.downloadSession = session

        var request = URLRequest(url: url)
        request.setValue("\(appName)-Updater", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        self.downloadTask = task
        task.resume()
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0.0
        closeProgressWindow()
    }

    private func showDownloadProgressWindow() {
        if progressWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 130),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Software Update"
            window.isReleasedWhenClosed = false
            window.center()

            let contentView = NSView(frame: window.contentView!.bounds)
            contentView.autoresizingMask = [.width, .height]

            let titleLabel = NSTextField(labelWithString: "Downloading \(appName) update...")
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            titleLabel.frame = NSRect(x: 20, y: 88, width: 340, height: 20)
            contentView.addSubview(titleLabel)

            let indicator = NSProgressIndicator(frame: NSRect(x: 20, y: 55, width: 340, height: 20))
            indicator.isIndeterminate = false
            indicator.minValue = 0.0
            indicator.maxValue = 1.0
            indicator.doubleValue = 0.0
            contentView.addSubview(indicator)
            self.progressIndicator = indicator

            let statusLabel = NSTextField(labelWithString: "Connecting...")
            statusLabel.font = NSFont.systemFont(ofSize: 11)
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.frame = NSRect(x: 20, y: 22, width: 250, height: 18)
            contentView.addSubview(statusLabel)
            self.progressStatusLabel = statusLabel

            let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(progressCancelClicked))
            cancelButton.bezelStyle = .rounded
            cancelButton.frame = NSRect(x: 280, y: 15, width: 80, height: 28)
            contentView.addSubview(cancelButton)

            window.contentView = contentView
            self.progressWindow = window
        }

        progressIndicator?.doubleValue = 0.0
        progressIndicator?.isIndeterminate = false
        progressStatusLabel?.stringValue = "Starting download..."
        progressWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func progressCancelClicked() {
        cancelDownload()
    }

    private func closeProgressWindow() {
        progressWindow?.orderOut(nil)
        progressWindow = nil
        progressIndicator = nil
        progressStatusLabel = nil
    }

    internal func updateDownloadProgress(bytesWritten: Int64,
                                        totalBytesWritten: Int64,
                                        totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            self.downloadProgress = progress
            self.progressIndicator?.isIndeterminate = false
            self.progressIndicator?.doubleValue = progress
            self.onDownloadProgress?(Float(progress))

            let writtenMB = Double(totalBytesWritten) / (1024.0 * 1024.0)
            let totalMB = Double(totalBytesExpectedToWrite) / (1024.0 * 1024.0)
            let percent = Int(progress * 100)
            self.progressStatusLabel?.stringValue = String(format: "%.1f MB of %.1f MB (%d%%)", writtenMB, totalMB, percent)
        } else {
            self.downloadProgress = -1.0
            self.progressIndicator?.isIndeterminate = true
            self.progressIndicator?.startAnimation(nil)
            self.onDownloadProgress?(-1.0)
            let writtenMB = Double(totalBytesWritten) / (1024.0 * 1024.0)
            self.progressStatusLabel?.stringValue = String(format: "%.1f MB downloaded", writtenMB)
        }
    }

    internal func handleDownloadFinished(location: URL) {
        let tempDir = FileManager.default.temporaryDirectory
        let targetFile = tempDir.appendingPathComponent("\(appName)_Update.dmg")

        do {
            try? FileManager.default.removeItem(at: targetFile)
            try FileManager.default.moveItem(at: location, to: targetFile)

            closeProgressWindow()
            isDownloading = false
            downloadProgress = 1.0

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Download complete"
            alert.informativeText = "The update for \(appName) has been downloaded. Would you like to quit \(appName) and open the installer now?"
            alert.addButton(withTitle: "Quit and Open Installer")
            alert.addButton(withTitle: "Later")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // 1. Open the DMG in Finder
                NSWorkspace.shared.open(targetFile)

                // 2. Quit the current application to allow installation
                NSApp.terminate(nil)
            }
        } catch {
            closeProgressWindow()
            isDownloading = false
            showErrorAlert(
                title: "Update Download Failed",
                message: "Failed to save the downloaded update to disk. Please try again."
            )
        }
    }

    internal func handleDownloadFailed(error: Error?) {
        closeProgressWindow()
        isDownloading = false
        downloadProgress = 0.0

        if let error = error as NSError?, error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            // User cancelled, do not display error dialog
            return
        }

        showErrorAlert(
            title: "Update Download Failed",
            message: "\(appName) was unable to download the update. Please check your internet connection or download the latest release directly from GitHub."
        )
    }

    // MARK: - Alert Helpers

    private func showInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - DownloadProgressDelegate

final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private weak var updater: GitHubUpdater?

    init(updater: GitHubUpdater) {
        self.updater = updater
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        Task { @MainActor [weak self] in
            self?.updater?.updateDownloadProgress(
                bytesWritten: bytesWritten,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpectedToWrite: totalBytesExpectedToWrite
            )
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // location is only temporary during the delegate call, so copy to persistent temp file first
        let tempDir = FileManager.default.temporaryDirectory
        let savedTempFile = tempDir.appendingPathComponent(UUID().uuidString + ".dmg")
        do {
            try FileManager.default.copyItem(at: location, to: savedTempFile)
            Task { @MainActor [weak self] in
                self?.updater?.handleDownloadFinished(location: savedTempFile)
            }
        } catch {
            Task { @MainActor [weak self] in
                self?.updater?.handleDownloadFailed(error: error)
            }
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor [weak self] in
                self?.updater?.handleDownloadFailed(error: error)
            }
        }
    }
}
