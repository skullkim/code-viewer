/// Which key-interpretation layer is active (REQ-010).
///
/// Only the interpretation of key input changes. The buffer, the file, the undo history and
/// the dirty state stay owned by Neovim in both modes (INV-3), so toggling can never fork
/// editor state or trigger a save.
public enum InputMode: String, Sendable, Codable, Hashable, CaseIterable {
    /// Keys are forwarded to Neovim unmodified. The default.
    case vim
    /// Keys are translated to the macOS editing conventions before being forwarded.
    case standard
}
