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
}
