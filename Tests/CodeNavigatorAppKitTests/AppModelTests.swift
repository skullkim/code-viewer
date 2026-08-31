import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// The model is where engine streams become screen state. Stream consumption is split from
/// the handlers so the rules can be driven directly and deterministically — an async test
/// that waits on a stream tests the scheduler as much as the logic.
@MainActor
@Suite("AppModel — 엔진 스트림을 화면 상태로 (REQ-004·009·010)")
struct AppModelTests {

    private func makeModel() -> (AppModel, FakeProjectSession, FakeEditorSession) {
        let project = FakeProjectSession()
        let editor = FakeEditorSession()
        let model = AppModel(
            editorSession: editor,
            workspace: FakeWorkspace(sharedSession: project),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (model, project, editor)
    }

    private func snapshot(revision: UInt64, text: String = "a") -> EditorGridSnapshot {
        EditorGridSnapshot(
            columns: 40, rows: 1,
            lines: [EditorGridLine(runs: [EditorTextRun(text: text, style: .plain, startColumn: 0, cellWidth: text.count)])],
            cursor: EditorCursorPosition(row: 0, column: 0),
            mode: .normal,
            defaultForeground: EditorColor(packedRGB: 0xFFFFFF),
            defaultBackground: EditorColor(packedRGB: 0x000000),
            revision: revision
        )
    }

    // MARK: Streams into state

    @Test("인덱스 상태가 모델에 반영된다")
    func indexStateReachesTheModel() {
        let (model, _, _) = makeModel()
        model.handle(indexState: .indexing(IndexProgress(completed: 3, total: 9)))
        #expect(model.indexState == .indexing(IndexProgress(completed: 3, total: 9)))
    }

    @Test("편집 세션 상태가 모델에 반영된다")
    func sessionStateReachesTheModel() {
        let (model, _, _) = makeModel()
        model.handle(sessionState: .disconnected(reason: "종료"))
        #expect(model.sessionState == .disconnected(reason: "종료"))
    }

    @Test("에디터 상태가 모델에 반영된다")
    func editorStatusReachesTheModel() {
        let (model, _, _) = makeModel()
        let status = EditorStatus(filePath: "/repo/a.swift", isDirty: true, cursorLine: 4, cursorColumn: 2, mode: .insert, inputMode: .vim)
        model.handle(editorStatus: status)
        #expect(model.editorStatus?.isDirty == true)
        #expect(model.editorStatus?.cursorLine == 4)
    }

    // MARK: Frames

    @Test("그리드 스냅샷이 그릴 프레임으로 바뀐다")
    func snapshotsBecomeDrawableFrames() {
        let (model, _, _) = makeModel()
        model.handle(snapshot: snapshot(revision: 1, text: "let"))
        #expect(model.gridFrame?.cells.count == 3)
        #expect(model.gridFrame?.revision == 1)
    }

    @Test("늦게 도착한 프레임은 버린다")
    func staleFramesAreDropped() {
        // Snapshots arrive from a stream; one that overtakes a newer frame would make the
        // editor flicker backwards.
        let (model, _, _) = makeModel()
        model.handle(snapshot: snapshot(revision: 5, text: "new"))
        model.handle(snapshot: snapshot(revision: 2, text: "old"))
        #expect(model.gridFrame?.revision == 5)
    }

    @Test("같은 리비전도 버린다 — 다시 그릴 이유가 없다")
    func repeatedRevisionsAreIgnored() {
        let (model, _, _) = makeModel()
        model.handle(snapshot: snapshot(revision: 5, text: "abc"))
        model.handle(snapshot: snapshot(revision: 5, text: "xyz"))
        #expect(model.gridFrame?.cells.map(\.character) == ["a", "b", "c"])
    }

    // MARK: Saving (design §2 F-7)

    @Test("저장이 끝나면 상태바에 줄 수와 크기가 뜬다")
    func savingReportsWhatWasWritten() {
        let (model, _, _) = makeModel()
        model.handle(savedFile: SavedFile(path: "/repo/Sources/SymbolIndex.swift", lineCount: 234, byteSize: 8_294))
        #expect(model.statusMessage?.text == "✓ 저장됨 · SymbolIndex.swift (234줄, 8.1KB)")
        #expect(model.statusMessage?.kind == .success)
    }

    @Test("작은 파일은 바이트로 표시한다")
    func smallFilesAreReportedInBytes() {
        let (model, _, _) = makeModel()
        model.handle(savedFile: SavedFile(path: "/repo/a.swift", lineCount: 3, byteSize: 62))
        #expect(model.statusMessage?.text == "✓ 저장됨 · a.swift (3줄, 62B)")
    }

    // MARK: Input mode (REQ-010)

    @Test("입력 모드 기본값은 Vim이다")
    func vimIsTheDefaultInputMode() {
        let (model, _, _) = makeModel()
        #expect(model.inputMode == .vim)
    }

    @Test("모드를 바꾸면 세션에 전달된다")
    func togglingTheModeReachesTheSession() async {
        let (model, _, editor) = makeModel()
        await model.setInputMode(.standard)
        #expect(model.inputMode == .standard)
        #expect(await editor.inputMode() == .standard)
    }

    @Test("선택한 모드가 재시작 후 복원된다")
    func theChosenModeSurvivesARestart() async {
        // REQ-010 AC-6.
        let storage = InMemoryKeyValueStore()
        let first = AppModel(
            editorSession: FakeEditorSession(),
            workspace: FakeWorkspace(), storage: storage, now: { Date() }
        )
        await first.setInputMode(.standard)

        let second = AppModel(
            editorSession: FakeEditorSession(),
            workspace: FakeWorkspace(), storage: storage, now: { Date() }
        )
        #expect(second.inputMode == .standard)
    }

    @Test("모드 전환은 저장을 일으키지 않는다")
    func togglingTheModeSavesNothing() async {
        // REQ-010 AC-4: only the key-interpretation layer changes.
        let (model, _, editor) = makeModel()
        await model.setInputMode(.standard)
        #expect(editor.sentKeys.isEmpty, "전환이 :w 를 보내면 안 된다")
        #expect(model.statusMessage == nil, "저장 피드백이 뜨면 안 된다")
    }

    // MARK: Derived presentation

    @Test("상태바 구성이 현재 상태에서 파생된다")
    func theStatusBarFollowsTheModel() {
        let (model, _, _) = makeModel()
        model.handle(sessionState: .connected)
        model.handle(indexState: .ready)
        model.handle(editorStatus: EditorStatus(
            filePath: "/repo/Sources/A.swift", isDirty: true,
            cursorLine: 8, cursorColumn: 5, mode: .insert, inputMode: .vim
        ))
        model.projectRootPath = "/repo"

        let bar = model.statusBar(for: ShellLayout.resolve(windowSize: CGSize(width: 1600, height: 1000)))
        #expect(bar.modeSegment.primaryLabel == "INSERT")
        #expect(bar.path == "Sources/A.swift")
        #expect(bar.showsDirtyIndicator)
        #expect(bar.indexChip.label == "인덱스 최신")
    }

    @Test("메뉴 활성 규칙이 현재 상태를 따른다")
    func theMenuFollowsTheModel() {
        let (model, _, _) = makeModel()
        model.handle(sessionState: .connected)
        model.projectRootPath = "/repo"
        #expect(!model.menuAvailability.isEnabled(.undo), "Vim 모드에서는 비활성")

        model.handle(sessionState: .disconnected(reason: "종료"))
        #expect(model.menuAvailability.isEnabled(.symbolSearch), "세션이 끊겨도 검색은 살아 있다")
        #expect(model.menuAvailability.isEnabled(.restartEditSession))
    }

    @Test("편집 세션 오버레이가 상태에서 파생된다")
    func theOverlayFollowsTheSessionState() {
        let (model, _, _) = makeModel()
        model.handle(sessionState: .connected)
        #expect(model.editSessionOverlay == nil)

        model.handle(sessionState: .disconnected(reason: "종료"))
        #expect(model.editSessionOverlay?.primaryAction == .restart)
    }
}
