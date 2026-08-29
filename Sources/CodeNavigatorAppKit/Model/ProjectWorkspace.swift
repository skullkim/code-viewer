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
public protocol ProjectWorkspace: Sendable {
    func openWorkspace(at projectRoot: URL, columns: Int, rows: Int) async throws
}

extension CodeNavigatorEngine: ProjectWorkspace {
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
