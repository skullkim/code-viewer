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

    @Test("디버거가 안 붙어 있으면 거터 클릭도 그냥 편집기로 간다")
    func passesTheClickThroughWhenNotDebugging() async {
        let (model, editor) = makeModel()
        editor.gutterLineForClick = 12   // 편집기는 거터라고 답하지만

        await model.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 3, column: 1, modifiers: ""))

        #expect(editor.mouseEvents.count == 1, "클릭이 편집기로 안 갔다")
        #expect(model.debug.breakpoints.isEmpty)
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
    func close() async {}
}
