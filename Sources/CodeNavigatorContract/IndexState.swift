/// The index lifecycle from the requirements state table (§6).
///
/// Queries are answered in every state — while a rebuild is in flight the previous index
/// still answers, and the UI shows that an update is running.
public enum IndexState: Sendable, Hashable {
    case notIndexed
    case indexing(IndexProgress)
    case ready
    case updating
    case rescanning(IndexProgress)

    /// True while the index is being built or refreshed, for a "updating…" affordance.
    public var isWorking: Bool {
        switch self {
        case .indexing, .updating, .rescanning:
            return true
        case .notIndexed, .ready:
            return false
        }
    }

    /// Progress to display, when the current state carries any.
    public var progress: IndexProgress? {
        switch self {
        case .indexing(let progress), .rescanning(let progress):
            return progress
        case .notIndexed, .ready, .updating:
            return nil
        }
    }
}
