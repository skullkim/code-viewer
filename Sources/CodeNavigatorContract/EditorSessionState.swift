/// The edit-session lifecycle from the requirements state table (§6).
///
/// `disconnected` carries a human-readable reason so the UI can explain the failure
/// and offer a restart, instead of going silently unresponsive (REQ-004 AC-5).
public enum EditorSessionState: Sendable, Hashable {
    case notStarted
    case connecting
    case connected
    case disconnected(reason: String)
}
