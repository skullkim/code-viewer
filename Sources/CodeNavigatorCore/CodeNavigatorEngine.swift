import CodeNavigatorContract
import Foundation

/// Assembles the engine and connects its two halves.
///
/// The application talks to `project` and `editor` through their contract protocols; this type
/// exists to own them and to make one connection the protocols deliberately do not express:
/// when Neovim writes a file, that file is re-indexed immediately.
///
/// That connection matters because the file watcher alone would be both slower and less certain.
/// Neovim knows exactly which path it just wrote, so the save path needs no debounce and no
/// guessing about which of a burst of events was the save (REQ-009 AC-5).
public final class CodeNavigatorEngine: Sendable {
    public let project: ProjectEngine
    public let editor: NeovimEditorSession

    private let saveObservationTask: SaveObservationTaskBox

    public init(editorExecutableOverridePath: String? = nil) {
        let project = ProjectEngine()
        let editor = NeovimEditorSession(executableOverridePath: editorExecutableOverridePath)
        self.project = project
        self.editor = editor
        self.saveObservationTask = SaveObservationTaskBox()
    }

    /// Opens a project and starts the editor on it, then keeps the index in step with saves.
    ///
    /// Indexing and editor start-up run concurrently: neither needs the other, and the user can
    /// begin typing while the index is still building (REQ-NF-003).
    public func start(projectRoot: URL, columns: Int, rows: Int) async throws {
        async let indexing: Void = project.openProject(at: projectRoot)
        async let editing: Void = editor.start(projectRoot: projectRoot, columns: columns, rows: rows)

        // Both are awaited before either failure is thrown, so one failing half cannot leave the
        // other still starting up in the background.
        var startFailure: (any Error)?
        do {
            try await indexing
        } catch {
            startFailure = error
        }
        do {
            try await editing
        } catch {
            startFailure = startFailure ?? error
        }
        if let startFailure {
            throw startFailure
        }

        await beginObservingSaves()
    }

    /// Switches to another project, moving the index, the tree, the search scope **and the
    /// editor** together (REQ-001 AC-2).
    ///
    /// Call this rather than `project.openProject(at:)` directly: opening a project only on the
    /// project side would leave the editor resolving paths against the previous root, which shows
    /// up much later as a file that mysteriously fails to open.
    ///
    /// A failure to scan the new project leaves everything as it was (REQ-001 AC-3): the index is
    /// only replaced after the scan succeeds, and the editor is only redirected after that.
    public func openProject(at projectRoot: URL) async throws {
        try await project.openProject(at: projectRoot)
        if case .connected = await editor.state() {
            try await editor.changeProjectRoot(to: projectRoot)
        }
    }

    public func shutDown() async {
        await saveObservationTask.cancel()
        await editor.shutDown()
        await project.closeProject()
    }

    private func beginObservingSaves() async {
        let savedFiles = await editor.savedFiles()
        let project = self.project
        await saveObservationTask.replace(with: Task {
            for await saved in savedFiles {
                await project.reindexSavedFile(atAbsolutePath: saved.path)
            }
        })
    }
}

/// Holds the save-observation task so the engine itself can stay immutable and `Sendable`.
private actor SaveObservationTaskBox {
    private var task: Task<Void, Never>?

    func replace(with newTask: Task<Void, Never>) {
        task?.cancel()
        task = newTask
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
