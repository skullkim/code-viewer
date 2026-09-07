import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 터미널 패널의 상태 기계. 진짜 셸 없이 잰다 — 셸이 필요한 테스트는 느리거나 흔들리고,
/// 여기서 물으려는 것은 셸이 아니라 화면이 무엇을 말하는가다.
@Suite("터미널 모델")
@MainActor
struct TerminalModelTests {

    @Test("돌리기 전에는 아무 상태도 주장하지 않는다")
    func startsIdle() {
        let model = TerminalModel()
        #expect(model.state == .idle)
        #expect(model.gridFrame == nil)
        #expect(!model.isRunning)
    }

    @Test("돌리면 무엇을 돌리는지 말한다")
    func namesWhatItIsRunning() async {
        let model = TerminalModel()
        await model.run(configuration("서버", "./gradlew bootRun"), projectRoot: "/p", session: FakeTerminal())
        #expect(model.state == .running(name: "서버"))
    }

    /// 못 띄운 것을 조용히 넘기지 않는다. 빈 터미널은 "명령이 아무것도 출력하지 않았다" 로 읽힌다.
    @Test("못 띄우면 그렇다고 말한다")
    func reportsAFailedStart() async {
        let terminal = FakeTerminal()
        terminal.startError = TerminalTestError.cannotStart
        let model = TerminalModel()

        await model.run(configuration("서버", "x"), projectRoot: "/p", session: terminal)
        guard case .failed = model.state else {
            Issue.record("실패를 말하지 않았다: \(model.state)")
            return
        }
    }

    /// **앞의 것을 먼저 끝낸다.** 안 끝내면 서버가 포트를 잡은 채 남고, 다음 실행이
    /// "포트 사용 중" 으로 실패한다 — 사용자는 원인을 못 찾는다.
    @Test("다시 돌리면 앞의 것을 먼저 끝낸다")
    func stopsThePreviousRunFirst() async {
        let first = FakeTerminal()
        let model = TerminalModel()
        await model.run(configuration("서버", "a"), projectRoot: "/p", session: first)
        await model.run(configuration("서버", "b"), projectRoot: "/p", session: FakeTerminal())
        #expect(first.stopCount == 1, "앞의 프로세스를 안 끝냈다")
    }

    @Test("환경변수와 작업 디렉터리가 세션에 그대로 간다")
    func handsTheEnvironmentToTheSession() async {
        let terminal = FakeTerminal()
        let model = TerminalModel()
        var configuration = self.configuration("서버", "./gradlew bootRun")
        configuration.workingDirectory = "backend"
        configuration.environment = ["SPRING_PROFILES_ACTIVE": "local"]

        await model.run(configuration, projectRoot: "/p", session: terminal)

        #expect(terminal.startedWorkingDirectory == "/p/backend")
        #expect(terminal.startedEnvironment?["SPRING_PROFILES_ACTIVE"] == "local")
        // 물려받은 것이 살아 있어야 한다 — PATH 가 사라지면 `./gradlew` 를 못 찾는다.
        #expect(terminal.startedEnvironment?["PATH"] != nil, "PATH 를 잃었다")
    }

    @Test("디버그로 돌리면 에이전트가 환경변수로 간다")
    func passesTheDebugAgent() async {
        let terminal = FakeTerminal()
        let model = TerminalModel()
        await model.run(
            configuration("서버", "./gradlew bootRun"),
            projectRoot: "/p", session: terminal, debugPort: 5005
        )
        #expect(terminal.startedEnvironment?["JAVA_TOOL_OPTIONS"]?.contains("5005") == true)
        #expect(model.lastDebugPort == 5005)
    }

    /// 끝난 프로세스의 마지막 출력이 남아 있으면 사용자는 아직 도는 줄 안다.
    @Test("끝내면 화면도 비운다")
    func clearsTheScreenOnStop() async {
        let terminal = FakeTerminal()
        let model = TerminalModel()
        await model.run(configuration("서버", "x"), projectRoot: "/p", session: terminal)
        await model.stop()
        #expect(model.gridFrame == nil)
        #expect(model.state == .idle)
        #expect(!model.isRunning)
    }

    private func configuration(_ name: String, _ command: String) -> RunConfiguration {
        RunConfiguration(name: name, command: command, workingDirectory: "", environment: [:])
    }
}

private enum TerminalTestError: Error { case cannotStart }

private final class FakeTerminal: TerminalSession, @unchecked Sendable {
    var startError: (any Error)?
    private(set) var startedWorkingDirectory: String?
    private(set) var startedEnvironment: [String: String]?
    private(set) var stopCount = 0
    private(set) var startedColumns: Int?
    private(set) var startedRows: Int?
    /// pty 에 실제로 나간 크기. 걸러 냈어야 할 값이 여기 있으면 화면이 지워진다.
    private(set) var resizes: [TerminalSize] = []

    func start(
        command: String, workingDirectory: String, environment: [String: String],
        columns: Int, rows: Int
    ) async throws {
        if let startError { throw startError }
        startedWorkingDirectory = workingDirectory
        startedEnvironment = environment
        startedColumns = columns
        startedRows = rows
    }
    func send(keys: String) async {}
    func resize(columns: Int, rows: Int) async {
        resizes.append(TerminalSize(columns: columns, rows: rows))
    }
    func stop() async { stopCount += 1 }
    func gridUpdates() async -> AsyncStream<EditorGridSnapshot> {
        AsyncStream { $0.finish() }
    }
}

/// 레이아웃이 끝나기 전의 크기 보고가 터미널 내용을 지운다.
///
/// 실제로 겪은 것: 창을 열면 그리드 뷰가 첫 레이아웃 패스에서 **1×1** 을 보고한다. 그 값이
/// 그대로 pty 에 가면 libvterm 이 화면을 1칸으로 줄이고, 그 순간 이미 찍힌 줄이 잘려 나간다.
/// 곧이어 159×9 가 와도 잘린 글자는 돌아오지 않는다 — 서버 기동 로그가 12글자만 남았다.
@Suite("터미널 크기 보고 걸러내기")
@MainActor
struct TerminalResizeGuardTests {

    private func startedModel() async -> (TerminalModel, FakeTerminal) {
        let model = TerminalModel()
        let session = FakeTerminal()
        await model.run(
            RunConfiguration(name: "서버", command: "run", workingDirectory: "", environment: [:]),
            projectRoot: "/tmp", session: session
        )
        return (model, session)
    }

    @Test("1×1 보고는 pty 에 전달하지 않는다 — 화면을 지우는 값이다")
    func ignoresTheDegenerateFirstLayout() async {
        let (model, session) = await startedModel()
        await model.resize(columns: 1, rows: 1)
        #expect(session.resizes.isEmpty, "레이아웃 전 크기가 pty 로 나갔다 — 출력이 잘린다")
    }

    @Test("쓸 만한 크기는 그대로 넘긴다")
    func forwardsUsableSizes() async {
        let (model, session) = await startedModel()
        await model.resize(columns: 159, rows: 9)
        #expect(session.resizes == [TerminalSize(columns: 159, rows: 9)])
    }

    /// 걸러 낸 값이 다음 실행의 시작 크기가 되면, 새 세션이 1칸으로 뜬다.
    @Test("걸러 낸 크기는 다음 실행의 시작 크기도 되지 않는다")
    func doesNotPoisonTheNextRun() async {
        let (model, _) = await startedModel()
        await model.resize(columns: 159, rows: 9)
        await model.resize(columns: 1, rows: 1)

        let next = FakeTerminal()
        await model.run(
            RunConfiguration(name: "서버", command: "run", workingDirectory: "", environment: [:]),
            projectRoot: "/tmp", session: next
        )
        #expect(next.startedColumns == 159, "다음 세션이 1칸으로 떴다")
        #expect(next.startedRows == 9)
    }
}

struct TerminalSize: Hashable {
    let columns: Int
    let rows: Int
}

/// `suspend=y` 로 띄운 JVM 은 **누가 풀어 줄 때까지 한 줄도 실행하지 않는다.**
///
/// 그렇게 띄우는 이유는 시작 코드에 건 브레이크포인트를 놓치지 않기 위해서다. 그런데 붙기만
/// 하고 풀어 주지 않으면 서버가 영영 안 뜬다 — 사용자는 "디버그 실행을 눌렀는데 서버가 안
/// 뜬다" 를 겪고, 화면 어디에도 그 이유가 없다.
@Suite("디버그 실행 뒤 재개")
@MainActor
struct DebugRunResumeTests {

    private func makeModel() -> AppModel {
        let model = AppModel(
            editorSession: FakeEditorSession(),
            workspace: FakeWorkspace(sharedSession: FakeProjectSession()),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        model.setProjectRootForTesting(NSTemporaryDirectory())
        return model
    }

    @Test("디버그 실행으로 붙으면 멈춰 있던 JVM 을 풀어 준다")
    func resumesTheSuspendedProcess() async {
        let model = makeModel()
        let debugSession = ResumeCountingSession()
        model.debugSessionFactory = { _, _ in debugSession }
        model.terminalSessionFactory = { FakeTerminal() }

        await model.run(
            RunConfiguration(name: "서버", command: "run", workingDirectory: "", environment: [:]),
            debugPort: 5005
        )
        #expect(debugSession.resumeCount == 1, "붙기만 하고 풀어 주지 않아 서버가 안 뜬다")
    }

    /// 그냥 실행은 디버거를 안 쓴다 — 풀어 줄 것도 없다.
    @Test("보통 실행은 디버거를 건드리지 않는다")
    func plainRunDoesNotTouchTheDebugger() async {
        let model = makeModel()
        let debugSession = ResumeCountingSession()
        model.debugSessionFactory = { _, _ in debugSession }
        model.terminalSessionFactory = { FakeTerminal() }

        await model.run(
            RunConfiguration(name: "서버", command: "run", workingDirectory: "", environment: [:])
        )
        #expect(debugSession.resumeCount == 0)
    }
}

private final class ResumeCountingSession: DebugSession, @unchecked Sendable {
    private(set) var resumeCount = 0

    func setBreakpoint(className: String, line: Int) async throws -> Int32 { 1 }
    func clearBreakpoint(requestID: Int32) async throws {}
    func waitForBreakpoint() async throws -> JavaStopEvent {
        try await Task.sleep(nanoseconds: .max)
        throw CancellationError()
    }
    func stackFrames(threadID: UInt64) async throws -> [JavaStackFrame] { [] }
    func localVariables(frame: JavaStackFrame, threadID: UInt64, codeIndex: UInt64) async throws -> [JavaVariable] { [] }
    func resume() async throws { resumeCount += 1 }
    func step(_ step: DebugStep, threadID: UInt64) async throws {}
    func fields(ofObject objectID: UInt64, typeSignature: String) async throws -> [JavaVariable] { [] }
    func setExceptionBreakpoint(_ rule: ExceptionBreakpointRule) async throws {}
    func watchField(named name: String, inClass className: String) async throws -> Int32 { 1 }
    func clearWatchpoint(requestID: Int32) async throws {}
    func capabilities() async throws -> DebugCapabilities { .none }
    func redefineClass(named className: String, bytecode: [UInt8]) async throws {}
    func close() async {}
}
