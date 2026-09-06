import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 디버거 화면의 상태 기계. 실제 JVM 없이 검증한다 — 디버기가 필요한 테스트는 아무도 안 돌리고,
/// 안 돌리는 테스트는 없는 테스트다.
@Suite("디버그 모델 — 붙기·걸기·멈춤·풀기")
@MainActor
struct DebugModelTests {

    /// 대본대로 답하는 가짜 세션.
    private final class FakeSession: DebugSession, @unchecked Sendable {
        var breakpointIDs: [Int32] = [7]
        var stop = JavaStopEvent(threadID: 1, requestID: 7, classID: 2, methodID: 3, codeIndex: 4)
        var frames: [JavaStackFrame] = [
            JavaStackFrame(frameID: 1, className: "Probe", methodName: "step", line: 6, classID: 2, methodID: 3),
            JavaStackFrame(frameID: 2, className: "Probe", methodName: "main", line: 12, classID: 2, methodID: 4),
        ]
        var variables: [JavaVariable] = [JavaVariable(name: "input", typeSignature: "I", value: "182")]
        var setBreakpointError: (any Error)?
        var variablesError: (any Error)?

        private(set) var cleared: [Int32] = []
        private(set) var resumeCount = 0
        private(set) var isClosed = false
        private let stopGate = AsyncGate()

        func setBreakpoint(className: String, line: Int) async throws -> Int32 {
            if let setBreakpointError { throw setBreakpointError }
            return breakpointIDs.isEmpty ? 0 : breakpointIDs.removeFirst()
        }
        func clearBreakpoint(requestID: Int32) async throws { cleared.append(requestID) }
        func waitForBreakpoint() async throws -> JavaStopEvent {
            // **한 번만 통과시킨다.** 계속 열어 두면 걸음을 뗀 직후 리스너가 곧바로 다시
            // 멈춤을 받아 화면을 다시 채우고, 그러면 "먼저 비우는가" 를 잴 수가 없다.
            // 실제 세션도 다음 멈춤까지 막힌다.
            await stopGate.waitOnce()
            return stop
        }
        func letItStop() { stopGate.open() }
        func stackFrames(threadID: UInt64) async throws -> [JavaStackFrame] { frames }
        func localVariables(frame: JavaStackFrame, threadID: UInt64, codeIndex: UInt64) async throws -> [JavaVariable] {
            if let variablesError { throw variablesError }
            return variables
        }
        func resume() async throws { resumeCount += 1 }
        /// 실제로 걸었는지 테스트가 확인할 수 있게 기록한다.
        private(set) var steps: [DebugStep] = []
        func step(_ step: DebugStep, threadID: UInt64) async throws { steps.append(step) }
        func close() async { isClosed = true }
    }

    /// 테스트가 "멈추는 순간" 을 직접 고를 수 있게 하는 문. 잠으로 기다리면 느리고 흔들린다.
    private final class AsyncGate: @unchecked Sendable {
        private var continuations: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false
        private let lock = NSLock()

        func wait() async {
            await withCheckedContinuation { continuation in
                lock.lock()
                if isOpen { lock.unlock(); continuation.resume(); return }
                continuations.append(continuation)
                lock.unlock()
            }
        }

        /// 통과시킨 뒤 다시 닫는다.
        ///
        /// 닫는 일은 동기 함수에 맡긴다 — `NSLock.lock()` 은 비동기 문맥에서 쓸 수 없다
        /// (스레드가 바뀌면 잠금을 놓을 사람이 사라진다).
        func waitOnce() async {
            await wait()
            closeGate()
        }

        private func closeGate() {
            lock.lock()
            isOpen = false
            lock.unlock()
        }
        func open() {
            lock.lock()
            isOpen = true
            let pending = continuations
            continuations = []
            lock.unlock()
            pending.forEach { $0.resume() }
        }
    }

    private func attached(_ session: FakeSession) async -> DebugModel {
        let model = DebugModel()
        await model.attach(session: session, host: "127.0.0.1", port: 5005)
        return model
    }

    @Test("붙기 전에는 아무 상태도 주장하지 않는다")
    func startsDetached() {
        let model = DebugModel()
        #expect(model.connection == .detached)
        #expect(model.frames.isEmpty)
        #expect(model.breakpoints.isEmpty)
    }

    @Test("붙으면 연결됨이 된다")
    func attaches() async {
        let model = await attached(FakeSession())
        #expect(model.connection == .attached(host: "127.0.0.1", port: 5005))
    }

    @Test("브레이크포인트를 토글한다 — 두 번 누르면 지워진다")
    func togglesABreakpoint() async throws {
        let session = FakeSession()
        let model = await attached(session)

        await model.toggleBreakpoint(path: "Probe.java", line: 6, className: "Probe")
        #expect(model.breakpoints.count == 1)
        #expect(model.breakpoints.first?.line == 6)

        await model.toggleBreakpoint(path: "Probe.java", line: 6, className: "Probe")
        #expect(model.breakpoints.isEmpty)
        #expect(session.cleared == [7], "JVM 에서도 지워야 한다 — 목록에서만 빼면 계속 멈춘다")
    }

    /// 걸리지 않은 브레이크포인트를 목록에 보여 주면 사용자는 걸린 줄 안다. 그리고 안 멈추는
    /// 것을 "아직 그 줄을 안 지났다" 로 읽는다.
    @Test("거는 데 실패하면 목록에 넣지 않고 이유를 남긴다")
    func doesNotListABreakpointItFailedToSet() async {
        let session = FakeSession()
        session.setBreakpointError = JavaDebugError.classNotLoaded("Probe")
        let model = await attached(session)

        await model.toggleBreakpoint(path: "Probe.java", line: 6, className: "Probe")
        #expect(model.breakpoints.isEmpty)
        #expect(model.lastError != nil)
    }

    @Test("멈추면 스택과 변수를 채운다")
    func fillsTheFrameOnStop() async throws {
        let session = FakeSession()
        let model = await attached(session)
        session.letItStop()
        await model.waitForNextStopForTesting()

        #expect(model.connection.isStopped)
        #expect(model.frames.count == 2)
        #expect(model.selectedFrame?.methodName == "step", "맨 위 프레임이 기본 선택이다")
        #expect(model.variables.map(\.name) == ["input"])
    }

    @Test("풀면 스택과 변수를 비운다 — 낡은 값을 화면에 남기지 않는다")
    func clearsTheFrameOnResume() async throws {
        let session = FakeSession()
        let model = await attached(session)
        session.letItStop()
        await model.waitForNextStopForTesting()

        await model.resume()
        #expect(session.resumeCount == 1)
        #expect(model.frames.isEmpty)
        #expect(model.variables.isEmpty)
        #expect(!model.connection.isStopped)
    }

    /// 변수 이름표가 없는 것과 변수가 없는 것은 다르다. 빈 목록으로 그리면 사용자는 전자를
    /// 후자로 읽는다.
    @Test("변수 정보가 없으면 빈 목록이 아니라 이유를 보여 준다")
    func explainsMissingVariableInformation() async throws {
        let session = FakeSession()
        session.variablesError = JavaDebugError.noLocalVariableInformation(
            className: "Probe", methodName: "step"
        )
        let model = await attached(session)
        session.letItStop()
        await model.waitForNextStopForTesting()

        #expect(model.variables.isEmpty)
        #expect(model.variableNotice != nil)
    }

    /// 한 걸음 떼는 순간 지금 화면은 낡는다. 안 비우면 사용자는 옛 스택을 보면서 다음
    /// 멈춤을 기다리고, 그 사이 아무 표시도 없어서 눌린 건지 아닌지 모른다.
    @Test("한 걸음 떼면 낡은 스택과 변수를 먼저 비운다")
    func clearsTheStaleFrameWhenStepping() async throws {
        let session = FakeSession()
        let model = await attached(session)
        session.letItStop()
        await model.waitForNextStopForTesting()
        #expect(!model.frames.isEmpty)

        await model.step(.over)
        #expect(session.steps == [.over])
        #expect(model.frames.isEmpty, "낡은 스택이 남았다")
        #expect(model.variables.isEmpty)
        #expect(!model.connection.isStopped)
    }

    @Test("멈춰 있지 않으면 걷지 않는다 — 스레드가 없으면 걸 곳도 없다")
    func doesNotStepWhileRunning() async throws {
        let session = FakeSession()
        let model = await attached(session)
        await model.step(.into)
        #expect(session.steps.isEmpty)
    }

    @Test("떼면 세션을 닫고 모든 것을 비운다")
    func detaches() async throws {
        let session = FakeSession()
        let model = await attached(session)
        await model.toggleBreakpoint(path: "Probe.java", line: 6, className: "Probe")

        await model.detach()
        #expect(session.isClosed)
        #expect(model.connection == .detached)
        #expect(model.breakpoints.isEmpty)
    }
}
