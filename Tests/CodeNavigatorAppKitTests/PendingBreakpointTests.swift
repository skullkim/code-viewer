import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 브레이크포인트는 **디버거가 붙기 전에도** 찍혀야 한다.
///
/// 사용자가 겪은 것: "디버깅할 break point 어떻게 찍나? intellj 처럼 빨간 원이 라인에 표시
/// 안되는데." `toggleBreakpoint` 가 `guard let session else { return }` 로 시작해서, 붙기
/// 전에는 눌러도 **아무 일도 안 일어났다** — 오류도, 표시도 없다.
///
/// IntelliJ 는 언제든 찍히고, 디버거가 붙을 때 심는다. 순서가 반대면 "시작 코드에
/// 브레이크포인트를 걸어 두고 디버그 실행" 이라는 가장 흔한 흐름이 아예 불가능하다.
@Suite("붙기 전 브레이크포인트")
@MainActor
struct PendingBreakpointTests {

    private func session() -> RecordingDebugSession { RecordingDebugSession() }

    @Test("붙지 않았어도 찍힌다")
    func canBeSetBeforeAttaching() async {
        let model = DebugModel()
        await model.toggleBreakpoint(path: "/p/A.java", line: 10, className: "A")

        #expect(model.breakpoints.map(\.line) == [10], "붙기 전에는 아무 일도 안 일어났다")
        #expect(model.breakpoints.first?.className == "A")
    }

    @Test("붙지 않았을 때 다시 누르면 지워진다")
    func togglesOffBeforeAttaching() async {
        let model = DebugModel()
        await model.toggleBreakpoint(path: "/p/A.java", line: 10, className: "A")
        await model.toggleBreakpoint(path: "/p/A.java", line: 10, className: "A")
        #expect(model.breakpoints.isEmpty)
    }

    /// 붙는 순간 JVM 에 심어야 한다. 안 심으면 목록에는 있는데 멈추지 않는다 — 사용자는
    /// "브레이크포인트가 안 먹는다" 를 겪는다.
    @Test("붙을 때 미리 찍어 둔 것을 JVM 에 심는다")
    func installsPendingBreakpointsOnAttach() async {
        let model = DebugModel()
        await model.toggleBreakpoint(path: "/p/A.java", line: 10, className: "A")
        await model.toggleBreakpoint(path: "/p/B.java", line: 20, className: "B")

        let session = session()
        await model.attach(session: session, host: "127.0.0.1", port: 5005)

        #expect(Set(session.installed) == ["A:10", "B:20"], "심은 것: \(session.installed)")
        // 심은 뒤에는 진짜 요청 id 를 들고 있어야 지울 수 있다.
        #expect(model.breakpoints.allSatisfy { $0.requestID != 0 })
    }

    /// 심다가 실패한 것을 목록에 남기지 않는다. 남기면 사용자는 걸린 줄 알고, 안 멈추는
    /// 것을 "아직 그 줄을 안 지났다" 로 읽는다.
    @Test("심지 못한 것은 목록에서 빠지고 이유를 남긴다")
    func dropsWhatCouldNotBeInstalled() async {
        let model = DebugModel()
        await model.toggleBreakpoint(path: "/p/A.java", line: 10, className: "Missing")

        let session = session()
        session.failingClassNames = ["Missing"]
        await model.attach(session: session, host: "127.0.0.1", port: 5005)

        #expect(model.breakpoints.isEmpty)
        #expect(model.lastError?.isEmpty == false, "왜 안 걸렸는지 말하지 않았다")
    }

    /// 화면이 표시를 그리려면 어느 파일의 몇 번째 줄인지 알아야 한다 — 붙기 전에도.
    @Test("붙기 전에도 화면이 그릴 줄 목록을 준다")
    func exposesLinesForTheGutterBeforeAttaching() async {
        let model = DebugModel()
        await model.toggleBreakpoint(path: "/p/A.java", line: 7, className: "A")
        #expect(model.breakpointLines(inFileAt: "/p/A.java") == [7])
        #expect(model.breakpointLines(inFileAt: "/p/Other.java").isEmpty)
    }
}

private final class RecordingDebugSession: DebugSession, @unchecked Sendable {
    private(set) var installed: [String] = []
    var failingClassNames: Set<String> = []
    private var nextID: Int32 = 0

    func setBreakpoint(className: String, line: Int) async throws -> Int32 {
        if failingClassNames.contains(className) {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "그런 클래스 없음"])
        }
        installed.append("\(className):\(line)")
        nextID += 1
        return nextID
    }
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
    func setExceptionBreakpoint(_ rule: ExceptionBreakpointRule) async throws {}
    func watchField(named name: String, inClass className: String) async throws -> Int32 { 1 }
    func clearWatchpoint(requestID: Int32) async throws {}
    func capabilities() async throws -> DebugCapabilities { .none }
    func redefineClass(named className: String, bytecode: [UInt8]) async throws {}
    func close() async {}
}
