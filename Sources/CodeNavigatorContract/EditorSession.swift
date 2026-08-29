import Foundation

/// The engine's editing surface: an embedded Neovim process, driven over msgpack-RPC.
///
/// Neovim owns the buffers, the undo history, the dirty state and every write to disk (INV-3).
/// The application sends key input and renders grid snapshots; it never edits text itself and
/// never writes project files.
///
/// The user's own configuration is loaded as-is and never modified (INV-4).
public protocol EditorSession: Sendable {
    /// Starts Neovim for a project root and attaches the UI. Throws `.editorNotInstalled`
    /// or `.editorUnavailable` with a displayable reason rather than hanging (REQ-004 AC-1).
    func start(projectRoot: URL, columns: Int, rows: Int) async throws

    /// Starts a fresh process after a crash, for the restart affordance (REQ-004 AC-5).
    func restart() async throws

    func state() async -> EditorSessionState

    func stateUpdates() async -> AsyncStream<EditorSessionState>

    /// One complete rendered frame per Neovim `flush`.
    func gridUpdates() async -> AsyncStream<EditorGridSnapshot>

    /// Buffer-level status for the status bar and the tree's current-file highlight.
    func statusUpdates() async -> AsyncStream<EditorStatus>

    /// Tells Neovim the visible grid size changed.
    func resizeGrid(columns: Int, rows: Int) async throws

    /// Forwards key input in Neovim's key notation, for example `"ihello<Esc>"`.
    func sendKeys(_ keys: String) async throws

    /// Switches the key-interpretation layer. Buffer state is untouched (REQ-010 AC-4).
    func setInputMode(_ mode: InputMode) async throws

    func inputMode() async -> InputMode

    /// Opens a project-relative path, optionally jumping to a 1-based line.
    /// When `recordJump` is true the current position is pushed onto Neovim's jump list first,
    /// so the Vim jump motions return to it (REQ-005 AC-4).
    func openFile(atRelativePath relativePath: String, line: Int?, recordJump: Bool) async throws

    /// Returns to the previous jump-list position.
    func jumpBack() async throws

    /// The identifier under the cursor, used as the query for go-to-definition and references.
    func wordUnderCursor() async throws -> String?

    /// Absolute paths Neovim reports as written, one per `:w`. The engine re-indexes each of
    /// them, so an in-app save is reflected without waiting on the file watcher (REQ-009 AC-5).
    func savedFilePaths() async -> AsyncStream<String>

    func shutDown() async
}
