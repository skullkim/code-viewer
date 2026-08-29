/// Why the editor could not be started at all.
///
/// Separate from a lost connection because the two need different words and different offers:
/// a missing Neovim needs installation instructions, a crashed one needs a restart button.
/// REQ-NF-005 requires the distinction to reach the user at start-up rather than as a silent
/// failure later.
public struct EditorStartupFailure: Sendable, Hashable {
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
        reason: String,
        searchedPaths: [String],
        requiredVersion: String,
        foundVersion: String? = nil
    ) {
        self.reason = reason
        self.searchedPaths = searchedPaths
        self.requiredVersion = requiredVersion
        self.foundVersion = foundVersion
    }
}
