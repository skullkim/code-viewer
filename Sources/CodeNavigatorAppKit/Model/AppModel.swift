import Foundation
import CoreGraphics
import Observation
import CodeNavigatorContract

/// The shell's state, fed by the engine's streams.
///
/// Stream consumption is separated from the handlers on purpose. `start()` spawns the
/// tasks; each `handle(...)` applies one update and is an ordinary synchronous function.
/// That keeps the rules — dropping a stale frame, composing a save message — testable
/// without waiting on a scheduler, which would test the scheduler as much as the rule.
@MainActor
@Observable
public final class AppModel {

    // MARK: Engine state

    public private(set) var indexState: IndexState = .notIndexed
    public private(set) var indexStatistics: IndexStatistics?
    public private(set) var sessionState: EditorSessionState = .notStarted
    public private(set) var editorStatus: EditorStatus?
    public private(set) var gridFrame: GridFrame?
    public private(set) var inputMode: InputMode
    public private(set) var statusMessage: StatusMessage?

    /// Several definitions share the name and the user has to choose (REQ-005 AC-2).
    public private(set) var definitionCandidates: [SymbolDefinition]?

    public private(set) var isOpeningProject = false
    /// The failure from the last open attempt, kept as the error so the presenting view
    /// decides the wording. REQ-001 AC-3: the previous project is still open.
    public private(set) var projectOpenError: (any Error)?

    /// The open project's root, used to show paths relative to it.
    public var projectRootPath: String?

    public let recentProjects: RecentProjectStore
    /// Window chrome the application restores on launch (REQ-011 AC-3).
    public let shell: ShellPreferences

    /// The file tree, which asks the engine on the user's rhythm rather than the engine's.
    public let fileTree: FileTreeModel

    /// The open projects, as tabs (REQ-012, ADR-0107).
    ///
    /// The tab bar is the only place the open project's name appears now that the toolbar's
    /// project popup is gone (02b C-1, §12 ruling 1), so this is not decoration.
    ///
    /// **Currently holds at most one tab.** The engine still exposes a single
    /// `ProjectSession` with no `ProjectOpenOutcome`, so a second project would replace the
    /// first's index rather than sit beside it — AC-2's instant switching and INV-5's
    /// isolation need the per-project sessions `03c` adopted but that are not built yet.
    /// The shape is here so that arrival is a small change; the capability is not claimed.
    public let tabs = ProjectTabSet()

    /// Distinguishes one shown message from the next, so a timer started for an earlier
    /// message cannot wipe a later one off the bar.
    private(set) var statusMessageToken = 0

    // MARK: Collaborators

    private let projectSession: ProjectSession
    private let editorSession: EditorSession
    private let workspace: SingleProjectWorkspace
    private let storage: KeyValueStore
    private var streamTasks: [Task<Void, Never>] = []
    private var statusMessageExpiryTask: Task<Void, Never>?

    static let inputModeStorageKey = "inputMode"

    /// The grid size a project is opened with, before the editor view has been laid out and
    /// can report the real one. Neovim refuses a zero-sized UI, so it needs a number now;
    /// the first `resizeGrid` from the view corrects it.
    static let initialGridColumns = 80
    static let initialGridRows = 24

    public init(
        projectSession: ProjectSession,
        editorSession: EditorSession,
        workspace: SingleProjectWorkspace,
        storage: KeyValueStore,
        now: @escaping @Sendable () -> Date
    ) {
        self.projectSession = projectSession
        self.editorSession = editorSession
        self.workspace = workspace
        self.storage = storage
        self.recentProjects = RecentProjectStore(storage: storage, now: now)
        self.shell = ShellPreferences(storage: storage)
        self.fileTree = FileTreeModel(projectSession: projectSession, editorSession: editorSession)
        // REQ-010 AC-6: the chosen mode comes back after a restart. Vim is the default,
        // and unreadable stored data falls back to it rather than refusing to launch.
        self.inputMode = Self.storedInputMode(in: storage) ?? .vim
    }

    // MARK: Stream wiring

    /// Subscribes to every engine stream. Each update lands on the main actor.
    public func start() {
        streamTasks.append(Task { [weak self] in
            guard let self else { return }
            for await state in await projectSession.indexStateUpdates() {
                self.handle(indexState: state)
            }
        })
        streamTasks.append(Task { [weak self] in
            guard let self else { return }
            for await state in await editorSession.stateUpdates() {
                self.handle(sessionState: state)
            }
        })
        streamTasks.append(Task { [weak self] in
            guard let self else { return }
            for await snapshot in await editorSession.gridUpdates() {
                self.handle(snapshot: snapshot)
            }
        })
        streamTasks.append(Task { [weak self] in
            guard let self else { return }
            for await status in await editorSession.statusUpdates() {
                self.handle(editorStatus: status)
            }
        })
        streamTasks.append(Task { [weak self] in
            guard let self else { return }
            for await file in await editorSession.savedFiles() {
                self.handle(savedFile: file)
            }
        })
    }

    public func stop() {
        streamTasks.forEach { $0.cancel() }
        streamTasks.removeAll()
    }

    // MARK: Handlers

    public func handle(indexState state: IndexState) {
        let wasWorking = indexState.isWorking
        indexState = state

        // The statistics only change when a pass finishes, so that is when they are read.
        // Without this the index details popover stays empty for ever, and `skippedCount`
        // is the only place REQ-002 AC-4 becomes visible to a user.
        if state == .ready, wasWorking || indexStatistics == nil {
            Task { await refreshIndexStatistics() }
        }
        // The tab bar's spinner reads this. Kept in step here rather than derived in the
        // view, so the bar and the status chip cannot disagree about whether indexing runs.
        tabs.activeTab?.setIndexState(state)
    }

    public func handle(sessionState state: EditorSessionState) {
        sessionState = state
    }

    public func handle(editorStatus status: EditorStatus) {
        editorStatus = status
        // The tree marks the file being edited (REQ-003 AC-3); it learns which one only
        // from here, because the editor is the side that knows.
        fileTree.updateCurrentFile(absolutePath: status.filePath, isDirty: status.isDirty)
    }

    public func handle(snapshot: EditorGridSnapshot) {
        // Revisions increase monotonically, so anything not newer than what is on screen
        // is a frame that lost its race. Drawing it would make the editor flicker
        // backwards.
        if let current = gridFrame, snapshot.revision <= current.revision {
            return
        }
        gridFrame = GridFrameBuilder.build(from: snapshot)
    }

    public func handle(savedFile file: SavedFile) {
        let name = PathDisplay.fileName(file.path)
        let size = ByteSizeText.string(fromByteCount: file.byteSize)
        show(StatusMessage(kind: .success, text: "✓ 저장됨 · \(name) (\(file.lineCount)줄, \(size))"))
    }

    // MARK: Status messages

    /// Shows a message and schedules its own removal (design §3 W-7: 2s for a success,
    /// 3s for an error).
    public func show(_ message: StatusMessage) {
        statusMessageToken += 1
        let token = statusMessageToken
        statusMessage = message

        statusMessageExpiryTask?.cancel()
        statusMessageExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(StatusMessageDuration.seconds(for: message.kind)))
            self?.clearStatusMessage(ifToken: token)
        }
    }

    /// Removes the message only if it is still the one that was shown.
    func clearStatusMessage(ifToken token: Int) {
        guard token == statusMessageToken else {
            return
        }
        statusMessage = nil
    }

    public func clearStatusMessage() {
        statusMessage = nil
    }

    // MARK: Commands

    /// Switches the key-interpretation layer (REQ-010).
    ///
    /// Only the interpretation changes. Neovim keeps the buffer, the undo history and the
    /// dirty state in both modes, so this can never fork editor state or trigger a save.
    public func setInputMode(_ mode: InputMode) async {
        inputMode = mode
        storage.setData(mode.rawValue.data(using: .utf8), forKey: Self.inputModeStorageKey)
        try? await editorSession.setInputMode(mode)
    }

    public func toggleInputMode() async {
        await setInputMode(inputMode == .vim ? .standard : .vim)
    }

    public func restartEditSession() async {
        try? await editorSession.restart()
    }

    public func refreshIndexStatistics() async {
        indexStatistics = await projectSession.indexStatistics()
    }

    // MARK: Editor input (REQ-004 AC-2, REQ-010 AC-1)

    /// Whether keys aimed at the editor are dropped rather than delivered.
    ///
    /// The rule lives here rather than in the view because it is the same rule the overlay
    /// is drawn from, and two copies of it would eventually disagree. Dropping is chosen
    /// over queueing so nothing is replayed into a session that may never arrive.
    public var isEditorInputBlocked: Bool {
        editSessionOverlay?.blocksKeyInput ?? false
    }

    public func sendKeys(_ notation: String) async {
        guard !isEditorInputBlocked else {
            return
        }
        try? await editorSession.sendKeys(notation)
    }

    public func sendMouse(_ event: EditorMouseEvent) async {
        guard !isEditorInputBlocked else {
            return
        }
        try? await editorSession.sendMouse(event)
    }

    /// Tells the editor how many cells it now has.
    ///
    /// Not gated on the input rule: a resize is not something the user typed, and a
    /// session that reconnects into a stale grid size draws into the wrong shape.
    public func resizeGrid(columns: Int, rows: Int) async {
        try? await editorSession.resizeGrid(columns: columns, rows: rows)
    }

    // MARK: Go to definition (REQ-005)

    public func goToDefinition() async {
        let word = (try? await editorSession.wordUnderCursor()) ?? nil
        let name = (word ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // A blank query is not a question worth asking the index; the routing rule already
        // knows what to say about it.
        let definitions = name.isEmpty ? [] : await projectSession.definitions(named: name)

        switch DefinitionRouting.route(symbolName: name, definitions: definitions) {
        case .navigate(let path, let line):
            await open(path: path, line: line)

        case .presentCandidates(let candidates):
            definitionCandidates = candidates

        case .reportNotFound(let message), .reportNoSymbolUnderCursor(let message):
            show(StatusMessage(kind: .error, text: message))
        }
    }

    public func openDefinition(_ definition: SymbolDefinition) async {
        definitionCandidates = nil
        await open(path: definition.path, line: definition.line)
    }

    public func dismissDefinitionCandidates() {
        definitionCandidates = nil
    }

    /// Opens a project-relative location, recording the jump.
    ///
    /// Used by the definition picker and by both result panels, so that every way of
    /// arriving somewhere leaves the same trail back (REQ-005 AC-4).
    public func openLocation(path: String, line: Int?) async {
        await open(path: path, line: line)
    }

    /// Returns to the previous jump-list position (REQ-005 AC-4).
    ///
    /// Goes through the engine rather than sending `<C-o>`, because the raw key means
    /// different things in the two input modes: in standard mode Neovim is in insert, where
    /// `<C-o>` waits for one normal command and silently eats the user's next keystroke.
    /// The engine wraps it in `normal!`, which behaves the same in both.
    public func jumpBack() async {
        try? await editorSession.jumpBack()
    }

    /// The editing commands, each routed to the engine rather than sent as a key string.
    ///
    /// A raw normal-mode key means something else entirely in standard mode, where Neovim
    /// is held in insert so the user can type `i`, `:` and `hjkl` as letters (REQ-010 AC-5).
    /// Measured against a real Neovim: `u` typed the letter u into the buffer, and `:w<CR>`
    /// did not save — a save that reports success and writes nothing. The engine wraps each
    /// of these so they behave the same in both modes.
    public func jumpForward() async { try? await editorSession.jumpForward() }
    public func save() async { try? await editorSession.save() }
    public func undo() async { try? await editorSession.undo() }
    public func redo() async { try? await editorSession.redo() }
    public func copySelection() async { try? await editorSession.copySelection() }
    public func cutSelection() async { try? await editorSession.cutSelection() }
    public func paste() async { try? await editorSession.paste() }
    public func selectAll() async { try? await editorSession.selectAll() }

    /// The identifier under the cursor, for the commands that start from it.
    public func wordUnderCursor() async -> String? {
        (try? await editorSession.wordUnderCursor()) ?? nil
    }

    private func open(path: String, line: Int?) async {
        // The jump is recorded so ⌃O leads back to where it started (REQ-005 AC-4).
        try? await editorSession.openFile(atRelativePath: path, line: line, recordJump: true)
    }

    // MARK: Opening a project (REQ-001)

    public func openProject(at projectRoot: URL) async {
        isOpeningProject = true
        projectOpenError = nil
        defer { isOpeningProject = false }

        do {
            try await workspace.openWorkspace(
                at: projectRoot,
                columns: Self.initialGridColumns,
                rows: Self.initialGridRows
            )
        } catch {
            // REQ-001 AC-3: nothing about the open project changes. The tree, the root and
            // the edit session are all left exactly as they were.
            projectOpenError = error
            forgetRecentProjectIfGone(error: error, path: projectRoot.path)
            return
        }

        projectRootPath = projectRoot.path
        recentProjects.recordOpened(rootPath: projectRoot.path)
        openTab(for: projectRoot)
        await fileTree.loadProject(name: projectRoot.lastPathComponent, rootPath: projectRoot.path)
    }

    /// Closes the open project, returning the window to the welcome screen (§3 W-2).
    ///
    /// The edit session is left alone. Whether an unsaved buffer should be discarded is
    /// Neovim's decision, not the application's (INV-3).
    /// Adds the tab for a project that opened, or activates the one already showing it.
    ///
    /// Identity comes from `ProjectIdentity`, not from the path as typed: two spellings of
    /// one directory must share a tab (REQ-012 AC-5), and comparing the raw strings is how
    /// the same project ends up open twice.
    private func openTab(for projectRoot: URL) {
        let path = projectRoot.path
        let identity = ProjectIdentity.canonical(
            for: path,
            isCaseSensitiveVolume: ProjectIdentity.isCaseSensitiveVolume(at: path)
        )
        tabs.open(ProjectTabState(
            id: identity,
            rootPath: path,
            name: projectRoot.lastPathComponent,
            projectSession: projectSession,
            editorSession: editorSession
        ))
        tabs.activeTab?.setIndexState(indexState)
    }

    public func closeProject() async {
        if let active = tabs.activeTabID {
            tabs.close(id: active)
        }
        projectRootPath = nil
        projectOpenError = nil
        definitionCandidates = nil
        indexStatistics = nil
        await fileTree.loadProject(name: nil, rootPath: nil)
    }

    public func dismissProjectOpenError() {
        projectOpenError = nil
    }

    /// Drops a recent entry whose folder is gone (design §3 W-2).
    ///
    /// Only for a path that no longer exists. A folder that is merely unreadable is still
    /// the project the user meant, and removing it would make a permissions problem look
    /// like a lost project.
    private func forgetRecentProjectIfGone(error: any Error, path: String) {
        guard case NavigatorError.projectNotFound = error else {
            return
        }
        recentProjects.remove(rootPath: path)
    }

    // MARK: Derived presentation

    public func statusBar(for layout: ShellLayout) -> StatusBarPresentation {
        StatusBarPresentation.make(
            sessionState: sessionState,
            editorStatus: editorStatus,
            indexState: indexState,
            inputMode: inputMode,
            message: statusMessage,
            projectRoot: projectRootPath,
            layout: layout
        )
    }

    public var menuAvailability: MenuAvailability {
        MenuAvailability(
            inputMode: inputMode,
            sessionState: sessionState,
            hasOpenProject: projectRootPath != nil
        )
    }

    public var editSessionOverlay: EditSessionOverlay? {
        EditSessionOverlay.make(for: sessionState)
    }

    private static func storedInputMode(in storage: KeyValueStore) -> InputMode? {
        guard let data = storage.data(forKey: inputModeStorageKey),
              let raw = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return InputMode(rawValue: raw)
    }
}
