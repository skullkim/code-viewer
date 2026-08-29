import Foundation

/// A project the user opened before.
public struct RecentProject: Sendable, Hashable, Codable, Identifiable {
    public let name: String
    public let rootPath: String
    public let lastOpenedAt: Date

    public var id: String { rootPath }

    public init(name: String, rootPath: String, lastOpenedAt: Date) {
        self.name = name
        self.rootPath = rootPath
        self.lastOpenedAt = lastOpenedAt
    }
}

/// Remembers the projects the user opened, newest first.
///
/// This is shell state, not engine state: REQ-011 AC-3 lists it beside window size and
/// split ratios, all of which the application restores on launch. The indexing engine
/// stays concerned with indexing.
///
/// The clock is injected because "most recent" is the whole point of the list, and a test
/// that depends on wall-clock ordering is a test that fails on a slow morning.
public final class RecentProjectStore: @unchecked Sendable {

    public static let storageKey = "recentProjects"

    /// Design §3 W-2: at most five entries.
    public static let maximumCount = 5

    private let storage: KeyValueStore
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(storage: KeyValueStore, now: @escaping @Sendable () -> Date) {
        self.storage = storage
        self.now = now
    }

    public func projects() -> [RecentProject] {
        lock.lock()
        defer { lock.unlock() }
        return loaded()
    }

    public func recordOpened(rootPath: String) {
        lock.lock()
        defer { lock.unlock() }

        let path = Self.normalised(rootPath)
        let entry = RecentProject(
            name: (path as NSString).lastPathComponent,
            rootPath: path,
            lastOpenedAt: now()
        )

        var entries = loaded().filter { $0.rootPath != path }
        entries.insert(entry, at: 0)
        save(Array(entries.prefix(Self.maximumCount)))
    }

    /// Drops an entry whose path no longer resolves, so the list stops offering a dead door.
    public func remove(rootPath: String) {
        lock.lock()
        defer { lock.unlock() }
        let path = Self.normalised(rootPath)
        save(loaded().filter { $0.rootPath != path })
    }

    private func loaded() -> [RecentProject] {
        guard let data = storage.data(forKey: Self.storageKey) else {
            return []
        }
        // Stored preferences are untrusted input. Losing the recent list is a much better
        // outcome than refusing to launch (REQ-NF-004), so damaged data reads as empty.
        guard let entries = try? JSONDecoder().decode([RecentProject].self, from: data) else {
            return []
        }
        return entries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    private func save(_ entries: [RecentProject]) {
        storage.setData(try? JSONEncoder().encode(entries), forKey: Self.storageKey)
    }

    private static func normalised(_ path: String) -> String {
        var result = (path as NSString).standardizingPath
        if result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
