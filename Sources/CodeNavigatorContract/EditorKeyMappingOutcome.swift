/// What the session decided about one navigation key, and why (REQ-015 AC-6).
///
/// This is on the contract so that "we did not overwrite the user's mapping" can be checked
/// without reading Neovim's internals. A requirement nobody outside the engine can measure is
/// one that gets asserted rather than verified.
public struct EditorKeyMappingOutcome: Sendable, Hashable, Codable {

    /// Three separate facts. They are **not** one boolean.
    ///
    /// Folding them loses in both directions: read Neovim's own default as the user's and our
    /// keys never get installed (AC-1 and AC-2 quietly do nothing); read the user's as an empty
    /// slot and we overwrite it (AC-6 quietly does nothing). Neither failure announces itself.
    public enum Resolution: String, Sendable, Hashable, Codable, CaseIterable {
        /// Nothing held the key, so the session installed its mapping.
        case installed
        /// Neovim's own default held it. The session replaced it for this process only.
        case replacedEditorDefault
        /// The user's configuration holds it. The session installed nothing (AC-6).
        case deferredToUserMapping
        /// The user's configuration holds a **longer key starting with this one**, so installing
        /// here would make theirs wait out `timeoutlen` on every press. The session installed
        /// nothing rather than slow their key down or delete it (AC-7, AC-8).
        ///
        /// Distinct from `deferredToUserMapping`: there the user owns *this* key, here they own
        /// a different one. The application can only explain the absence correctly if it can
        /// tell the two apart.
        case withheldToKeepUserPrefixKeys
    }

    /// The key sequence, in Neovim's notation — `"gd"`, `"gr"`.
    public let keys: String
    public let request: EditorNavigationRequest
    public let resolution: Resolution
    /// Which file's mapping won. Present for `deferredToUserMapping` and
    /// `withheldToKeepUserPrefixKeys`.
    public let userScriptPath: String?
    /// The user's longer keys that this one would have shadowed. Only for
    /// `withheldToKeepUserPrefixKeys`; empty otherwise.
    public let conflictingKeys: [String]

    public init(
        keys: String,
        request: EditorNavigationRequest,
        resolution: Resolution,
        userScriptPath: String? = nil,
        conflictingKeys: [String] = []
    ) {
        self.keys = keys
        self.request = request
        self.resolution = resolution
        self.userScriptPath = userScriptPath
        self.conflictingKeys = conflictingKeys
    }
}
