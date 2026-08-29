import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Records what the shell asked the engine to open, so opening a project can be checked
/// without an engine. The two contract protocols each own half of that operation and
/// neither expresses that the halves move together.
final class RecordingWorkspace: ProjectWorkspace, @unchecked Sendable {
    private let lock = NSLock()
    private var opened: [(root: URL, columns: Int, rows: Int)] = []
    var openError: (any Error)?

    /// A synchronous critical section. `NSLock.lock()` cannot be called from an async
    /// context, and `openWorkspace` is reached from one.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var openedRoots: [URL] {
        locked { opened.map(\.root) }
    }

    var lastGridSize: (columns: Int, rows: Int)? {
        locked { opened.last.map { ($0.columns, $0.rows) } }
    }

    func openWorkspace(at projectRoot: URL, columns: Int, rows: Int) async throws {
        if let openError {
            throw openError
        }
        locked { opened.append((projectRoot, columns, rows)) }
    }
}

@MainActor
@Suite("AppModel 명령 — 입력 배선·정의 이동·프로젝트 열기 (REQ-001·004·005·010)")
struct AppModelCommandTests {

    private func makeModel() -> (AppModel, FakeProjectSession, FakeEditorSession, RecordingWorkspace) {
        let project = FakeProjectSession()
        let editor = FakeEditorSession()
        let workspace = RecordingWorkspace()
        let model = AppModel(
            projectSession: project,
            editorSession: editor,
            workspace: workspace,
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (model, project, editor, workspace)
    }

    private func definition(_ name: String, path: String, line: Int) -> SymbolDefinition {
        SymbolDefinition(name: name, kind: .function, path: path, line: line, signature: "func \(name)()")
    }

    private let startupFailure = EditorStartupFailure(
        reason: "Neovim을 찾을 수 없습니다",
        searchedPaths: ["/usr/local/bin"],
        requiredVersion: "0.9.0",
        foundVersion: nil
    )

    // MARK: 키 입력 (REQ-004 AC-2, REQ-010 AC-1)

    @Test("연결된 세션에서는 키가 그대로 전달된다")
    func keysReachAConnectedSession() async {
        let (model, _, editor, _) = makeModel()
        model.handle(sessionState: .connected)

        await model.sendKeys("iabc<Esc>")

        #expect(editor.sentKeys == ["iabc<Esc>"])
    }

    @Test("오버레이가 떠 있으면 키를 버린다 — 큐잉하지 않는다")
    func keysAreDroppedWhileTheOverlayIsUp() async {
        let (model, _, editor, _) = makeModel()
        model.handle(sessionState: .disconnected(reason: "종료"))

        await model.sendKeys("iabc")

        #expect(model.isEditorInputBlocked)
        #expect(editor.sentKeys.isEmpty)
    }

    @Test("연결 중에도 키를 버린다 (입력 유실 방지 — 02 §3 W-8)")
    func keysAreDroppedWhileConnecting() async {
        let (model, _, editor, _) = makeModel()
        model.handle(sessionState: .connecting)

        await model.sendKeys("x")

        #expect(model.isEditorInputBlocked)
        #expect(editor.sentKeys.isEmpty)
    }

    @Test("기동 실패 상태에서도 키를 버린다")
    func keysAreDroppedAfterAStartupFailure() async {
        let (model, _, editor, _) = makeModel()
        model.handle(sessionState: .startupFailed(startupFailure))

        await model.sendKeys("x")

        #expect(editor.sentKeys.isEmpty)
    }

    @Test("마우스 입력도 같은 차단 규칙을 따른다")
    func mouseFollowsTheSameBlockingRule() async {
        let (model, _, editor, _) = makeModel()
        let event = EditorMouseEvent(button: .left, action: .press, row: 3, column: 7, modifiers: "")

        model.handle(sessionState: .disconnected(reason: "종료"))
        await model.sendMouse(event)
        #expect(editor.mouseEvents.isEmpty)

        model.handle(sessionState: .connected)
        await model.sendMouse(event)
        #expect(editor.mouseEvents.count == 1)
        #expect(editor.mouseEvents.first?.column == 7)
    }

    @Test("그리드 리사이즈는 세션이 끊겨도 전달된다 — 화면 크기는 입력이 아니다")
    func resizeIsNotInput() async {
        let (model, _, editor, _) = makeModel()
        model.handle(sessionState: .disconnected(reason: "종료"))

        await model.resizeGrid(columns: 120, rows: 40)

        #expect(editor.resizeRequests.count == 1)
        #expect(editor.resizeRequests.first?.columns == 120)
    }

    // MARK: 정의로 이동 (REQ-005)

    @Test("정의가 1건이면 팝오버 없이 바로 이동한다 (AC-1)")
    func oneDefinitionNavigatesDirectly() async {
        let (model, project, editor, _) = makeModel()
        editor.wordUnderCursorValue = "buildIndex"
        project.definitionsByName["buildIndex"] = [definition("buildIndex", path: "Sources/Index.swift", line: 8)]

        await model.goToDefinition()

        #expect(model.definitionCandidates == nil)
        #expect(editor.openedFiles.count == 1)
        #expect(editor.openedFiles.first?.path == "Sources/Index.swift")
        #expect(editor.openedFiles.first?.line == 8)
        // REQ-005 AC-4: ⌃O must lead back to where the jump started.
        #expect(editor.openedFiles.first?.recordJump == true)
    }

    @Test("동명 정의가 여러 건이면 후보 목록을 띄운다 (AC-2)")
    func severalDefinitionsPresentCandidates() async {
        let (model, project, editor, _) = makeModel()
        editor.wordUnderCursorValue = "parse"
        project.definitionsByName["parse"] = [
            definition("parse", path: "Index/Parser.swift", line: 41),
            definition("parse", path: "Util/ArgParse.swift", line: 12),
        ]

        await model.goToDefinition()

        #expect(model.definitionCandidates?.count == 2)
        // Nothing is opened until the user picks one.
        #expect(editor.openedFiles.isEmpty)
    }

    @Test("정의가 0건이면 상태바 에러 — 조용한 무동작 금지 (AC-3)")
    func noDefinitionReportsAnError() async {
        let (model, _, editor, _) = makeModel()
        editor.wordUnderCursorValue = "legacyScan"

        await model.goToDefinition()

        #expect(model.definitionCandidates == nil)
        #expect(editor.openedFiles.isEmpty)
        #expect(model.statusMessage?.kind == .error)
        #expect(model.statusMessage?.text.contains("legacyScan") == true)
    }

    @Test("커서에 심볼이 없으면 그 사실을 말한다")
    func noSymbolUnderCursorSaysSo() async {
        let (model, project, editor, _) = makeModel()
        editor.wordUnderCursorValue = "   "

        await model.goToDefinition()

        #expect(model.statusMessage?.kind == .error)
        #expect(model.statusMessage?.text.contains("심볼이 없습니다") == true)
        // A blank query is not a question worth asking the index.
        #expect(project.definitionsByName.isEmpty)
        #expect(editor.openedFiles.isEmpty)
    }

    @Test("후보를 고르면 이동하고 목록이 닫힌다")
    func choosingACandidateNavigatesAndCloses() async {
        let (model, project, editor, _) = makeModel()
        editor.wordUnderCursorValue = "parse"
        project.definitionsByName["parse"] = [
            definition("parse", path: "Index/Parser.swift", line: 41),
            definition("parse", path: "Util/ArgParse.swift", line: 12),
        ]
        await model.goToDefinition()

        await model.openDefinition(definition("parse", path: "Util/ArgParse.swift", line: 12))

        #expect(model.definitionCandidates == nil)
        #expect(editor.openedFiles.first?.path == "Util/ArgParse.swift")
        #expect(editor.openedFiles.first?.line == 12)
    }

    // MARK: 프로젝트 열기 (REQ-001)

    @Test("프로젝트를 열면 인덱스·편집기·트리·최근 목록이 함께 움직인다 (AC-2)")
    func openingAProjectMovesEverything() async {
        let (model, project, _, workspace) = makeModel()
        project.directoryEntries[""] = [
            DirectoryEntry(name: "Sources", path: "Sources", isDirectory: true)
        ]

        await model.openProject(at: URL(fileURLWithPath: "/repo/sample"))

        #expect(workspace.openedRoots.map(\.path) == ["/repo/sample"])
        #expect(model.projectRootPath == "/repo/sample")
        #expect(model.fileTree.projectRootPath == "/repo/sample")
        #expect(model.fileTree.presentation.rows.count == 1)
        #expect(model.recentProjects.projects().map(\.rootPath) == ["/repo/sample"])
        #expect(model.projectOpenError == nil)
        #expect(model.isOpeningProject == false)
    }

    @Test("열기에 실패하면 이전 상태를 유지한다 (AC-3)")
    func aFailedOpenKeepsThePreviousProject() async {
        let (model, _, _, workspace) = makeModel()
        await model.openProject(at: URL(fileURLWithPath: "/repo/first"))

        workspace.openError = NavigatorError.projectNotFound(path: "/repo/gone")
        await model.openProject(at: URL(fileURLWithPath: "/repo/gone"))

        #expect(model.projectRootPath == "/repo/first")
        #expect(model.fileTree.projectRootPath == "/repo/first")
        #expect(model.projectOpenError != nil)
        #expect(model.isOpeningProject == false)
    }

    @Test("사라진 경로는 최근 목록에서 빠진다 — 권한 실패는 남는다")
    func aMissingPathLeavesTheRecentList() async {
        let (model, _, _, workspace) = makeModel()
        await model.openProject(at: URL(fileURLWithPath: "/repo/gone"))
        #expect(model.recentProjects.projects().map(\.rootPath) == ["/repo/gone"])

        workspace.openError = NavigatorError.projectNotFound(path: "/repo/gone")
        await model.openProject(at: URL(fileURLWithPath: "/repo/gone"))
        #expect(model.recentProjects.projects().isEmpty)

        // A folder that exists but cannot be read is still the project the user meant.
        workspace.openError = nil
        await model.openProject(at: URL(fileURLWithPath: "/repo/locked"))
        workspace.openError = NavigatorError.projectNotReadable(path: "/repo/locked", reason: "권한 없음")
        await model.openProject(at: URL(fileURLWithPath: "/repo/locked"))
        #expect(model.recentProjects.projects().map(\.rootPath) == ["/repo/locked"])
    }

    @Test("프로젝트는 편집기가 거부하지 않을 그리드 크기로 열린다")
    func aProjectOpensWithANonZeroGrid() async {
        let (model, _, _, workspace) = makeModel()

        await model.openProject(at: URL(fileURLWithPath: "/repo/sample"))

        #expect(workspace.lastGridSize?.columns == AppModel.initialGridColumns)
        #expect(workspace.lastGridSize?.rows == AppModel.initialGridRows)
        #expect((workspace.lastGridSize?.columns ?? 0) > 0)
        #expect((workspace.lastGridSize?.rows ?? 0) > 0)
    }

    // MARK: 상태 메시지 만료 (02 §3 W-7)

    @Test("성공 2초·에러 3초")
    func messagesHaveTheirOwnLifetimes() {
        #expect(StatusMessageDuration.seconds(for: .success) == 2)
        #expect(StatusMessageDuration.seconds(for: .error) == 3)
    }

    @Test("먼저 뜬 메시지의 타이머가 나중 메시지를 지우지 않는다")
    func anOldTimerCannotClearANewMessage() {
        let (model, _, _, _) = makeModel()

        model.show(StatusMessage(kind: .success, text: "✓ 저장됨"))
        let firstToken = model.statusMessageToken
        model.show(StatusMessage(kind: .error, text: "✕ 정의를 찾을 수 없습니다"))

        model.clearStatusMessage(ifToken: firstToken)

        #expect(model.statusMessage?.text == "✕ 정의를 찾을 수 없습니다")

        model.clearStatusMessage(ifToken: model.statusMessageToken)
        #expect(model.statusMessage == nil)
    }

    @Test("에디터 상태가 트리의 현재 파일 표시로 이어진다 (REQ-003 AC-3)")
    func editorStatusReachesTheTree() {
        let (model, _, _, _) = makeModel()

        model.handle(editorStatus: EditorStatus(
            filePath: "/repo/sample/Sources/Index.swift",
            isDirty: true,
            cursorLine: 8,
            cursorColumn: 5,
            mode: .normal,
            inputMode: .vim
        ))

        #expect(model.fileTree.currentFileAbsolutePath == "/repo/sample/Sources/Index.swift")
        #expect(model.fileTree.isCurrentFileDirty)
    }
}
