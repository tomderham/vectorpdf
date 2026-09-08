import Foundation

/// A named, ordered set of documents that open together as tabs in a single window — e.g. "the
/// three specs I always need side by side for project X." Distinct from a plain Favorite (a
/// single document); opening a TabGroup opens all of its documents at once, as tabs of one
/// window, rather than one document on its own.
public struct TabGroup: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    /// Ordered to match tab order when reopened.
    public var documentPaths: [String]
    public let dateAdded: Date
    public var dateModified: Date

    public init(
        id: UUID = UUID(),
        name: String,
        documentPaths: [String],
        dateAdded: Date = Date(),
        dateModified: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.documentPaths = documentPaths
        self.dateAdded = dateAdded
        self.dateModified = dateModified
    }
}

/// Persistent manager for saved Tab Groups — mirrors FavoritesManager's storage approach
/// (UserDefaults-backed JSON) for consistency, at the same, small scale of data.
@MainActor
public final class TabGroupManager: ObservableObject {
    public static let shared = TabGroupManager()
    private let userDefaultsKey = "com.vectorpdf.app.tabgroups"

    @Published public private(set) var groups: [TabGroup] = []

    public init() {
        loadGroups()
    }

    public func loadGroups() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let list = try? JSONDecoder().decode([TabGroup].self, from: data) {
            self.groups = list
        }
    }

    private func saveGroups() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    @discardableResult
    public func addGroup(name: String, documentPaths: [String]) -> TabGroup {
        let group = TabGroup(name: name, documentPaths: documentPaths)
        groups.insert(group, at: 0)
        saveGroups()
        return group
    }

    @discardableResult
    public func removeGroup(_ id: UUID) -> (group: TabGroup, index: Int)? {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = groups.remove(at: idx)
        saveGroups()
        return (removed, idx)
    }

    public func insertGroup(_ group: TabGroup, at index: Int = 0) {
        guard !groups.contains(where: { $0.id == group.id }) else { return }
        let insertIdx = min(max(0, index), groups.count)
        groups.insert(group, at: insertIdx)
        saveGroups()
    }

    /// Overwrites an existing group's document list (and bumps dateModified) — used by "Update
    /// Group" once a saved group's window has had tabs added or removed. Deliberately explicit
    /// rather than automatic: silently rewriting a saved group every time a tab closes would be
    /// surprising, especially for a tab closed by accident.
    public func updateDocumentPaths(for id: UUID, to documentPaths: [String]) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].documentPaths = documentPaths
        groups[idx].dateModified = Date()
        saveGroups()
    }

    public func rename(_ id: UUID, to name: String) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].name = name
        saveGroups()
    }

    public func group(withId id: UUID) -> TabGroup? {
        groups.first { $0.id == id }
    }

    /// Opens every document in `group` as tabs of one new window. See DocumentWindowing.openGroup
    /// for the actual window/tab creation (shared with the app's ordinary Open/Favorite flows).
    public func open(_ group: TabGroup) {
        DocumentWindowing.openGroup(group)
    }
}
