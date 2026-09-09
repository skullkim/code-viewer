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
    /// 실행 설정 감지도 같은 이유로 여기 붙는다 — 탭이 바뀌면 다른 프로젝트이고,
    /// 앞 탭의 실행 설정을 그대로 두면 사용자는 엉뚱한 폴더에서 명령을 돌린다.
    public var projectRootPath: String? {
        didSet {
            syncRenderDocument()
            guard projectRootPath != oldValue else { return }
            detectedRunConfigurations = []
            guard let root = projectRootPath else { return }
            Task { await detectRunConfigurations(projectRoot: root) }
        }
    }

    /// 지금 키보드를 들고 있는 표면.
    ///
    /// 뷰가 아니라 모델이 들고 있다. 메뉴가 켤지 말지와 라우터가 어디로 보낼지를 **같은
    /// 값**으로 정해야 하기 때문이다 — 둘이 갈라지면 메뉴는 켜져 있는데 명령은 엉뚱한 데로
    /// 간다. 그건 아무 일도 안 일어나는 것보다 나쁘다.
    public let focus = KeyboardFocusCoordinator()

    public let recentProjects: RecentProjectStore
    /// Window chrome the application restores on launch (REQ-011 AC-3).
    public let shell: ShellPreferences
    /// 디버거 화면의 상태. 세션은 붙을 때 주입된다 — 프로젝트를 열었다고 JVM 이 있는 것은 아니다.
    public let debug = DebugModel()
    /// 터미널 패널. 세션은 실행할 때 주입된다.
    public let terminal = TerminalModel()
    /// 실제 터미널 세션을 만드는 것. 조립 지점이 넣어 준다 — 이 모델은 Core 를 모른다.
    public var terminalSessionFactory: (@Sendable () -> any TerminalSession)?
    /// 명령을 찾는 데 쓰는 PATH. 화면이 보여 준다 — "command not found" 만으로는 무엇이
    /// 빠졌는지 알 수 없고, 그 답을 사용자에게 물어보게 된다.
    ///
    /// **저장된 값이다. 뷰가 물을 때 계산하지 않는다.** 계산하려면 로그인 셸을 띄워야
    /// 하는데, 뷰 본문은 메인 스레드라 창이 그대로 멈춘다 — E2E 가 앱이 안 뜨는 것으로
    /// 잡았다. FSEvents 때와 같은 실수를 한 번 더 했다.
    public private(set) var terminalSearchPath: String = ""

    /// 조립 지점이 배경에서 한 번 재어 넣는다.
    public func setTerminalSearchPath(_ path: String) {
        terminalSearchPath = path
    }
    /// 지금 고른 실행 설정.
    public private(set) var selectedRunConfigurationID: String?
    /// 실제 JDWP 세션은 조립 지점이 넣어 준다. 이 모델은 Core 를 모른다 — 알면 화면 상태를
    /// 재는 데 JVM 이 필요해지고, 그런 테스트는 아무도 안 돌린다.
    public var debugSessionFactory: DebugSessionFactory?

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
    private var treeRefreshTask: Task<Void, Never>?

    /// 진행 중인 더티 재집계를 기다린다 (테스트 전용 이음매).
    func awaitDirtyRefresh() async {
        await dirtyRefreshTask?.value
    }

    /// 진행 중인 트리 새로고침을 기다린다 (테스트 전용 이음매).
    func awaitTreeRefresh() async {
        await treeRefreshTask?.value
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
        streamTasks.append(Task { [weak self] in
            guard let self else { return }
            for await request in await editorSession.navigationRequests() {
                self.onNavigationRequest?(request)
            }
        })
    }

    /// What to do when the editor asks for `gd` / `gr` (REQ-015).
    ///
    /// A closure rather than a direct call because answering a navigation needs both this model
    /// and `SearchModel`, and only the composition root holds both. Routing it from here would
    /// mean giving the editor model a reference to search just to forward one enum, and the
    /// forwarding is the whole job (ADR-0113).
    public var onNavigationRequest: ((EditorNavigationRequest) -> Void)?

    public func stop() {
        streamTasks.forEach { $0.cancel() }
        streamTasks.removeAll()
    }

    // MARK: 구문 팔레트 (REQ-016 AC-3, AC-6)

    /// The appearance the palette is built for.
    ///
    /// The view tells the model rather than the model asking: an effective appearance belongs to
    /// a view hierarchy, and reading `NSApp` from here would answer for the application when the
    /// question is about the window the editor is actually in.
    public private(set) var appearanceScheme: AppearanceScheme = .light

    /// Hands the editor the application's colours.
    ///
    /// Failure is swallowed on purpose. Highlighting is derived (INV-8), so a palette that did
    /// not apply must leave the file open and editable — the cost of losing it is a duller
    /// screen, and the cost of propagating it would be a session that will not start.
    public func applySyntaxPalette() async {
        try? await editorSession.applySyntaxPalette(
            SyntaxPaletteBuilder.palette(for: appearanceScheme)
        )
    }

    /// Rebuilds and resends the palette when the system appearance changes (AC-6).
    public func appearanceChanged(to scheme: AppearanceScheme) async {
        guard scheme != appearanceScheme else { return }
        appearanceScheme = scheme
        await applySyntaxPalette()
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

        // 인덱싱이 끝나면 트리도 다시 읽는다. 감시자가 새 파일을 잡아 재인덱싱했다는
        // 뜻이고, 트리는 **열 때 한 번 읽은 캐시**를 들고 있어 그 파일을 모른다
        // (QA 실측: 검색은 6개, 트리는 5개).
        //
        // 끝났을 때만 한다 — 진행률은 큰 레포에서 초당 여러 번 바뀌고, 매번 다시 읽으면
        // 새로고침 자체가 부하가 된다. 더티 카운트를 "바뀔 때만" 센 것과 같은 이유다.
        if state == .ready, wasWorking {
            treeRefreshTask = Task { await fileTree.refreshVisibleDirectories() }
        }
        // The tab bar's spinner reads this. Kept in step here rather than derived in the
        // view, so the bar and the status chip cannot disagree about whether indexing runs.
        tabs.activeTab?.setIndexState(state)
    }

    public func handle(sessionState state: EditorSessionState) {
        let wasAlreadyConnected = sessionState == .connected
        sessionState = state
        // A session that just attached is painted with Neovim's own colours. Re-applying on every
        // fresh connection — not only the first — is what keeps a restart (REQ-004 AC-5) from
        // silently dropping the theme, which would look like the highlighting "stopped working".
        if state == .connected, !wasAlreadyConnected {
            Task { await applySyntaxPalette() }
        }
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
            dirtyRefreshTask = Task { await refreshDirtyCounts() }
        }

        // 변경 막대는 **파일이 바뀌거나 저장될 때** 다시 계산한다. 커서가 움직일 때마다
        // git 을 부르면 방향키 한 번에 프로세스가 하나씩 뜬다.
        //
        // 저장은 `isDirty` 가 참에서 거짓으로 가는 순간이다 — 그때 디스크가 바뀌었고,
        // 다시 묻지 않으면 방금 고친 줄에 막대가 없다.
        let didSave = wasDirty == true && !status.isDirty
        if lastGitMarkerPath != status.filePath || didSave {
            lastGitMarkerPath = status.filePath
            gitMarkerTask = Task { await refreshGitMarkers() }
        } else if status.isDirty {
            // 타이핑하는 동안에도 막대가 따라와야 한다. 이 핸들러는 커서가 움직일 때마다
            // 불리므로 **잠깐 뜸을 들인다** — 매 글자마다 git 을 부르면 프로세스가 그만큼 뜬다.
            gitMarkerTask?.cancel()
            gitMarkerTask = Task {
                try? await Task.sleep(for: .milliseconds(Self.gitMarkerDebounce))
                guard !Task.isCancelled else { return }
                await refreshGitMarkers()
            }
        }
    }

    /// 열린 파일이 저장소와 어떻게 다른지 묻는 함수. 조립 지점에서 꽂는다 — 모델이 git 을
    /// 직접 부르면 화면 상태를 재는 데 진짜 저장소가 필요해진다.
    public var gitLineChangeProvider: (@Sendable (_ relativePath: String, _ root: String) -> [GitLineChange])?
    /// 저장 전 버퍼 내용을 저장소와 견주는 함수. 사용자가 타이핑하는 동안에도 막대가 보여야
    /// 한다 — 저장하기 전 내용은 디스크에 없어서 `git diff` 가 못 본다.
    public var gitBufferChangeProvider: (
        @Sendable (_ relativePath: String, _ root: String, _ buffer: String) -> [GitLineChange]
    )?
    /// 편집기가 들고 있는 저장 전 내용을 읽는 함수.
    public var editorBufferReader: (@Sendable (String) async -> String?)?

    /// 타이핑이 멎기를 기다리는 시간(밀리초). 짧으면 프로세스가 자주 뜨고, 길면 막대가
    /// 굼떠 보인다.
    static let gitMarkerDebounce = 350

    /// 마지막으로 표시를 계산한 파일. 같은 파일이면 커서가 움직여도 다시 묻지 않는다.
    private var lastGitMarkerPath: String?
    private var gitMarkerTask: Task<Void, Never>?

    /// 열린 파일의 변경 막대를 다시 계산해 편집기에 놓는다.
    public func refreshGitMarkers() async {
        guard
            let gitLineChangeProvider,
            let root = projectRootPath,
            let absolutePath = editorStatus?.filePath,
            !absolutePath.isEmpty
        else {
            // 열린 파일이 없으면 물을 것이 없다. 빈 경로로 git 을 부르면 저장소 전체의
            // diff 가 와서, 아무 파일에나 남의 줄 번호가 붙는다.
            return
        }

        let relativePath = Self.relativePath(of: absolutePath, under: root)

        // 저장 전 편집이 있으면 **버퍼**를 저장소와 견준다. 디스크만 보면 저장하기 전까지
        // 아무 표시도 안 나오는데, IntelliJ 는 타이핑하는 즉시 그린다.
        var buffer: String?
        if editorStatus?.isDirty == true, let editorBufferReader {
            buffer = await editorBufferReader(absolutePath)
        }

        // git 은 프로세스를 띄운다. 창을 멈추게 두지 않는다.
        let bufferProvider = gitBufferChangeProvider
        let changes = await Task.detached(priority: .utility) {
            if let buffer, let bufferProvider {
                return bufferProvider(relativePath, root, buffer)
            }
            return gitLineChangeProvider(relativePath, root)
        }.value

        // **변경이 없어도 보낸다.** 빈 결과라고 안 보내면 앞서 놓인 막대가 남아서,
        // 되돌리기로 원래대로 만들었는데 막대가 그대로인 모양이 된다.
        try? await editorSession.showGitMarkers(
            EditorGitMarkers(absolutePath: absolutePath, changes: changes),
            palette: SyntaxPaletteBuilder.gitMarkerPalette(for: appearanceScheme)
        )
    }

    /// 테스트용 — 상태 변화가 걸어 둔 갱신이 끝나기를 기다린다.
    func settleGitMarkersForTesting() async {
        await gitMarkerTask?.value
    }

    private static func relativePath(of absolutePath: String, under root: String) -> String {
        guard absolutePath.hasPrefix(root) else { return absolutePath }
        return String(absolutePath.dropFirst(root.count).drop(while: { $0 == "/" }))
    }

    /// **모든 탭의** 미저장 버퍼 수를 편집기에 다시 묻는다.
    ///
    /// 활성 탭만 갱신하면 비활성 탭의 값은 그 탭이 마지막으로 활성이었을 때 그대로
    /// 얼어붙는다 — QA 가 본 것이 그것이다(저장했는데 ● 이 안 꺼진다).
    ///
    /// **그리고 그게 이 기능이 존재하는 이유를 정면으로 깬다.** 탭의 ● 은 *다른 탭에
    /// 있는 동안* 그 프로젝트에 저장 안 한 변경이 있는지 알려 주려고 있다. 활성 탭은
    /// 상태바가 이미 말해 준다 — 활성만 갱신하는 것은 아는 것만 다시 아는 것이다.
    ///
    /// 탭 수만큼 왕복이 늘지만 더티가 **바뀔 때와 저장할 때만** 돈다. 프로젝트를 수십 개
    /// 여는 도구가 아니다.
    ///
    /// 상태바는 *현재 파일*의 더티를 그리고 탭은 *그 프로젝트 전체*를 그린다 — 알갱이가
    /// 다르지만 출처는 하나(편집기의 더티 버퍼)다.
    private func refreshDirtyCounts() async {
        for tab in tabs.tabs {
            let files = await dirtyFiles(in: tab)
            tab.setDirtyBufferCount(files.count)
        }
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
        dirtyRefreshTask = Task { await refreshDirtyCounts() }
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

    /// 지금 열린 파일이 자바인지. 브레이크포인트를 걸 수 있는지가 이것으로 갈린다.
    var isJavaFileOpen: Bool {
        editorStatus?.filePath?.hasSuffix(".java") == true
    }

    public func sendMouse(_ event: EditorMouseEvent) async {
        guard !isEditorInputBlocked else {
            return
        }
        // **붙어 있지 않아도 거터를 가로챈다.**
        //
        // 예전에는 붙어 있을 때만 그랬다 — 디버깅 안 하는 사람이 줄 번호를 누를 때마다
        // 아무 일도 안 일어나는 것을 겪지 않게. 그런데 그 판단의 대가가 더 컸다: 디버깅을
        // **하려는** 사람이 브레이크포인트를 찍을 방법이 없어진다. 먼저 붙어야 하는데,
        // 붙이려면 실행해야 하고, 실행하면 이미 지나간 뒤다.
        //
        // 자바 파일이 아니면 클릭은 그대로 편집기로 간다.
        //
        // **누를 때만** 토글한다. 뗄 때도 하면 한 번 눌러 두 번 토글돼 아무 일도 안 일어난
        // 것처럼 보인다.
        if event.action == .press, event.button == .left,
           // `try?` 가 옵셔널을 두 겹으로 감싸므로 한 번에 푼다. 안 풀면 "거터가 아님"과
           // "물어보다 실패함"이 같은 값이 되고, 실패를 거터 클릭으로 읽는다.
           let line = (try? await editorSession.gutterLine(atRow: event.row, column: event.column)) ?? nil {
            // 자바가 아니면 브레이크포인트를 걸 수 없다. 그때는 조용히 편집기로 넘긴다 —
            // 마크다운 거터를 누를 때마다 "Java 파일에서만" 을 띄우면 그게 더 성가시다.
            guard isJavaFileOpen else {
                try? await editorSession.sendMouse(event)
                return
            }
            await toggleBreakpoint(atLine: line)
            // 편집기로 넘기지 않는다. 넘기면 커서가 그 줄로 뛰고, 사용자는 브레이크포인트를
            // 걸었을 뿐인데 보던 자리를 잃는다.
            return
        }
        try? await editorSession.sendMouse(event)
    }

    // MARK: 실행 (REQ-018)

    /// 소스를 훑어 실행 설정을 알아내는 함수. 조립 지점에서 꽂는다 — 모델이 디스크를 직접
    /// 알면 화면 상태를 재는 데 진짜 프로젝트가 필요해진다.
    public var runConfigurationDetector: (@Sendable (String) -> [RunConfiguration])?

    /// 소스에서 알아낸 것들. **저장하지 않는다** — 사용자가 고쳐 저장할 때 비로소 설정이
    /// 된다. 그래야 "사용자가 고친 것을 다음 스캔이 덮어썼다" 가 원천적으로 없다.
    public private(set) var detectedRunConfigurations: [RunConfiguration] = []

    /// 고르개에 보일 목록. 저장한 것이 앞에 오고, 이름이 같으면 저장한 것이 이긴다 —
    /// 둘 다 보이면 어느 것이 도는지 알 수 없다.
    public var availableRunConfigurations: [RunConfiguration] {
        let savedNames = Set(shell.runConfigurations.map(\.name))
        return shell.runConfigurations + detectedRunConfigurations.filter {
            !savedNames.contains($0.name)
        }
    }

    /// 이 설정이 감지된 것인지. 화면이 표시를 붙일 때 쓴다.
    public func isDetected(_ configuration: RunConfiguration) -> Bool {
        !shell.runConfigurations.contains { $0.name == configuration.name }
            && detectedRunConfigurations.contains { $0.name == configuration.name }
    }

    /// 프로젝트를 훑어 실행 설정을 알아낸다. 프로젝트를 열 때와 사용자가 새로 고칠 때 부른다.
    public func detectRunConfigurations(projectRoot: String) async {
        guard let runConfigurationDetector else { return }
        // 훑기는 디스크를 도는 일이라 창을 멈추게 하면 안 된다.
        let found = await Task.detached(priority: .utility) {
            runConfigurationDetector(projectRoot)
        }.value
        detectedRunConfigurations = found
    }

    /// 지금 고른 설정. 고른 적이 없으면 첫 번째다 — 설정이 하나뿐인 흔한 경우에 고르는
    /// 동작을 요구하지 않는다.
    public var selectedRunConfiguration: RunConfiguration? {
        availableRunConfigurations.first { $0.id == selectedRunConfigurationID }
            ?? availableRunConfigurations.first
    }

    public func selectRunConfiguration(_ configuration: RunConfiguration) {
        selectedRunConfigurationID = configuration.id
    }

    /// 고른 설정을 터미널에서 돌린다.
    ///
    /// - Parameter debugPort: 디버그로 띄우면 그 포트. 띄운 뒤 자동으로 붙는다.
    public func run(_ configuration: RunConfiguration, debugPort: UInt16? = nil) async {
        guard let root = projectRootPath else {
            show(StatusMessage(kind: .error, text: "✕ 프로젝트를 먼저 여세요"))
            return
        }
        guard let terminalSessionFactory else {
            show(StatusMessage(kind: .error, text: "✕ 터미널이 이 빌드에 연결되어 있지 않습니다"))
            return
        }
        shell.isDebugPanelVisible = true
        shell.bottomPanelTab = .terminal
        selectedRunConfigurationID = configuration.id

        await terminal.run(
            configuration, projectRoot: root,
            session: terminalSessionFactory(), debugPort: debugPort
        )
        if case .failed(let reason) = terminal.state {
            show(StatusMessage(kind: .error, text: "✕ \(reason)"))
            return
        }
        guard debugPort != nil else { return }
        // **터미널이 실제로 연 포트로 붙는다.** 요청한 값을 그대로 쓰면 Gradle 에서 어긋난다 —
        // Gradle 은 `--debug-jvm` 포트를 5005 로 고정하고 우리 요청을 무시한다(실측).
        guard let attachPort = terminal.lastDebugPort else { return }

        // 디버그 실행이면 붙는다. **JVM 이 포트를 열 때까지 기다린다** — 바로 붙으면
        // "연결 거부" 가 나고, 그건 우리가 너무 빨랐다는 뜻이지 설정이 틀렸다는 뜻이 아닌데
        // 화면에서는 구별되지 않는다.
        await attachAfterLaunch(port: attachPort)
    }

    /// 실행 직후 디버거를 붙인다. JVM 이 뜰 시간을 준다.
    private func attachAfterLaunch(port: UInt16) async {
        let deadline = Date().addingTimeInterval(Self.launchAttachTimeout)
        while Date() < deadline {
            await attachDebugger(host: "127.0.0.1", port: port)
            if debug.connection.isAttached {
                // `suspend=y` 로 띄웠으므로 JVM 은 **한 줄도 실행하지 않은 채** 우리를
                // 기다린다. 그렇게 띄우는 이유는 시작 코드에 건 브레이크포인트를 놓치지
                // 않기 위해서인데, 붙기만 하고 풀어 주지 않으면 서버가 영영 안 뜬다 —
                // 사용자는 "디버그 실행을 눌렀는데 서버가 안 뜬다" 만 겪는다.
                await debug.resume()
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        // **디버거를 탓하지 않는다.** 붙을 대상이 없는 흔한 이유는 실행이 실패한 것이다 —
        // 명령을 못 찾거나 빌드가 깨지면 JVM 은 뜨지도 않는다. "연결 실패" 만 말하면
        // 사용자는 디버거를 고치려 든다.
        show(StatusMessage(
            kind: .error,
            text: "✕ \(port) 에 붙을 대상이 없습니다 — 터미널 탭에서 실행이 실패하지 않았는지 보세요"
        ))
    }

    /// 디버그 실행이 쓰는 포트. `-agentlib:jdwp` 예제가 거의 다 5005 를 쓴다.
    public static let defaultDebugPort: UInt16 = 5005

    /// 실행 뒤 붙기를 포기하는 시간. gradle 은 JVM 이 뜨기까지 몇 초 걸린다.
    static let launchAttachTimeout: TimeInterval = 30

    public func stopRun() async {
        await terminal.stop()
        if debug.connection.isAttached {
            await debug.detach()
        }
    }

    /// 실행 설정을 통째로 갈아 끼운다. 편집 화면이 끝낼 때 부른다.
    public func replaceRunConfigurations(_ configurations: [RunConfiguration]) {
        shell.runConfigurations = configurations
        // 고른 것이 사라졌으면 선택을 놓는다 — 없는 설정을 고른 채로 두면 실행 버튼이
        // 아무 일도 안 한다.
        if let selected = selectedRunConfigurationID,
           !configurations.contains(where: { $0.id == selected }) {
            selectedRunConfigurationID = configurations.first?.id
        }
    }

    public func openShell() async {
        // 조용히 돌아가지 않는다. 셸 버튼을 눌렀는데 아무 일도 안 일어나면 사용자는 앱이
        // 고장난 것으로 읽는다 — 실제로는 프로젝트를 안 연 것뿐이다.
        guard let root = projectRootPath else {
            show(StatusMessage(kind: .error, text: "✕ 프로젝트를 먼저 여세요"))
            return
        }
        guard let terminalSessionFactory else {
            show(StatusMessage(kind: .error, text: "✕ 터미널이 이 빌드에 연결되어 있지 않습니다"))
            return
        }
        shell.isDebugPanelVisible = true
        shell.bottomPanelTab = .terminal
        await terminal.openShell(projectRoot: root, session: terminalSessionFactory())
    }

    /// 지금 열린 파일의 컴파일된 클래스를 JVM 에 다시 넣는다.
    ///
    /// `.class` 파일을 **찾아서** 넣는다 — 우리는 컴파일하지 않는다. 컴파일까지 하려면
    /// 빌드 도구(gradle·maven)를 알아야 하고, 그건 이 앱이 하려는 일이 아니다. 사용자가
    /// 자기 빌드로 만든 `.class` 를 그대로 쓴다.
    public func hotSwapCurrentFile() async {
        guard let status = editorStatus,
              let absolutePath = status.filePath,
              let root = projectRootPath,
              let relativePath = PathDisplay.relativePath(ofAbsolutePath: absolutePath, projectRoot: root),
              let source = try? String(contentsOfFile: absolutePath, encoding: .utf8),
              let className = JavaTypeName.forFile(atPath: relativePath, source: source)
        else {
            show(StatusMessage(kind: .error, text: "✕ Java 파일에서만 핫스왑할 수 있습니다"))
            return
        }
        guard let classFile = ClassFileLocator.find(forClassNamed: className, projectRoot: root) else {
            show(StatusMessage(
                kind: .error,
                text: "✕ \(className) 의 .class 파일을 못 찾았습니다 — 먼저 빌드하세요"
            ))
            return
        }
        guard let bytecode = try? [UInt8](Data(contentsOf: classFile)) else {
            show(StatusMessage(kind: .error, text: "✕ .class 파일을 읽지 못했습니다"))
            return
        }
        await debug.hotSwap(className: className, bytecode: bytecode)
        if let error = debug.lastError {
            show(StatusMessage(kind: .error, text: "✕ \(error)"))
        } else {
            show(StatusMessage(kind: .success, text: "핫스왑 완료 — \(className)"))
        }
    }

    /// 커서 아래 낱말을 필드로 보고 지켜보기를 토글한다.
    ///
    /// 클래스는 열린 파일에서 만든다 — 다른 클래스의 필드를 지켜보려면 그 파일을 열어야 한다.
    /// 커서 아래 낱말이 필드가 아니면 세션이 "그런 필드 없다" 로 답하고, 그 말을 그대로 보인다.
    public func toggleFieldWatchAtCursor() async {
        guard let name = await wordUnderCursor(), !name.isEmpty else {
            show(StatusMessage(kind: .error, text: "✕ 커서 위치에 이름이 없습니다"))
            return
        }
        guard let status = editorStatus,
              let absolutePath = status.filePath,
              let root = projectRootPath,
              let relativePath = PathDisplay.relativePath(ofAbsolutePath: absolutePath, projectRoot: root),
              let source = try? String(contentsOfFile: absolutePath, encoding: .utf8),
              let className = JavaTypeName.forFile(atPath: relativePath, source: source)
        else {
            show(StatusMessage(kind: .error, text: "✕ Java 파일에서만 필드를 지켜볼 수 있습니다"))
            return
        }
        await debug.toggleFieldWatch(named: name, inClass: className)
        if let error = debug.lastError {
            show(StatusMessage(kind: .error, text: "✕ \(error)"))
        }
    }

    /// 커서가 선 줄의 브레이크포인트. 없으면 nil.
    public func breakpointAtCursor() -> DebugBreakpoint? {
        guard let status = editorStatus,
              let absolutePath = status.filePath,
              let root = projectRootPath,
              let relativePath = PathDisplay.relativePath(ofAbsolutePath: absolutePath, projectRoot: root)
        else {
            return nil
        }
        return debug.breakpoints.first { $0.path == relativePath && $0.line == status.cursorLine }
    }

    /// 줄 번호를 받아 그 줄의 브레이크포인트를 토글한다. 커서 위치와 무관하다.
    public func toggleBreakpoint(atLine line: Int) async {
        guard let status = editorStatus,
              let absolutePath = status.filePath,
              let root = projectRootPath,
              let relativePath = PathDisplay.relativePath(ofAbsolutePath: absolutePath, projectRoot: root)
        else {
            return
        }
        guard let source = try? String(contentsOfFile: absolutePath, encoding: .utf8),
              let className = JavaTypeName.forFile(atPath: relativePath, source: source)
        else {
            show(StatusMessage(kind: .error, text: "✕ Java 파일에서만 브레이크포인트를 걸 수 있습니다"))
            return
        }
        await debug.toggleBreakpoint(path: relativePath, line: line, className: className)
        if let error = debug.lastError {
            show(StatusMessage(kind: .error, text: "✕ \(error)"))
        }
        await refreshDebugMarkers()
    }

    /// 테스트가 프로젝트 루트를 놓기 위한 것.
    func setProjectRootForTesting(_ path: String) {
        projectRootPath = path
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

    // MARK: 디버거 (REQ-016)

    /// Attaches to a JVM already running with `-agentlib:jdwp`.
    ///
    /// 세션 만들기를 모델 밖에 두지 않는다 — 대신 실패를 그대로 화면 상태로 옮긴다. 붙지
    /// 못한 것을 조용히 넘기면 사용자는 브레이크포인트를 걸어 놓고 왜 안 멈추는지 묻는다.
    public func attachDebugger(host: String, port: UInt16) async {
        guard let debugSessionFactory else {
            debug.reportAttachFailure("디버거가 이 빌드에 연결되어 있지 않습니다")
            return
        }
        do {
            let session = try await debugSessionFactory(host, port)
            // 멈추면 그 자리를 화면에 띄운다. 모델이 편집기를 직접 알면 화면 상태를 재는
            // 데 편집기가 필요해지므로, 콜백으로 받는다.
            debug.onStopped = { [weak self] in await self?.revealStoppedLine() }
            await debug.attach(session: session, host: host, port: port)
            show(StatusMessage(kind: .success, text: "디버거 연결됨 — \(host):\(port)"))
        } catch {
            debug.reportAttachFailure("\(host):\(port) 에 붙지 못했습니다: \(error)")
            show(StatusMessage(kind: .error, text: "✕ 디버거 연결 실패"))
        }
    }

    public func detachDebugger() async {
        await debug.detach()
        show(StatusMessage(kind: .success, text: "디버거 연결 해제"))
    }

    /// Toggles a breakpoint on the line the cursor is on.
    ///
    /// 클래스 이름은 파일에서 만든다 — JDWP 는 파일을 모르고 클래스만 안다. Java 가 아니거나
    /// 이름을 못 만들면 **거기서 멈춘다**. 억지로 만든 이름으로 JVM 에 물으면 "그런 클래스
    /// 없음" 이 돌아오고, 그 실패는 화면에서 "아직 그 줄을 안 지났다" 와 같아 보인다.
    /// 디버거 표시를 편집기에 다시 그린다.
    ///
    /// 지금 열려 있는 파일 것만 그린다. 다른 파일의 브레이크포인트를 이 파일 줄 번호에
    /// 찍으면 없는 표시를 만드는 것이고, 사용자는 걸지 않은 자리에 점이 있는 것을 본다.
    public func refreshDebugMarkers() async {
        guard let status = editorStatus,
              let absolutePath = status.filePath,
              let root = projectRootPath,
              let relativePath = PathDisplay.relativePath(ofAbsolutePath: absolutePath, projectRoot: root)
        else {
            return
        }

        let breakpointLines = debug.breakpoints
            .filter { $0.path == relativePath }
            .map(\.line)
        // 멈춘 줄은 그 파일에서 멈췄을 때만 그린다.
        let stoppedLine = debug.stoppedBreakpointPath == relativePath ? debug.stoppedLine : nil

        try? await editorSession.showDebugMarkers(
            EditorDebugMarkers(
                path: relativePath, breakpointLines: breakpointLines, stoppedLine: stoppedLine
            ),
            palette: SyntaxPaletteBuilder.debugPalette(for: appearanceScheme)
        )
    }

    /// 멈춘 자리를 화면에 띄운다 — 파일을 열고 그 줄로 간다.
    ///
    /// **아는 파일일 때만** 연다. 프레임의 클래스 이름만으로 파일을 되짚으면 틀릴 수 있고,
    /// 엉뚱한 파일이 열리는 것은 아무것도 안 여는 것보다 나쁘다. 우리가 건 브레이크포인트면
    /// 경로를 이미 알고 있다.
    public func revealStoppedLine() async {
        guard let path = debug.stoppedBreakpointPath, let line = debug.stoppedLine else { return }
        await openFile(atRelativePath: path, line: line)
        await refreshDebugMarkers()
    }

    public func toggleBreakpointAtCursor() async {
        guard let status = editorStatus,
              let absolutePath = status.filePath,
              let root = projectRootPath,
              let relativePath = PathDisplay.relativePath(ofAbsolutePath: absolutePath, projectRoot: root)
        else {
            show(StatusMessage(kind: .error, text: "✕ 브레이크포인트를 걸 파일이 없습니다"))
            return
        }
        _ = relativePath
        await toggleBreakpoint(atLine: status.cursorLine)
    }

    /// 참조 검색이 "무엇에 대한 참조인가"를 풀 수 있게 커서 자리를 알려 준다.
    ///
    /// 이름만으로는 답이 없다 — 실측으로 463파일 레포에서 `getId` 는 서로 무관한 15개
    /// 타입에 걸쳐 670줄에 나온다. 어느 것을 물은 것인지는 커서가 선 자리에만 적혀 있다.
    ///
    /// 에디터는 절대 경로로 말하고 엔진은 상대 경로를 받으므로 여기서 변환한다. 변환이
    /// 안 되면(프로젝트 밖 파일) 원점 없이 검색한다 — 좁히지 못할 뿐 결과는 나온다.
    public var referenceQueryOrigin: ReferenceQueryOrigin? {
        guard let status = editorStatus,
              let absolutePath = status.filePath,
              let root = projectRootPath,
              let relativePath = PathDisplay.relativePath(ofAbsolutePath: absolutePath, projectRoot: root)
        else {
            return nil
        }
        return ReferenceQueryOrigin(path: relativePath, line: status.cursorLine)
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
    /// 닫은 탭의 검색 상태를 버리라고 알려 줄 곳. 조립 지점에서 꽂는다 — 모델이 검색
    /// 모델을 직접 알면 둘이 서로를 붙들게 된다.
    public var onTabClosed: (@MainActor (ProjectTabIdentifier) -> Void)?

    public func closeTab(_ identifier: ProjectTabIdentifier) async {
        try? await workspace.closeTab(identifier)
        // 그 탭의 검색·참조 결과도 버린다. 안 버리면 오래 쓸수록 쌓이기만 한다.
        onTabClosed?(identifier)
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
            hasOpenProject: projectRootPath != nil,
            appearance: shell.appearance,
            debugConnection: debug.connection,
            exceptionRule: debug.exceptionRule,
            capabilities: debug.capabilities,
            isRunning: terminal.isRunning,
            canDebugSelected: selectedRunConfiguration?.canDebug ?? true,
            keyboardOwner: focus.owner,
            usesUserVimConfiguration: shell.usesUserVimConfiguration
        )
    }

    /// Records the choice. Putting it into effect is `AppearanceApplier`'s job — the model does
    /// not reach for `NSApp`, so it stays buildable twice in one test process.
    ///
    /// The editor's own colours are not repainted here. Changing the application appearance makes
    /// AppKit tell the editor view its effective appearance changed, and that path already rebuilds
    /// the palette and resends it (AC-6). Repainting here as well would send it twice, and the
    /// second send would be the one that had to be kept correct.
    public func setAppearancePreference(_ preference: AppearancePreference) {
        shell.appearance = preference
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

