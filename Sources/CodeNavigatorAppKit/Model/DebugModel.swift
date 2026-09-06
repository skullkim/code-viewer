import CodeNavigatorContract
import Foundation
import Observation

/// A breakpoint the user asked for, and what the JVM called it.
///
/// `requestID` 를 같이 든다. 목록에서만 지우고 JVM 에 안 알리면 프로그램은 **계속 그 줄에서
/// 멈추는데** 화면에는 브레이크포인트가 없다 — 사용자가 원인을 찾을 방법이 없는 상태다.
public struct DebugBreakpoint: Sendable, Hashable, Identifiable {
    public let path: String
    public let line: Int
    public let className: String
    public let requestID: Int32

    public var id: String { "\(path):\(line)" }
}

public enum DebugConnection: Sendable, Hashable {
    case detached
    case attaching(host: String, port: UInt16)
    case attached(host: String, port: UInt16)
    /// 멈춰 있다. 어디에 멈췄는지는 `frames` 가 답한다.
    case stopped(host: String, port: UInt16)
    case failed(String)

    public var isStopped: Bool {
        if case .stopped = self { return true }
        return false
    }

    public var isAttached: Bool {
        switch self {
        case .attached, .stopped: return true
        case .detached, .attaching, .failed: return false
        }
    }
}

/// 디버거 화면의 상태.
///
/// 세션은 프로토콜로 받는다 — 화면 상태 기계를 재는 데 진짜 JVM 이 필요하면 아무도 그
/// 테스트를 안 돌리고, 안 돌리는 테스트는 없는 테스트다.
@MainActor
@Observable
public final class DebugModel {

    public private(set) var connection: DebugConnection = .detached
    public private(set) var breakpoints: [DebugBreakpoint] = []
    public private(set) var frames: [JavaStackFrame] = []
    public private(set) var variables: [JavaVariable] = []
    /// 변수를 못 읽은 이유. **빈 목록과 구별해야 한다** — 없는 것과 알 수 없는 것은 다른 사건이다.
    public private(set) var variableNotice: String?
    public private(set) var lastError: String?
    public private(set) var selectedFrameID: UInt64?
    /// 멈춘 자리 — **우리가 건 브레이크포인트일 때만** 채워진다.
    ///
    /// 프레임의 클래스 이름으로 파일을 되짚지 않는다. 되짚기는 틀릴 수 있고, 엉뚱한 파일이
    /// 열리는 것은 아무것도 안 여는 것보다 나쁘다 — 사용자가 그 파일을 고치기 시작한다.
    public private(set) var stoppedBreakpointPath: String?
    public private(set) var stoppedLine: Int?

    /// 멈춤이 화면에 반영돼야 한다고 알린다. 뷰 계층이 파일을 열고 표시를 다시 그린다 —
    /// 모델이 직접 하면 편집기를 알아야 하고, 그러면 이 모델을 테스트하는 데 편집기가 필요해진다.
    public var onStopped: (@MainActor () async -> Void)?

    private var session: (any DebugSession)?
    private var stopThreadID: UInt64?
    private var stopCodeIndex: UInt64?
    private var listener: Task<Void, Never>?
    /// 테스트가 멈춤 처리를 기다리기 위한 것. 잠으로 기다리면 느리고 흔들린다.
    private var stopHandled: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public var selectedFrame: JavaStackFrame? {
        frames.first { $0.frameID == selectedFrameID } ?? frames.first
    }

    // MARK: 붙기 · 떼기

    public func attach(session: any DebugSession, host: String, port: UInt16) async {
        self.session = session
        connection = .attached(host: host, port: port)
        lastError = nil
        startListening(host: host, port: port)
    }

    public func reportAttachFailure(_ reason: String) {
        connection = .failed(reason)
        lastError = reason
    }

    public func detach() async {
        listener?.cancel()
        listener = nil
        // JVM 에 걸린 것을 지우고 나서 닫는다. 반대로 하면 다음 디버거가 우리가 남긴
        // 브레이크포인트를 만나고, 그건 아무도 설명할 수 없는 멈춤이 된다.
        for breakpoint in breakpoints {
            try? await session?.clearBreakpoint(requestID: breakpoint.requestID)
        }
        await session?.close()
        session = nil
        connection = .detached
        breakpoints = []
        clearStoppedState()
    }

    // MARK: 브레이크포인트

    public func toggleBreakpoint(path: String, line: Int, className: String) async {
        guard let session else { return }

        if let existing = breakpoints.first(where: { $0.path == path && $0.line == line }) {
            do {
                try await session.clearBreakpoint(requestID: existing.requestID)
                breakpoints.removeAll { $0.id == existing.id }
            } catch {
                lastError = "브레이크포인트를 지우지 못했습니다: \(error)"
            }
            return
        }

        do {
            let requestID = try await session.setBreakpoint(className: className, line: line)
            breakpoints.append(
                DebugBreakpoint(path: path, line: line, className: className, requestID: requestID)
            )
            lastError = nil
        } catch {
            // 걸리지 않은 것을 목록에 넣지 않는다. 넣으면 사용자는 걸린 줄 알고, 안 멈추는
            // 것을 "아직 그 줄을 안 지났다" 로 읽는다.
            lastError = "\(className):\(line) 에 브레이크포인트를 걸지 못했습니다: \(error)"
        }
    }

    public func selectFrame(_ frame: JavaStackFrame) async {
        selectedFrameID = frame.frameID
        await loadVariables(for: frame)
    }

    // MARK: 멈춤 · 재개

    private func startListening(host: String, port: UInt16) {
        listener = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let session = await self.session else { return }
                do {
                    let stop = try await session.waitForBreakpoint()
                    await self.handleStop(stop, host: host, port: port)
                } catch {
                    await self.reportListenerFailure(error)
                    return
                }
            }
        }
    }

    private func reportListenerFailure(_ error: any Error) {
        guard connection.isAttached else { return }
        connection = .failed("디버기와의 연결이 끊겼습니다: \(error)")
    }

    private func handleStop(_ stop: JavaStopEvent, host: String, port: UInt16) async {
        stopThreadID = stop.threadID
        stopCodeIndex = stop.codeIndex
        connection = .stopped(host: host, port: port)

        do {
            frames = try await session?.stackFrames(threadID: stop.threadID) ?? []
        } catch {
            frames = []
            lastError = "호출 스택을 읽지 못했습니다: \(error)"
        }
        selectedFrameID = frames.first?.frameID
        if let top = frames.first {
            await loadVariables(for: top)
        }

        // 우리가 건 브레이크포인트를 requestID 로 되짚는다. 못 찾으면 비운다 — 모르는
        // 자리를 아는 척하지 않는다.
        if let matched = breakpoints.first(where: { $0.requestID == stop.requestID }) {
            stoppedBreakpointPath = matched.path
            stoppedLine = matched.line
        } else {
            stoppedBreakpointPath = nil
            stoppedLine = nil
        }
        await onStopped?()

        notifyStopHandled()
    }

    private func loadVariables(for frame: JavaStackFrame) async {
        guard let session, let threadID = stopThreadID, let codeIndex = stopCodeIndex else { return }
        do {
            variables = try await session.localVariables(
                frame: frame, threadID: threadID, codeIndex: codeIndex
            )
            variableNotice = variables.isEmpty ? "이 자리에 지역 변수가 없습니다" : nil
        } catch let error as JavaDebugError {
            variables = []
            variableNotice = Self.notice(for: error)
        } catch {
            variables = []
            variableNotice = "지역 변수를 읽지 못했습니다: \(error)"
        }
    }

    private static func notice(for error: JavaDebugError) -> String {
        switch error {
        case .noLocalVariableInformation(let className, let methodName):
            return "\(className).\(methodName) 은 디버그 정보 없이 컴파일되어 변수 이름을 알 수 없습니다 (javac -g 필요)"
        case .classNotLoaded(let className):
            return "\(className) 이 아직 로드되지 않았습니다"
        case .noExecutableCodeOnLine(let className, let line):
            return "\(className) \(line)행에는 실행 코드가 없습니다"
        case .notSuspended:
            return "디버기가 멈춰 있지 않습니다"
        }
    }

    /// 한 걸음 나아간다. 멈춤은 리스너가 받아 화면을 다시 채운다 — 브레이크포인트와 같은 길이다.
    public func step(_ step: DebugStep) async {
        guard let session, let threadID = stopThreadID else { return }
        // 걸음을 떼는 순간 지금 화면은 낡은다. 먼저 비워야 사용자가 옛 스택을 보며 기다리지 않는다.
        let stoppedAt = connection
        clearStoppedState()
        if case .stopped(let host, let port) = stoppedAt {
            connection = .attached(host: host, port: port)
        }
        do {
            try await session.step(step, threadID: threadID)
        } catch {
            lastError = "한 걸음 나아가지 못했습니다: \(error)"
        }
    }

    public func resume() async {
        guard let session else { return }
        do {
            try await session.resume()
        } catch {
            lastError = "재개하지 못했습니다: \(error)"
            return
        }
        // 낡은 스택과 변수를 화면에 남기지 않는다. 남기면 사용자는 아직 멈춰 있다고 읽는다.
        clearStoppedState()
        if case .stopped(let host, let port) = connection {
            connection = .attached(host: host, port: port)
        }
    }

    private func clearStoppedState() {
        stoppedBreakpointPath = nil
        stoppedLine = nil
        frames = []
        variables = []
        variableNotice = nil
        selectedFrameID = nil
        stopThreadID = nil
        stopCodeIndex = nil
    }

    // MARK: 테스트 지원

    /// 다음 멈춤 처리가 끝날 때까지 기다린다. 잠 대신 쓰는 것 — 잠으로 기다리는 테스트는
    /// 느리거나 흔들리거나 둘 다다.
    func waitForNextStopForTesting() async {
        if connection.isStopped { return }
        await withCheckedContinuation { continuation in
            stopHandled.append(continuation)
        }
    }

    private func notifyStopHandled() {
        let waiting = stopHandled
        stopHandled = []
        waiting.forEach { $0.resume() }
    }
}
