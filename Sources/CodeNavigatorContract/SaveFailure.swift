/// One file that could not be written, and why.
///
/// The reason is Neovim's own message (`E45: 'readonly' option is set`, …) rather than a
/// category of ours. What the user can do differs by reason — a read-only file is a permission
/// they can change, a missing directory is not — and flattening them removes that.
public struct SaveFailure: Sendable, Hashable {
    /// Project-relative, POSIX, like every other path in this contract.
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}
