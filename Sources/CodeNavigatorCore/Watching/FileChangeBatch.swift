/// Accumulates file changes and decides how to apply them.
///
/// This is deliberately pure and has no timer of its own, so every policy decision — coalescing,
/// the bulk threshold, the drop signal — is testable without waiting on wall-clock time.
struct FileChangeBatch {
    /// Above this many pending paths, re-indexing them one by one costs more than one clean
    /// rescan, and a rescan also catches anything the burst hid from us.
    static let bulkChangeThreshold = 50

    private var pendingChanges: [String: FileChangeKind] = [:]
    private var isFullRescanRequested = false

    var pendingCount: Int { pendingChanges.count }

    var isEmpty: Bool { pendingChanges.isEmpty && !isFullRescanRequested }

    /// Records one change. Repeated events for the same path collapse: the newest wins, so an
    /// add-then-modify-then-modify burst becomes one entry.
    mutating func note(path: String, kind: FileChangeKind) {
        pendingChanges[path] = kind
    }

    /// Called when the watcher reports it dropped events, so itemised changes can no longer be
    /// trusted to be complete.
    mutating func requestFullRescan() {
        isFullRescanRequested = true
    }

    /// Takes everything pending and resets, so changes arriving during the work start a new batch.
    mutating func drain() -> FileChangeResolution {
        defer {
            pendingChanges.removeAll()
            isFullRescanRequested = false
        }

        if isFullRescanRequested {
            return .fullRescan
        }
        if pendingChanges.isEmpty {
            return .none
        }
        if pendingChanges.count >= Self.bulkChangeThreshold {
            return .fullRescan
        }
        return .incremental(pendingChanges)
    }
}
