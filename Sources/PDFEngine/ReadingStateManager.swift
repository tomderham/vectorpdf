import Foundation
import CoreGraphics

/// A document's remembered reading position, zoom, and saved snapshots — keyed by file path (see
/// ReadingStateManager). Deliberately simple automatic per-document persistence, not an explicit
/// workspace file to save/open, and no security-scoped bookmarks: the app isn't sandboxed, so
/// there's no need to regain file access permission across launches via a bookmark.
public struct DocumentReadingState: Codable, Equatable {
    public var lastPageIndex: Int
    public var zoomScale: CGFloat
    public var snapshots: [SnapshotTarget]

    public init(lastPageIndex: Int, zoomScale: CGFloat, snapshots: [SnapshotTarget]) {
        self.lastPageIndex = lastPageIndex
        self.zoomScale = zoomScale
        self.snapshots = snapshots
    }
}

/// Persists each document's last page, zoom, and snapshots across launches, keyed by file path.
/// Storage approach mirrors FavoritesManager/TabGroupManager (UserDefaults-backed JSON) for
/// consistency, at the same small scale of data.
@MainActor
public final class ReadingStateManager: ObservableObject {
    public static let shared = ReadingStateManager()
    private let userDefaultsKey = "com.vectorpdf.app.readingstate"

    private var states: [String: DocumentReadingState] = [:]

    private init() {
        load()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: DocumentReadingState].self, from: data) {
            self.states = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    public func state(for path: String) -> DocumentReadingState? {
        states[path]
    }

    public func updateState(for path: String, lastPageIndex: Int, zoomScale: CGFloat, snapshots: [SnapshotTarget]) {
        states[path] = DocumentReadingState(lastPageIndex: lastPageIndex, zoomScale: zoomScale, snapshots: snapshots)
        save()
    }
}
