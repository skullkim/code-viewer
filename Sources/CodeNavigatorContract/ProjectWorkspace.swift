import Foundation

/// Several projects open at once, one tab each (REQ-012).
///
/// The engine owns which projects are open and which one is active; the application draws that.
/// Each tab keeps its own index for as long as it is open — the user chose "keep everything" so
/// that switching is immediate, so nothing here discards an index to save memory (AC-2).
///
/// Isolation between tabs is real but has a measured boundary: every surface this protocol
/// exposes is scoped to one project, while Neovim's own buffer list and registers are process
/// global. ADR-0009 records what was measured and why the boundary is drawn where it is.
public protocol ProjectWorkspace: Sendable {
    /// Opens a project, or brings it forward if it is already open (AC-5).
    ///
    /// Sameness is decided on the **canonical** root, so two spellings of one directory are one
    /// project. That normalisation is the engine's, and `ProjectTab.rootPath` is its answer.
    func openProject(at rootPath: URL) async throws -> ProjectOpenOutcome

    /// Open tabs in the user's order.
    func tabs() async -> [ProjectTab]

    func activeTab() async -> ProjectTab?

    /// Brings a tab forward. There is no I/O to wait for — the index is already in memory (AC-2).
    func activate(_ identifier: ProjectTabIdentifier) async throws

    /// Closes a tab and releases its index, watcher and editor state together (AC-3).
    func closeTab(_ identifier: ProjectTabIdentifier) async throws

    /// Reorders tabs after the user drags one.
    func reorderTabs(_ order: [ProjectTabIdentifier]) async

    /// The index, tree and search for one tab. `nil` once that tab is closed.
    func session(for identifier: ProjectTabIdentifier) async -> (any ProjectSession)?

    /// The document a render view draws, for one tab (REQ-013).
    ///
    /// Named by tab rather than inferred from what is active: the active tabpage moves whenever
    /// the user types `gt`, and two tabs can both hold a `README.md`, so an inference is wrong in
    /// the way that looks right.
    func renderSource(
        atRelativePath relativePath: String, in identifier: ProjectTabIdentifier
    ) async throws -> RenderSource

    /// The bytes of a resource a rendered document refers to — an image, a font.
    ///
    /// The same door as the document on purpose. A renderer that read its own images would enforce
    /// INV-6's root restriction a second way, and the danger is not two readers but **two rules**:
    /// the weaker becomes the real boundary the day they drift.
    ///
    /// Failures keep their reason (`fileNotFound` / `fileTooLarge` / `invalidPath` /
    /// `fileNotReadable`). An adapter that collapses them into `nil` makes "not there", "too large"
    /// and "outside the project" one event, and the sandbox chip can no longer say which happened.
    func renderResource(
        atRelativePath relativePath: String, in identifier: ProjectTabIdentifier
    ) async throws -> Data

    /// Reopens a saved set, naming what could not be reopened rather than dropping it (AC-4, AC-6).
    ///
    /// `activeRootPath` is where the user was when they quit. Without it the restored window shows
    /// whichever project happened to be restored last, which is not the same thing — AC-4 asks for
    /// the list **and** the active tab. When that project is one of the ones that went missing,
    /// the first surviving tab takes over rather than leaving the window blank under a full tab bar.
    func restoreTabs(from rootPaths: [URL], activeRootPath: URL?) async -> TabRestoreOutcome
}
