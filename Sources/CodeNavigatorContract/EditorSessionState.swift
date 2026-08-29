/// The edit-session lifecycle from the requirements state table (§6).
///
/// Start-up failure and disconnection are separate cases on purpose. They look alike in a status
/// bar but call for different responses: one is fixed by installing or upgrading Neovim, the
/// other by restarting it. Collapsing them into one string forces the interface to guess.
public enum EditorSessionState: Sendable, Hashable {
    case notStarted
    case connecting
    case connected
    /// Neovim could not be started — missing, unusable, or too old.
    case startupFailed(EditorStartupFailure)
    /// The session was running and stopped. `reason` is displayable as-is (REQ-004 AC-5).
    case disconnected(reason: String)

    /// A state's identity without its payload, so the set of states can be iterated.
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case notStarted
        case connecting
        case connected
        case startupFailed
        case disconnected
    }

    /// No `default`: adding a case fails the build here, beside the list that must grow with it.
    public var kind: Kind {
        switch self {
        case .notStarted: return .notStarted
        case .connecting: return .connecting
        case .connected: return .connected
        case .startupFailed: return .startupFailed
        case .disconnected: return .disconnected
        }
    }

    /// One representative value per state, for tests that claim to cover every state.
    ///
    /// Payload choice: `startupFailed` uses `foundVersion: nil` — Neovim absent rather than too
    /// old — because that is the branch whose message has no version number to show, and so the
    /// one where a formatting mistake surfaces. `disconnected` carries a non-empty reason because
    /// an empty one would let a view that drops the reason still pass.
    public static let allKnownCases: [EditorSessionState] = Kind.allCases.map { kind in
        switch kind {
        case .notStarted:
            return .notStarted
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        case .startupFailed:
            return .startupFailed(
                EditorStartupFailure(
                    reason: "Neovim을 찾을 수 없습니다.",
                    searchedPaths: ["/opt/homebrew/bin/nvim", "/usr/local/bin/nvim"],
                    requiredVersion: "0.9.0",
                    foundVersion: nil
                )
            )
        case .disconnected:
            return .disconnected(reason: "편집 세션이 종료됐습니다.")
        }
    }
}
