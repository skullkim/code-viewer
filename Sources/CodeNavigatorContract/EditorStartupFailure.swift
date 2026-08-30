/// Why the editor could not be started at all.
///
/// Separate from a lost connection because the two need different words and different offers:
/// a missing Neovim needs installation instructions, a crashed one needs a restart button.
/// REQ-NF-005 requires the distinction to reach the user at start-up rather than as a silent
/// failure later.
/// Why start-up failed, as a category the interface can branch on.
///
/// The distinction is not cosmetic: each one sends the user somewhere different. Telling someone
/// their editor is missing when it is installed and running sends them to reinstall software they
/// already have — which is what happened before this existed.
public enum EditorStartupFailureKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// No executable found anywhere the engine looked.
    case notInstalled
    /// Found and runnable, but older than this application needs.
    case versionTooOld
    /// The executable exists and the process spawned, but it never completed the handshake.
    /// Not a missing editor — a slow or wedged one.
    case unresponsive
    /// The process could not be spawned at all (permissions, corrupt binary).
    case launchFailed
}

public struct EditorStartupFailure: Sendable, Hashable {
    /// What kind of failure this is. Branch on this, not on `foundVersion == nil` — a timeout
    /// also has no version, and reading it as "not installed" is how the wrong message got shown.
    public let kind: EditorStartupFailureKind
    /// One line the interface can show as-is.
    public let reason: String
    /// Where the engine looked, so the user can see why their install was missed.
    public let searchedPaths: [String]
    /// The minimum version this application needs.
    public let requiredVersion: String
    /// The version actually found, when one was found but is too old. `nil` means nothing was
    /// found at all — which is a different message from "yours is too old".
    public let foundVersion: String?

    public init(
        kind: EditorStartupFailureKind,
        reason: String,
        searchedPaths: [String],
        requiredVersion: String,
        foundVersion: String? = nil
    ) {
        self.kind = kind
        self.reason = reason
        self.searchedPaths = searchedPaths
        self.requiredVersion = requiredVersion
        self.foundVersion = foundVersion
    }
}
