/// What Neovim answered when asked who holds a key.
///
/// Only the fields the decision needs. Keeping this a plain value is what lets the decision be
/// tested without an editor: gathering facts and judging them are different jobs, and the one
/// that is easy to get wrong is the judging.
struct NeovimKeyMappingReport: Sendable, Hashable {
    /// Whether any mapping holds the key at all.
    let isPresent: Bool
    /// Neovim's script identifier for whatever defined it. Non-positive means it came from
    /// inside the editor rather than from a sourced script — measured: its own defaults report `-8`.
    let scriptIdentifier: Int
    /// Where that script lives, with symbolic links already resolved. `nil` when Neovim could
    /// not name one.
    let scriptPath: String?
}
