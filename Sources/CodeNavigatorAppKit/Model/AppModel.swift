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
    /// 에디터가 말하는 현재 파일. **바뀌면 렌더가 따라간다** — 기억해서 부르는 게 아니라
    /// 값이 바뀌는 자리에 붙여 둔다.
    ///
    /// 호출로 두면 잊힌다. 실제로 잊혀 있었다: 알려 주는 호출이 토글과 한 곳뿐이라 파일을
    /// 열어도 렌더 모델은 아무것도 모르는 상태에 남았고, 그 상태가 화면에는
    /// **"이 파일에는 내용이 없습니다"** 로 나왔다. 헤더는 이 값을 반응형으로 읽어 따라가고
    /// 본문만 안 따라가니, **화면 둘이 서로 다른 파일을 말했다.**
    public private(set) var editorStatus: EditorStatus? {
        didSet { syncRenderDocument() }
    }
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
    /// 활성 탭의 루트. 탭이 바뀌면 여기가 바뀌고, **렌더도 같이 옮겨 간다.**
    ///
    /// 탭 전환 경로가 네 곳인데 그 전부에서 렌더 갱신을 기억해야 한다면 하나는 반드시
    /// 빠진다 — 그리고 빠진 그 경로에서만 본문이 직전 탭의 문서를 말한다.
    public var projectRootPath: String? {
        didSet { syncRenderDocument() }
    }

    public let recentProjects: RecentProjectStore
    /// Window chrome the application restores on launch (REQ-011 AC-3).
    public let shell: ShellPreferences

    /// The file tree, which asks the engine on the user's rhythm rather than the engine's.
    /// The active tab's tree, or an empty one when no project is open.
    ///
    /// Forwarded rather than owned: the tree belongs to the tab (ADR-0107), and every view
    /// that reads `model.fileTree` keeps working because the name did not move — only what
    /// stands behind it.
    public var fileTree: FileTreeModel {
        tabs.activeTab?.fileTree ?? emptyFileTree
    }

    /// Shown while the welcome screen is up. Never loads a project.
    private let emptyFileTree: FileTreeModel

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

    private let editorSession: EditorSession
    /// The open projects, owned by the engine (REQ-012).
    ///
    /// One session per project lives behind this, which is what lets two projects be open
    /// at once with both indexes in memory — the thing AC-2's "즉시 전환" needs and the
    /// single-project seam could not give.
    private let workspace: any ProjectWorkspace
    private let storage: KeyValueStore
    private var streamTasks: [Task<Void, Never>] = []
    /// One index subscription per open tab.
    private var indexWatchers: [ProjectTabIdentifier: Task<Void, Never>] = [:]

    /// Projects that were open last time and could not be reopened (REQ-012 AC-6).
    ///
    /// Kept rather than dropped: silently forgetting a project is indistinguishable from
    /// the application losing it, and the user cannot tell whether their folder moved or
    /// something went wrong here.
    public private(set) var missingTabs: [MissingTab] = []
    private var statusMessageExpiryTask: Task<Void, Never>?

    /// 마지막으로 시작한 더티 재집계. 테스트가 그 완료를 기다릴 수 있게 붙들어 둔다 —
    /// `Task.yield()` 로 기다리면 스케줄링에 따라 통과가 갈린다.
    private var dirtyRefreshTask: Task<Void, Never>?

    /// 진행 중인 더티 재집계를 기다린다 (테스트 전용 이음매).
    func awaitDirtyRefresh() async {
        await dirtyRefreshTask?.value
    }

    static let inputModeStorageKey = "inputMode"

    /// The grid size a project is opened with, before the editor view has been laid out and
    /// can report the real one. Neovim refuses a zero-sized UI, so it needs a number now;
    /// the first `resizeGrid` from the view corrects it.
    static let initialGridColumns = 80
    static let initialGridRows = 24

    /// 어떤 파일을 렌더할 수 있는가 — `.md`·`.html` 판정.
    ///
    /// 주입받는다. 이 모델은 확장자 정책의 주인이 아니고, 목록을 여기에 또 적으면 렌더
    /// 도메인의 목록과 갈라진다 — 한쪽만 늘어나는 날 링크는 열리는데 버튼은 비활성이 된다.
    private let isRenderableDocument: (String) -> Bool

    /// 렌더 문서를 준비하는 모델. 여기 사는 이유는 워크스페이스가 여기 있기 때문이고,
    /// 창의 생성자에 인자를 하나 더 다는 것보다 **아무도 잊을 수 없는 자리**라서다.
    public let render: RenderDocumentModel

    public init(
        editorSession: EditorSession,
        workspace: any ProjectWorkspace,
        storage: KeyValueStore,
        now: @escaping @Sendable () -> Date,
        // 기본값은 **진짜 동작**이다. 예전 기본값 `{ _ in false }` 는 중립처럼 보였지만
        // 중립이 아니라 하나의 행동이었고, 하필 **모든 렌더 검사를 무의미하게 만드는**
        // 행동이었다 — 주입을 잊은 채 쓴 모델은 렌더가 영원히 안 켜지고, 그 위에서 쓴
        // 렌더 테스트는 "렌더 꺼짐" 경로만 재면서 전부 초록이 된다.
        // 잊었을 때 조용히 꺼지는 대신 정상 동작하도록 뒤집었다. 다른 판정을 원하는
        // 테스트는 그대로 주입하면 된다.
        isRenderableDocument: @escaping (String) -> Bool = RenderableDocument.isRenderable(relativePath:)
    ) {
        self.editorSession = editorSession
        self.workspace = workspace
        self.storage = storage
        self.isRenderableDocument = isRenderableDocument
        self.render = RenderDocumentModel(workspace: workspace)
        self.emptyFileTree = FileTreeModel(
            projectSession: NoProjectSession(),
            editorSession: editorSession
        )
        self.recentProjects = RecentProjectStore(storage: storage, now: now)
        self.shell = ShellPreferences(storage: storage)
        // REQ-010 AC-6: the chosen mode comes back after a restart. Vim is the default,
        // and unreadable stored data falls back to it rather than refusing to launch.
        self.inputMode = Self.storedInputMode(in: storage) ?? .vim
    }

    // MARK: Stream wiring

    /// Subscribes to every engine stream. Each update lands on the main actor.
    public func start() {
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

    // MARK: 렌더 보기 (REQ-013 AC-3, 02b F-14)

    /// 지금 열린 파일의 렌더 상태 — **툴바·상태바·헤더가 전부 이것을 읽는다.**
    public var renderViewState: RenderViewState {
        guard let path = editorStatus?.filePath, let tab = tabs.activeTab else {
            return .noDocument
        }
        return tab.renderViewSelection.state(forPath: path, isRenderable: isRenderableDocument(path))
    }

    /// 화면에 있어야 할 문서를 모델에 알린다.
    ///
    /// 창 본문이 아니라 여기서 부른다 — `body` 는 SwiftUI 가 아무 때나 돌리고, 거기서
    /// 읽기를 시작하면 **스크롤 위치가 매번 처음으로 돌아간다**.
    public func syncRenderDocument() {
        guard renderViewState.isShowingRender,
              let absolutePath = editorStatus?.filePath,
              let root = projectRootPath,
              let tab = tabs.activeTabID
        else {
            render.clear()
            return
        }

        // **에디터는 절대 경로로 말하고, 엔진의 문은 상대 경로를 받는다**
        // (`EditorStatus.filePath` 는 절대, `renderSource(atRelativePath:)` 는 상대).
        // 변환 없이 넘기면 엔진이 거절하고, 그 거절이 **모든 파일에** 일어난다 — 그런데
        // 문구가 "잘못된 경로입니다"라서 화면은 *경로가 이상한 그 파일* 을 말하는 것처럼
        // 보인다. 상태바와 파일 트리가 이미 같은 변환을 거쳐 간다.
        guard let relativePath = PathDisplay.relativePath(
            ofAbsolutePath: absolutePath, projectRoot: root
        ) else {
            // 루트 밖이다. 여기서만 "밖이라서 못 그린다"가 참이 된다.
            render.showOutsideProjectRoot(absolutePath: absolutePath)
            return
        }

        render.showIfNeeded(path: relativePath, root: root, tab: tab)
    }

    /// 렌더 보기와 소스 보기를 오간다. 선택은 그 파일에 대해 세션 동안 남는다.
    public func toggleRenderView() {
        guard let path = editorStatus?.filePath, let tab = tabs.activeTab else {
            return
        }
        guard isRenderableDocument(path) else {
            // 02b F-14 4. 아무 일도 안 일어나면 사용자는 키가 안 먹은 줄 안다 — 왜 안
            // 되는지를 말해야 다시 누르지 않는다.
            show(StatusMessage(kind: .error, text: RenderableDocument.unsupportedMessage))
            return
        }
        tab.renderViewSelection.toggle(path: path, isRenderable: true)
        syncRenderDocument()
    }

    public func handle(editorStatus status: EditorStatus) {
        let wasDirty = editorStatus?.isDirty
        editorStatus = status
        // The tree marks the file being edited (REQ-003 AC-3); it learns which one only
        // from here, because the editor is the side that knows.
        fileTree.updateCurrentFile(absolutePath: status.filePath, isDirty: status.isDirty)

        // 탭 바의 ● 도 **여기서** 흐른다. 상태바·트리·탭 바가 같은 한 사건에서 갱신되므로
        // 세 표면이 서로 다른 답을 낼 수 없다 — QA 가 본 것이 정확히 그 어긋남이었다
        // (상태바는 ● 인데 탭 바는 아니었다).
        //
        // 더티 여부가 **바뀔 때만** 다시 센다. 이 핸들러는 커서가 움직일 때마다 불리고,
        // 매번 세면 편집기에 왕복이 그만큼 는다.
        if wasDirty != status.isDirty {
            dirtyRefreshTask = Task { await refreshActiveTabDirtyCount() }
        }
    }

    /// 활성 탭의 미저장 버퍼 수를 편집기에 다시 묻는다.
    ///
    /// 상태바는 *현재 파일*의 더티를 그리고 탭은 *그 프로젝트 전체*를 그린다 — 알갱이가
    /// 다르지만 출처는 하나(편집기의 더티 버퍼)다. 탭이 현재 파일만 보면 다른 파일을
    /// 고쳐 둔 채 깨끗한 파일로 옮긴 순간 점이 사라진다.
    private func refreshActiveTabDirtyCount() async {
        guard let tab = tabs.activeTab else { return }
        let files = await dirtyFiles(in: tab)
        tab.setDirtyBufferCount(files.count)
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
        // 저장은 더티를 지우는 사건이다. 상태 갱신만 기다리면 점이 남아 있는 창이 생기고,
        // 그 창에서 사용자는 저장이 안 된 줄 안다 — 반대 방향의 거짓말도 똑같이 나쁘다.
        dirtyRefreshTask = Task { await refreshActiveTabDirtyCount() }
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
        guard let session = tabs.activeTab?.projectSession else { return }
        indexStatistics = await session.indexStatistics()
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
        let session = tabs.activeTab?.projectSession
        let definitions = name.isEmpty ? [] : await (session?.definitions(named: name) ?? [])

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

    /// 렌더된 문서 안의 링크로 파일을 연다 (REQ-013).
    ///
    /// 연 뒤에 렌더 문서를 다시 맞춘다 — 새 파일이 `.md` 면 렌더로, 아니면 소스로 열린다.
    /// 그건 토글이 아니라 **그 파일의 성질**이다(02b D-C).
    public func openFile(atRelativePath path: String, line: Int?) async {
        await open(path: path, line: line)
        syncRenderDocument()
    }

    private func open(path: String, line: Int?) async {
        // The jump is recorded so ⌃O leads back to where it started (REQ-005 AC-4).
        try? await editorSession.openFile(atRelativePath: path, line: line, recordJump: true)
    }

    // MARK: 탭 복원 (REQ-012 AC-4·AC-6)

    /// Reopens the projects that were open, and lands on the one the user was looking at.
    ///
    /// The engine does the reopening: it owns the sessions and the normalisation that
    /// decides whether a stored path still names the same project. What this adds is the
    /// application's half — the stored list, and turning what came back into tabs.
    public func restoreTabs() async {
        let storedPaths = shell.openTabRootPaths
        // Nothing to restore is not the same as restoring nothing: calling the engine with
        // an empty list would start a session for a window that shows the welcome screen.
        guard !storedPaths.isEmpty else { return }

        let outcome = await workspace.restoreTabs(
            from: storedPaths.map { URL(fileURLWithPath: $0) },
            activeRootPath: shell.activeTabRootPath.map { URL(fileURLWithPath: $0) }
        )

        // 세션을 못 얻은 탭은 **조용히 빼지 않는다.**
        //
        // 엔진은 그 탭을 들고 있다 — 세션을 쥐고 배경에서 인덱싱한다. 앱 목록에서만 빠지면
        // 사용자는 그것을 **보지도 닫지도 못한 채** 자원을 쓴다. 그래서 엔진에서 닫고,
        // 못 열었다고 말한다(W-12). 두 목록이 갈라지는 자리를 하나 없앤다.
        var unopened: [MissingTab] = []
        for tab in outcome.restored {
            guard let session = await workspace.session(for: tab.id) else {
                try? await workspace.closeTab(tab.id)
                unopened.append(MissingTab(
                    displayName: tab.displayName,
                    rootPath: tab.rootPath,
                    reason: .noPermission
                ))
                continue
            }
            let state = ProjectTabState(
                id: tab.id,
                rootPath: tab.rootPath.path,
                name: tab.displayName,
                projectSession: session,
                editorSession: editorSession
            )
            tabs.open(state)
            watchIndexState(of: state)
            await state.fileTree.loadProject(name: tab.displayName, rootPath: tab.rootPath.path)
        }

        // Which tab is in front is the engine's answer, so the application follows it rather
        // than guessing from the order things came back in.
        if let active = await workspace.activeTab() {
            tabs.activate(id: active.id)
        }
        projectRootPath = tabs.activeTab?.rootPath
        missingTabs = outcome.missing + unopened
        rememberOpenTabs()
    }

    /// Clears the report after the user has seen it (W-12).
    public func dismissMissingTabs() {
        missingTabs = []
    }

    /// Records what is open, so the next launch can bring it back.
    ///
    /// Paths, not identifiers: the engine mints an identifier per run, so a stored one
    /// would name nothing tomorrow.
    private func rememberOpenTabs() {
        shell.setOpenTabs(
            rootPaths: tabs.tabs.map(\.rootPath),
            activeRootPath: tabs.activeTab?.rootPath
        )
    }

    // MARK: Saving before a tab closes (W-13)

    /// Which of this tab's buffers have unsaved changes.
    ///
    /// Empty when the editor cannot answer — a session that never started has nothing
    /// unsaved, and treating "cannot ask" as "there is something to lose" would put a sheet
    /// in front of a close that is safe.
    public func dirtyFiles(in tab: ProjectTabState) async -> [String] {
        let root = URL(fileURLWithPath: tab.rootPath)
        return (try? await editorSession.dirtyFiles(inProjectRoot: root)) ?? []
    }

    /// Writes every dirty buffer in this tab and reports what happened to each.
    ///
    /// A thrown error becomes a failure outcome rather than a silent success: the caller
    /// closes the tab only when the save completed, so "we could not tell" has to read as
    /// "not complete".
    public func saveAll(in tab: ProjectTabState) async -> SaveAllOutcome {
        let root = URL(fileURLWithPath: tab.rootPath)
        do {
            return try await editorSession.saveAll(inProjectRoot: root)
        } catch {
            return SaveAllOutcome(
                savedPaths: [],
                failures: [SaveFailure(path: tab.name, reason: "\(error)")]
            )
        }
    }

    // MARK: Opening a project (REQ-001)

    public func openProject(at projectRoot: URL) async {
        isOpeningProject = true
        projectOpenError = nil
        defer { isOpeningProject = false }

        let outcome: ProjectOpenOutcome
        do {
            outcome = try await workspace.openProject(at: projectRoot)
        } catch {
            // REQ-001 AC-3: nothing about the open project changes. The tree, the root and
            // the edit session are all left exactly as they were.
            projectOpenError = error
            forgetRecentProjectIfGone(error: error, path: projectRoot.path)
            return
        }

        // Whether this opened a tab or brought one forward is the engine's answer, not
        // ours. Deciding it here would mean normalising paths a second way, and two
        // normalisations disagreeing is how one project ends up open twice (AC-5).
        let tab = outcome.tab
        recentProjects.recordOpened(rootPath: tab.rootPath.path)

        // Correctness lives in `ProjectTabSet.open`, which refuses a tab it already holds.
        // This branch exists to avoid the work: without it, reopening an open project would
        // fetch a session and reload the whole tree before the set discarded the result.
        if let existing = tabs.tabs.first(where: { $0.id == tab.id }) {
            tabs.activate(id: existing.id)
        } else {
            guard let session = await workspace.session(for: tab.id) else {
                // 엔진은 이미 탭을 만들었다. 여기서 그냥 돌아가면 **화면에 없는 탭이
                // 세션을 쥔 채 남고, 사용자는 닫을 방법이 없다.** 만든 것을 되돌린다.
                try? await workspace.closeTab(tab.id)
                projectOpenError = NavigatorError.projectNotFound(path: tab.rootPath.path)
                return
            }
            let state = ProjectTabState(
                id: tab.id,
                rootPath: tab.rootPath.path,
                name: tab.displayName,
                projectSession: session,
                editorSession: editorSession
            )
            tabs.open(state)
            watchIndexState(of: state)
            await state.fileTree.loadProject(name: tab.displayName, rootPath: tab.rootPath.path)
        }

        projectRootPath = tabs.activeTab?.rootPath
        rememberOpenTabs()
    }

    /// Brings a tab forward (REQ-012 AC-2).
    ///
    /// The engine is told first: it owns which project is active, and the tab bar is a
    /// display of that rather than a second opinion. No index is rebuilt — every open
    /// project keeps its own, which is what makes switching immediate.
    public func activateTab(_ identifier: ProjectTabIdentifier) async {
        try? await workspace.activate(identifier)
        tabs.activate(id: identifier)
        projectRootPath = tabs.activeTab?.rootPath
        rememberOpenTabs()
    }

    /// Closes a tab, in the engine as well as on screen (REQ-012 AC-3).
    public func closeTab(_ identifier: ProjectTabIdentifier) async {
        try? await workspace.closeTab(identifier)
        indexWatchers[identifier]?.cancel()
        indexWatchers[identifier] = nil
        tabs.close(id: identifier)
        projectRootPath = tabs.activeTab?.rootPath
        rememberOpenTabs()
        if tabs.tabs.isEmpty {
            definitionCandidates = nil
            indexStatistics = nil
        }
    }

    /// Follows one tab's index, so a background project's progress is real.
    ///
    /// Every open tab is watched at once rather than only the active one: the tab bar draws
    /// a spinner per tab (W-11), and a tab that only reports while it is in front would
    /// finish indexing invisibly.
    private func watchIndexState(of tab: ProjectTabState) {
        indexWatchers[tab.id] = Task { [weak self, weak tab] in
            guard let session = tab?.projectSession else { return }
            for await state in await session.indexStateUpdates() {
                guard let self, let tab else { return }
                tab.setIndexState(state)
                if tab.id == self.tabs.activeTabID {
                    self.handle(indexState: state)
                }
            }
        }
    }

    /// Closes the open project, returning the window to the welcome screen (§3 W-2).
    ///
    /// The edit session is left alone. Whether an unsaved buffer should be discarded is
    /// Neovim's decision, not the application's (INV-3).
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
            layout: layout,
            renderView: renderViewState
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
