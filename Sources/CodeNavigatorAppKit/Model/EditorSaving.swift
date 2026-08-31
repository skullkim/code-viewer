import Foundation
import CodeNavigatorCore
import CodeNavigatorContract

/// Saving a whole project's dirty buffers (W-13).
///
/// **Temporary.** `NeovimEditorSession` already implements both of these; they are simply
/// not on the `EditorSession` protocol yet, so the application — which holds the protocol —
/// cannot reach them. Declared here so the close sheet can be wired against real behaviour
/// instead of a stub that would close dirty tabs silently.
///
/// **Delete this file when the two methods move onto `EditorSession`**, and change
/// `AppModel` to call them directly. Asked of backend; this is the seam until then, not a
/// second contract.
protocol EditorSaving: Sendable {
    /// Project-relative paths of buffers with unsaved changes, for this project only.
    func dirtyFiles(inProjectRoot root: URL) async throws -> [String]

    /// Writes every dirty buffer belonging to this project, and says what happened to each.
    ///
    /// Scoped by root rather than "the current project", because one Neovim process serves
    /// every tab (ADR-0008) and therefore has no current project to mean.
    func saveAll(inProjectRoot root: URL) async throws -> SaveAllOutcome
}

extension NeovimEditorSession: EditorSaving {}
