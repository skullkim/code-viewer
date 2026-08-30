import CodeNavigatorContract
import Foundation

/// Several projects open at once (REQ-012).
///
/// Each project gets its own `ProjectEngine` — its own index, watcher and search scope — and they
/// all share one Neovim with a tabpage each (ADR-0008: 15.5MB for four projects against 60.1MB for
/// a process each, against a 150MB budget). Isolation therefore comes from the sessions rather
/// than from Neovim: every surface here is answered by one project's engine and holds no reference
/// to another's, which is what makes INV-5 structural instead of a rule someone has to remember.
/// ADR-0009 records what tabpages do and do not isolate on their own.
///
/// Nothing is discarded when a tab loses focus. The user chose to keep every project indexed so
/// that switching is immediate, so `activate` has no I/O to wait for (AC-2).
public actor ProjectWorkspaceEngine: ProjectWorkspace {
    private let editor: NeovimEditorSession
    private let initialColumns: Int
    private let initialRows: Int

    private var orderedTabs: [ProjectTab] = []
    private var sessions: [ProjectTabIdentifier: ProjectEngine] = [:]
    private var activeIdentifier: ProjectTabIdentifier?
    private var saveObservationTask: Task<Void, Never>?

    public init(columns: Int, rows: Int, editorExecutableOverridePath: String? = nil) {
        self.editor = NeovimEditorSession(executableOverridePath: editorExecutableOverridePath)
        self.initialColumns = max(columns, 1)
        self.initialRows = max(rows, 1)
    }

    /// The shared editing session. One process serves every tab (ADR-0008).
    public var editorSession: NeovimEditorSession { editor }

    // MARK: - Opening

    public func openProject(at rootPath: URL) async throws -> ProjectOpenOutcome {
        let canonical = try Self.canonicalDirectory(at: rootPath)

        // Sameness is decided on the canonical path, so `/tmp/x` and `/private/tmp/x` are one
        // project rather than two tabs that disagree about which is which (AC-5).
        if let existing = orderedTabs.first(where: { $0.rootPath.path == canonical.path }) {
            try? await activate(existing.id)
            return .activatedExisting(existing)
        }

        let identifier = ProjectTabIdentifier()
        let session = ProjectEngine()
        // Indexing failure is an open failure: without an index there is nothing to show. Nothing
        // has been added to the workspace yet, so there is nothing to roll back.
        try await session.openProject(at: canonical)

        sessions[identifier] = session
        let tab = ProjectTab(
            id: identifier,
            displayName: canonical.lastPathComponent,
            rootPath: canonical
        )
        orderedTabs.append(tab)
        activeIdentifier = identifier
        refreshDisambiguators()

        // The editor is an enhancement over the index, never a precondition for it: a project that
        // indexed fine stays open and searchable even when Neovim cannot start, and the editor's
        // own state carries the failure to the overlay (W-8).
        await bringEditorToTab(identifier, root: canonical)
        await beginObservingSavesIfNeeded()

        return .opened(currentTab(identifier) ?? tab)
    }

    // MARK: - Tabs

    public func tabs() async -> [ProjectTab] { orderedTabs }

    public func activeTab() async -> ProjectTab? {
        activeIdentifier.flatMap { currentTab($0) }
    }

    public func activate(_ identifier: ProjectTabIdentifier) async throws {
        guard sessions[identifier] != nil else {
            throw NavigatorError.noProjectOpen
        }
        activeIdentifier = identifier
        try? await editor.activateProjectTab(identifier)
    }

    public func closeTab(_ identifier: ProjectTabIdentifier) async throws {
        guard let session = sessions[identifier] else {
            return
        }
        // The index, the watcher and the editor's tabpage go together. Leaving any of them behind
        // is a project the user believes is closed still holding memory and still watching files.
        await session.closeProject()
        sessions[identifier] = nil
        try? await editor.closeProjectTab(identifier)
        orderedTabs.removeAll { $0.id == identifier }
        refreshDisambiguators()

        if activeIdentifier == identifier {
            activeIdentifier = orderedTabs.last?.id
            if let next = activeIdentifier {
                try? await editor.activateProjectTab(next)
            }
        }
    }

    public func reorderTabs(_ order: [ProjectTabIdentifier]) async {
        // Only a permutation of what is open is honoured. An unknown identifier would otherwise
        // drop a tab from the bar while its project stayed open and indexed, invisible.
        var reordered: [ProjectTab] = []
        for identifier in order {
            if let tab = orderedTabs.first(where: { $0.id == identifier }) {
                reordered.append(tab)
            }
        }
        for tab in orderedTabs where reordered.contains(where: { $0.id == tab.id }) == false {
            reordered.append(tab)
        }
        orderedTabs = reordered
    }

    public func session(for identifier: ProjectTabIdentifier) async -> (any ProjectSession)? {
        sessions[identifier]
    }

    // MARK: - Restoring

    public func restoreTabs(from rootPaths: [URL]) async -> TabRestoreOutcome {
        var restored: [ProjectTab] = []
        var missing: [MissingTab] = []

        for rootPath in rootPaths {
            do {
                let outcome = try await openProject(at: rootPath)
                restored.append(outcome.tab)
            } catch {
                missing.append(
                    MissingTab(
                        displayName: rootPath.lastPathComponent,
                        rootPath: rootPath,
                        reason: Self.restoreFailureReason(for: error, at: rootPath)
                    )
                )
            }
        }
        return TabRestoreOutcome(restored: restored, missing: missing)
    }

    /// A folder that is gone and one that is merely unreadable call for different remedies, so the
    /// reason is preserved rather than flattened into "could not open" (AC-6).
    private static func restoreFailureReason(
        for error: any Error, at rootPath: URL
    ) -> TabRestoreFailureReason {
        if case NavigatorError.projectNotReadable = error {
            return .noPermission
        }
        return FileManager.default.fileExists(atPath: rootPath.path) ? .noPermission : .notFound
    }

    // MARK: - Editor

    private func bringEditorToTab(_ identifier: ProjectTabIdentifier, root: URL) async {
        if await editor.state() != .connected {
            try? await editor.start(projectRoot: root, columns: initialColumns, rows: initialRows)
        }
        guard await editor.state() == .connected else { return }
        try? await editor.openProjectTab(identifier, root: root)
    }

    // MARK: - Keeping indexes in step with saves

    /// Neovim reports every save on one stream for the whole process, so the path decides which
    /// project it belongs to. Handing a save to the wrong project would reindex a file that
    /// project does not contain and leave the one that does stale.
    private func beginObservingSavesIfNeeded() async {
        guard saveObservationTask == nil else { return }
        let savedFiles = await editor.savedFiles()
        saveObservationTask = Task { [weak self] in
            for await saved in savedFiles {
                guard let self else { return }
                await self.reindexSavedFile(atAbsolutePath: saved.path)
            }
        }
    }

    private func reindexSavedFile(atAbsolutePath path: String) async {
        for tab in orderedTabs {
            let prefix = tab.rootPath.path.hasSuffix("/") ? tab.rootPath.path : tab.rootPath.path + "/"
            if path.hasPrefix(prefix) {
                await sessions[tab.id]?.reindexSavedFile(atAbsolutePath: path)
                return
            }
        }
    }

    // MARK: - Cost

    /// What the workspace currently costs (REQ-NF-002, AC-3).
    ///
    /// See `WorkspaceMemoryFootprint` for why a close that frees nothing visible is normal: the
    /// allocator reuses the pages instead of returning them, so growth across repeated open/close
    /// is the question, not whether the number falls.
    public func memoryFootprint() async -> WorkspaceMemoryFootprint {
        var symbolCount = 0
        for session in sessions.values {
            symbolCount += await session.indexStatistics().symbolCount
        }
        return WorkspaceMemoryFootprint(
            processFootprintBytes: Self.processFootprintInBytes(),
            openTabCount: orderedTabs.count,
            indexedSymbolCount: symbolCount
        )
    }

    private static func processFootprintInBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    public func shutDown() async {
        saveObservationTask?.cancel()
        saveObservationTask = nil
        await editor.shutDown()
        for session in sessions.values {
            await session.closeProject()
        }
        sessions.removeAll()
        orderedTabs.removeAll()
        activeIdentifier = nil
    }

    // MARK: - Helpers

    private func currentTab(_ identifier: ProjectTabIdentifier) -> ProjectTab? {
        orderedTabs.first { $0.id == identifier }
    }

    /// Fills in a disambiguator only for names that actually collide, and clears it when the
    /// collision goes away. Shown always it would be noise on every tab; left stale it would name
    /// a conflict that no longer exists.
    private func refreshDisambiguators() {
        var countsByName: [String: Int] = [:]
        for tab in orderedTabs {
            countsByName[tab.displayName, default: 0] += 1
        }
        orderedTabs = orderedTabs.map { tab in
            let isAmbiguous = (countsByName[tab.displayName] ?? 0) > 1
            let parent = tab.rootPath.deletingLastPathComponent().lastPathComponent
            return ProjectTab(
                id: tab.id,
                displayName: tab.displayName,
                rootPath: tab.rootPath,
                disambiguator: isAmbiguous && parent.isEmpty == false ? parent : nil
            )
        }
    }

    /// Resolves symlinks so one directory has one identity, and refuses anything that is not a
    /// readable directory before a tab is created for it.
    private static func canonicalDirectory(at rootPath: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootPath.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw NavigatorError.projectNotFound(path: rootPath.path)
        }
        guard let resolved = realpath(rootPath.path, nil) else {
            throw NavigatorError.projectNotFound(path: rootPath.path)
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }
}
