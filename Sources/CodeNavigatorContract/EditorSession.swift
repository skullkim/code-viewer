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
    ///
    /// The notation is produced by the application and is the **same in both input modes** — how
    /// it is interpreted is this session's business, not the caller's. That split is what keeps
    /// the standard-mode rules in one place instead of half here and half in the view.
    func sendKeys(_ keys: String) async throws

    /// Forwards a mouse event, which key notation cannot express because it carries no position.
    func sendMouse(_ event: EditorMouseEvent) async throws

    /// Switches the key-interpretation layer. Buffer state is untouched (REQ-010 AC-4).
    func setInputMode(_ mode: InputMode) async throws

    func inputMode() async -> InputMode

    /// Opens a project-relative path, optionally jumping to a 1-based line.
    /// When `recordJump` is true the current position is pushed onto Neovim's jump list first,
    /// so the Vim jump motions return to it (REQ-005 AC-4).
    func openFile(atRelativePath relativePath: String, line: Int?, recordJump: Bool) async throws

    /// Returns to the previous jump-list position.
    func jumpBack() async throws

    /// Moves forward again through the jump list.
    func jumpForward() async throws

    /// Writes the current buffer to disk.
    ///
    /// Neovim performs the write, as it does for every change to a file (INV-3). What this method
    /// guarantees over sending `:w` as keys is that it behaves the same in both input modes:
    /// key notation is interpreted against the editor's current mode, so the same keystrokes mean
    /// different things depending on where the user happens to be — and for a save, that
    /// difference is a file that silently does not get written.
    func save() async throws

    /// Reverses the last change.
    func undo() async throws

    /// Reapplies the last reversed change.
    func redo() async throws

    /// Copies the current selection to the system clipboard.
    func copySelection() async throws

    /// Cuts the current selection to the system clipboard.
    func cutSelection() async throws

    /// Pastes the system clipboard at the cursor.
    func paste() async throws

    /// Selects the whole buffer.
    func selectAll() async throws

    /// The identifier under the cursor, used as the query for go-to-definition and references.
    func wordUnderCursor() async throws -> String?

    /// Files Neovim reports as written, one per `:w`. The engine re-indexes each of them, so an
    /// in-app save is reflected without waiting on the file watcher (REQ-009 AC-5).
    /// Files this project has unsaved changes in, project-relative (W-13's sheet lists them).
    ///
    /// Scoped by root rather than by "the current project", because one Neovim serves every open
    /// project (ADR-0008) and its active tabpage moves whenever the user types `gt`. A session
    /// asked for "the current project" would answer with wherever the cursor happens to be, which
    /// is not the project the user is closing.
    ///
    /// Buffers outside every open project root belong to no tab and are left alone: closing a tab
    /// is no reason to save a file the user opened by hand somewhere else.
    func dirtyFiles(inProjectRoot root: URL) async throws -> [String]

    /// Saves every unsaved buffer belonging to one project.
    ///
    /// Not `:wa` — measured, that writes across tabpage boundaries, so closing one project would
    /// silently write another project's unsaved work to disk without the user approving it. The
    /// buffers are enumerated and saved individually, which is also what makes a per-file result
    /// possible: W-13 keeps its sheet open on failure and has to say *which* files were refused.
    func saveAll(inProjectRoot root: URL) async throws -> SaveAllOutcome

    func savedFiles() async -> AsyncStream<SavedFile>

    func shutDown() async
}
