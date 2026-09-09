import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 거터를 눌러 브레이크포인트를 건다 — IntelliJ 에서 눈과 손이 먼저 가는 자리다.
///
/// 조심할 것 둘. 거터 클릭은 **편집기로 넘기면 안 된다** — 넘기면 커서가 그 줄로 뛰고,
/// 사용자는 브레이크포인트를 걸었을 뿐인데 보던 자리를 잃는다. 그리고 디버거가 안 붙어
/// 있으면 거터 클릭은 그냥 평범한 클릭이어야 한다 — 안 그러면 디버깅을 안 하는 사람이
/// 줄 번호를 누를 때마다 아무 일도 안 일어나는 것을 겪는다.
@Suite("거터 클릭으로 브레이크포인트")
@MainActor
struct GutterClickTests {

    private func makeModel() -> (AppModel, FakeEditorSession) {
        let editor = FakeEditorSession()
        let model = AppModel(
            editorSession: editor,
            workspace: FakeWorkspace(sharedSession: FakeProjectSession()),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (model, editor)
    }

    /// 거터 클릭이 브레이크포인트가 되려면 열린 Java 파일이 있어야 한다. 그 상태를 놓는다.
    private func openJavaFile(_ model: AppModel, _ editor: FakeEditorSession) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gutter-\(UUID().uuidString)")
        let file = root.appendingPathComponent("src/Probe.java")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "package demo;\nclass Probe {}\n".write(to: file, atomically: true, encoding: .utf8)
        model.setProjectRootForTesting(root.path)
        model.handle(editorStatus: EditorStatus(
            filePath: file.path, isDirty: false, cursorLine: 1, cursorColumn: 1,
            mode: .normal, inputMode: .vim
        ))
    }

    /// 자바 파일이 아니면(여기서는 아무 파일도 안 열림) 걸 클래스가 없다. 그때는 조용히
    /// 편집기로 넘긴다 — 마크다운 거터를 누를 때마다 "Java 파일에서만" 을 띄우면 더 성가시다.
    @Test("자바 파일이 열려 있지 않으면 거터 클릭도 그냥 편집기로 간다")
    func passesTheClickThroughWithoutAJavaFile() async {
        let (model, editor) = makeModel()
        editor.gutterLineForClick = 12   // 편집기는 거터라고 답하지만

        await model.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 3, column: 1, modifiers: ""))

        #expect(editor.mouseEvents.count == 1, "클릭이 편집기로 안 갔다")
        #expect(model.debug.breakpoints.isEmpty)
    }

    /// 규칙이 뒤집혔다. 예전에는 **붙어 있을 때만** 거터를 가로챘다. 그러면 디버깅을
    /// *하려는* 사람이 브레이크포인트를 찍을 방법이 없다 — 먼저 붙어야 하고, 붙이려면
    /// 실행해야 하고, 실행하면 이미 지나간 뒤다. 사용자가 그대로 겪었다:
    /// "디버깅할 break point 어떻게 찍나? intellj 처럼 빨간 원이 라인에 표시 안되는데"
    @Test("붙어 있지 않아도 자바 파일의 거터 클릭은 브레이크포인트를 건다")
    func togglesBeforeAttaching() async throws {
        let (model, editor) = makeModel()
        try openJavaFile(model, editor)
        editor.gutterLineForClick = 12

        await model.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 3, column: 1, modifiers: ""))

        #expect(model.debug.breakpoints.map(\.line) == [12], "붙기 전에는 아무 일도 안 일어났다")
        #expect(editor.mouseEvents.isEmpty, "클릭을 삼켜야 커서가 안 뛴다")
        // 거터에 실제로 그려야 한다 — 목록에만 있고 화면에 없으면 사용자는 못 찍은 줄 안다.
        #expect(editor.debugMarkers.last?.breakpointLines == [12])
    }

    /// 붙어 있고 거터를 눌렀으면 브레이크포인트를 걸고 **클릭은 삼킨다.**
    @Test("붙어 있으면 거터 클릭이 브레이크포인트를 걸고 편집기로 안 넘어간다")
    func togglesTheBreakpointAndSwallowsTheClick() async throws {
        let (model, editor) = makeModel()
        editor.gutterLineForClick = 12
        await model.debug.attach(session: GutterFakeDebugSession(), host: "127.0.0.1", port: 5005)
        try openJavaFile(model, editor)

        await model.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 3, column: 1, modifiers: ""))

        #expect(editor.mouseEvents.isEmpty, "거터 클릭이 편집기로 새어 나갔다 — 커서가 뛴다")
        #expect(model.debug.breakpoints.map(\.line) == [12])
    }

    /// 본문을 누른 것은 거터가 아니다. 편집기가 nil 로 답하면 평소대로 넘긴다.
    @Test("본문 클릭은 그대로 편집기로 간다")
    func leavesTextClicksAlone() async {
        let (model, editor) = makeModel()
        editor.gutterLineForClick = nil
        await model.debug.attach(session: GutterFakeDebugSession(), host: "127.0.0.1", port: 5005)

        await model.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 3, column: 20, modifiers: ""))

        #expect(editor.mouseEvents.count == 1)
        #expect(model.debug.breakpoints.isEmpty)
    }

    /// 누르고 떼는 두 이벤트가 온다. 뗄 때도 걸면 한 번 눌러 두 번 토글돼 **아무 일도 안
    /// 일어난 것처럼** 보인다.
    @Test("떼는 이벤트로는 토글하지 않는다")
    func onlyTogglesOnPress() async throws {
        let (model, editor) = makeModel()
        editor.gutterLineForClick = 12
        await model.debug.attach(session: GutterFakeDebugSession(), host: "127.0.0.1", port: 5005)
        try openJavaFile(model, editor)

        await model.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 3, column: 1, modifiers: ""))
        await model.sendMouse(EditorMouseEvent(button: .left, action: .release, row: 3, column: 1, modifiers: ""))

        #expect(model.debug.breakpoints.map(\.line) == [12], "떼면서 다시 토글됐다")
    }
}

private final class GutterFakeDebugSession: DebugSession, @unchecked Sendable {
    private var next: Int32 = 0
    func setBreakpoint(className: String, line: Int) async throws -> Int32 { next += 1; return next }
    func clearBreakpoint(requestID: Int32) async throws {}
    func waitForBreakpoint() async throws -> JavaStopEvent {
        try await Task.sleep(nanoseconds: .max)
        throw CancellationError()
    }
    func stackFrames(threadID: UInt64) async throws -> [JavaStackFrame] { [] }
    func localVariables(frame: JavaStackFrame, threadID: UInt64, codeIndex: UInt64) async throws -> [JavaVariable] { [] }
    func resume() async throws {}
    func step(_ step: DebugStep, threadID: UInt64) async throws {}
    func fields(ofObject objectID: UInt64, typeSignature: String) async throws -> [JavaVariable] { [] }
    /// 규칙을 기록한다 — 껐는지 켰는지 테스트가 확인할 수 있게.
    private(set) var exceptionRule: ExceptionBreakpointRule = .off
    func setExceptionBreakpoint(_ rule: ExceptionBreakpointRule) async throws {
        exceptionRule = rule
    }
    /// 지켜보는 필드를 기록한다.
    private(set) var watchedFields: [String] = []
    func watchField(named name: String, inClass className: String) async throws -> Int32 {
        watchedFields.append("\(className).\(name)")
        return Int32(watchedFields.count)
    }
    func clearWatchpoint(requestID: Int32) async throws {}
    var capabilitiesForTests = DebugCapabilities(
        canRedefineClasses: true, canPopFrames: false, canGetInstanceInfo: true
    )
    private(set) var redefinedClasses: [String] = []
    func capabilities() async throws -> DebugCapabilities { capabilitiesForTests }
    func redefineClass(named className: String, bytecode: [UInt8]) async throws {
        redefinedClasses.append(className)
    }
    func close() async {}
}
