import Foundation
import CodeNavigatorCore
import CodeNavigatorContract

/// Opening a project as one operation.
///
/// The two engine protocols each own half of it: `ProjectSession` moves the index and
/// `EditorSession` moves the buffer's root. Neither expresses that they must move
/// together, and doing only the first leaves the editor resolving paths against the
/// previous root — a failure that surfaces much later as a file that mysteriously will not
/// open (REQ-001 AC-2).
/// **Superseded, kept until the engine implements its replacement.**
///
/// ADR-0106 introduced this so that opening a project could not move the index without
/// moving the editor with it — the two halves live behind different protocols and nothing
/// in the contract said they travel together.
///
/// REQ-012 replaces it: `CodeNavigatorContract.ProjectWorkspace` owns the open projects,
/// their identity and the active one, which is strictly more than this does. That protocol
/// is adopted but the engine does not implement it yet, so this stays as the single-project
/// seam until it does — renamed rather than left sharing a name, because two protocols
/// called `ProjectWorkspace` make "which one opens a project" answerable two ways.
public protocol SingleProjectWorkspace: Sendable {
    func openWorkspace(at projectRoot: URL, columns: Int, rows: Int) async throws
}

extension CodeNavigatorEngine: SingleProjectWorkspace {
    public func openWorkspace(at projectRoot: URL, columns: Int, rows: Int) async throws {
        // The first open has to start Neovim; a later one only redirects the running
        // session, which is what `openProject` does.
        guard await editor.state() == .notStarted else {
            try await openProject(at: projectRoot)
            return
        }
        try await start(projectRoot: projectRoot, columns: columns, rows: rows)
    }
}
