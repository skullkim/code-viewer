/// Who currently holds a key mapping.
///
/// Deliberately not a boolean. The middle case — Neovim's own default — is the one that has no
/// natural place in a yes/no answer, and it is also the common one: Neovim 0.12 ships `gr`-prefixed
/// defaults out of the box.
enum NeovimKeyMappingOwner: Sendable, Hashable {
    /// The key is free.
    case nobody
    /// Neovim itself put a mapping there. Ours may take its place, for this session only.
    case editorDefault
    /// The user's own configuration put it there. It wins (REQ-015 AC-6).
    case user(scriptPath: String)

    /// The payload-free identity, so a test claiming to cover "every kind" can prove it does.
    enum Kind: String, CaseIterable, Sendable {
        case nobody
        case editorDefault
        case user
    }

    var kind: Kind {
        switch self {
        case .nobody: return .nobody
        case .editorDefault: return .editorDefault
        case .user: return .user
        }
    }
}
