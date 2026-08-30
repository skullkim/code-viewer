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
        // other still starting up in the background. The failures are kept apart because the
        // rollback below needs to know *which* half succeeded.
        var indexingFailure: (any Error)?
        var editingFailure: (any Error)?
        do {
            try await indexing
        } catch {
            indexingFailure = error
        }
        do {
            try await editing
        } catch {
            editingFailure = error
        }

        // Without an index this application can do nothing, so a failure there is a failure to
        // open. The editor this attempt may have started belongs to nobody once the caller sees
        // the error: invisible to the application, surviving its shutdown, outliving the app
        // itself. This attempt started it, so this attempt takes it back down.
        if let indexingFailure {
            if editingFailure == nil {
                await editor.shutDown()
            }
            throw indexingFailure
        }

        // An editor failure is deliberately **not** an open failure. W-8 promises the user that
        // the tree, symbol search, references and full-text search keep working without Neovim,
        // and that promise is only kept if the index survives. Throwing here made the application
        // discard an index that had built perfectly well, and the user saw `인덱스 없음` on a
        // project that had just been indexed. The failure is not swallowed — the editor carries it
        // in `state()`, which is exactly what the overlay reads.
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
        // Redirecting a live session is the cheap path. If it refuses, the editor is now pointed
        // at the previous project while the index has moved — a divergence that shows up much
        // later as a file that mysteriously will not open — so the session is rebuilt on the new
        // root rather than left disagreeing. Throwing instead would fail a switch the index has
        // already completed, which is the same mistake `start` used to make.
        if case .connected = await editor.state(),
           (try? await editor.changeProjectRoot(to: projectRoot)) != nil {
            return
        }

        // The editor is not attached: a previous attempt failed, or it never ran. Reopening a
        // project is where a user retries after fixing whatever was wrong, so it has to be a
        // place the editor can come back. Without this, one failed start left the application
        // permanently editor-less — every later open took this path, skipped Neovim entirely,
        // and the app sat there with no child process at all no matter how often the user retried.
        //
        // A failure here stays out of the caller's way for the same reason as in `start`: the
        // project did open, and the editor's own state reports that it did not.
        try? await editor.startReusingAgreedGridSize(projectRoot: projectRoot)
    }

    /// The text a render view draws (REQ-013).
    ///
    /// The **buffer wins** when the editor is holding this file: a preview is usually opened to
    /// see how the thing just typed looks, and drawing the saved copy would show a document
    /// missing that paragraph — wrong, not merely stale. The origin travels with the text so the
    /// view can say which copy this is instead of the fallback being silent.
    ///
    /// This is the only door to project text for rendering, which is what lets INV-6 be a
    /// boundary (`ProjectRelativePath`) rather than a rule each call site has to remember.
    public func renderSource(atRelativePath relativePath: String) async throws -> RenderSource {
        guard let projectRoot = await project.currentProject()?.rootPath else {
            throw NavigatorError.noProjectOpen
        }
        let resolved = try ProjectRelativePath.resolve(relativePath, inProjectRoot: projectRoot)

        if let lines = try? await editor.bufferLines(forFileAt: resolved.url.path) {
            let text = lines.joined(separator: "\n")
            // The same document must not render from one source and refuse from the other, or the
            // limit looks random to the user.
            try Self.checkWithinRenderLimit(byteSize: text.utf8.count, path: resolved.relativePath)
            return RenderSource(path: resolved.relativePath, text: text, origin: .editorBuffer)
        }

        return try Self.readFromDisk(at: resolved)
    }

    private static func readFromDisk(at resolved: ProjectRelativePath) throws -> RenderSource {
        // Size is checked before reading: measuring after the read means the memory is already
        // spent, which is what the limit exists to prevent.
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.url.path),
            let byteSize = attributes[.size] as? Int
        else {
            throw NavigatorError.fileNotReadable(
                path: resolved.relativePath,
                reason: "파일 정보를 읽을 수 없습니다"
            )
        }
        try checkWithinRenderLimit(byteSize: byteSize, path: resolved.relativePath)

        guard let data = try? Data(contentsOf: resolved.url) else {
            throw NavigatorError.fileNotReadable(
                path: resolved.relativePath,
                reason: "파일을 읽을 수 없습니다"
            )
        }
        guard let text = String(data: data, encoding: .utf8) else {
            // Mojibake is worse than a refusal: it looks like the document, so the user blames
            // their own file (REQ-013 AC-6).
            throw NavigatorError.fileNotDecodable(path: resolved.relativePath)
        }

        return RenderSource(path: resolved.relativePath, text: text, origin: .savedFile)
    }

    private static func checkWithinRenderLimit(byteSize: Int, path: String) throws {
        guard byteSize > RenderSource.maximumByteSize else {
            return
        }
        throw NavigatorError.fileTooLarge(
            path: path,
            byteSize: byteSize,
            limit: RenderSource.maximumByteSize
        )
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
