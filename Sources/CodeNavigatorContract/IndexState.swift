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

    /// A state's identity without its payload.
    ///
    /// `CaseIterable` cannot be synthesised for an enum carrying associated values, so this
    /// payload-free twin carries the iteration instead. It also lets a caller ask "is this still
    /// the same state?" without comparing progress numbers that change every few files.
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case notIndexed
        case indexing
        case ready
        case updating
        case rescanning
    }

    /// This switch has **no `default`**, so adding a case to `IndexState` fails the build right
    /// here — in the same file as `allKnownCases`, which must then be updated too.
    public var kind: Kind {
        switch self {
        case .notIndexed: return .notIndexed
        case .indexing: return .indexing
        case .ready: return .ready
        case .updating: return .updating
        case .rescanning: return .rescanning
        }
    }

    /// One representative value per state, for tests that claim to cover *every* state.
    ///
    /// A hand-written list silently omits whatever is added next, which is how a new state ends
    /// up with no staleness notice and no chip while four tests stay green. Deriving it from
    /// `Kind.allCases` through a `default`-less switch removes that possibility: a new case
    /// cannot compile until it appears here.
    ///
    /// Payload choice: the progress-carrying states use `total: 0`, the boundary meaning "the
    /// file list is still being built", because that is the value most likely to divide by zero
    /// or render as an empty bar.
    public static let allKnownCases: [IndexState] = Kind.allCases.map { kind in
        switch kind {
        case .notIndexed: return .notIndexed
        case .indexing: return .indexing(IndexProgress(completed: 0, total: 0))
        case .ready: return .ready
        case .updating: return .updating
        case .rescanning: return .rescanning(IndexProgress(completed: 0, total: 0))
        }
    }
}
