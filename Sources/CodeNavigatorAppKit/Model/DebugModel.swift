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
    /// "i == 500" 같은 조건. 없으면 항상 멈춘다.
    public var condition: BreakpointCondition?

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

/// 변수 패널의 한 줄. 평평한 목록을 나무처럼 그리기 위한 것이다.
///
/// 뷰가 재귀 구조를 다루지 않게 **평평하게 펴서** 준다. SwiftUI 의 `OutlineGroup` 을 쓰면
/// 재귀 타입이 필요하고, 그러면 "누가 누구의 자식인가" 가 모델과 뷰 두 곳에 살게 된다.
public struct DebugVariableRow: Sendable, Hashable, Identifiable {
    public let variable: JavaVariable
    /// 들여쓰기 단. 0 이 최상위.
    public let depth: Int
    public let isExpanded: Bool
    /// 부모까지의 경로. 같은 이름의 필드가 여러 객체에 있으므로 이름만으로는 줄을 못 가른다.
    public let path: [UInt64]

    public var id: String { path.map(String.init).joined(separator: ".") + "/" + variable.name }
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
    /// 왜 멈췄는지. 화면이 브레이크포인트와 예외를 다르게 말해야 한다.
    public private(set) var stopReason: DebugStopReason?
    /// 사용자가 계속 보고 싶어 하는 식들. 멈출 때마다 다시 푼다 — IntelliJ 의 Watches 다.
    public private(set) var watches: [DebugWatch] = []
    /// 이 JVM 이 무엇을 허용하는지. 못 하는 것을 메뉴에 켜 두지 않기 위한 것이다.
    public private(set) var capabilities: DebugCapabilities = .none

    /// 지켜보는 필드들. 이름은 `클래스.필드`, 값은 지울 때 쓸 요청 id.
    public private(set) var watchedFields: [String: Int32] = [:]

    /// 마지막으로 물어본 식과 그 답. 화면이 되돌려 보여 준다.
    public private(set) var lastExpression: String?
    public private(set) var lastExpressionResult: String?

    /// 예외에서 멈추는 규칙. 기본은 안 잡히는 예외만 — caught 를 켜면 프레임워크가 예외로
    /// 흐름을 제어하는 코드에서 초당 수십 번 멈춘다.
    public private(set) var exceptionRule: ExceptionBreakpointRule = .off

    /// 멈춤이 화면에 반영돼야 한다고 알린다. 뷰 계층이 파일을 열고 표시를 다시 그린다 —
    /// 모델이 직접 하면 편집기를 알아야 하고, 그러면 이 모델을 테스트하는 데 편집기가 필요해진다.
    public var onStopped: (@MainActor () async -> Void)?

    private var session: (any DebugSession)?
    private var stopThreadID: UInt64?
    private var stopCodeIndex: UInt64?
    private var listener: Task<Void, Never>?
    /// 테스트가 멈춤 처리를 기다리기 위한 것. 잠으로 기다리면 느리고 흔들린다.
    private var stopHandled: [CheckedContinuation<Void, Never>] = []

    /// 펼친 객체들. 키는 객체 id.
    private var expandedObjectIDs: Set<UInt64> = []
    /// 이미 읽어 온 자식들. 디버기가 멈춰 있는 동안 값은 안 변하므로 다시 묻지 않는다 —
    /// 매번 왕복하면 큰 객체에서 패널이 눈에 띄게 느려진다.
    private var childrenByObjectID: [UInt64: [JavaVariable]] = [:]

    public init() {}

    /// 화면이 그릴 줄들. 펼친 것만 자식이 끼어든다.
    public var variableRows: [DebugVariableRow] {
        var rows: [DebugVariableRow] = []
        appendRows(for: variables, depth: 0, path: [], into: &rows)
        return rows
    }

    private func appendRows(
        for variables: [JavaVariable], depth: Int, path: [UInt64], into rows: inout [DebugVariableRow]
    ) {
        for variable in variables {
            let isExpanded = variable.objectID.map { expandedObjectIDs.contains($0) } ?? false
            rows.append(DebugVariableRow(
                variable: variable, depth: depth, isExpanded: isExpanded, path: path
            ))
            guard isExpanded, let objectID = variable.objectID else { continue }
            let children = childrenByObjectID[objectID] ?? []
            if children.isEmpty {
                // 필드가 없는 객체도 열 수는 있다. 아무것도 안 나오면 사용자는 눌리지
                // 않았다고 읽는다.
                rows.append(DebugVariableRow(
                    variable: JavaVariable(name: "필드 없음", typeSignature: "", value: ""),
                    depth: depth + 1, isExpanded: false, path: path + [objectID]
                ))
            } else {
                appendRows(for: children, depth: depth + 1, path: path + [objectID], into: &rows)
            }
        }
    }

    /// Opens or closes one row.
    public func toggleExpansion(of row: DebugVariableRow) async {
        guard let objectID = row.variable.objectID else { return }

        if expandedObjectIDs.contains(objectID) {
            expandedObjectIDs.remove(objectID)
            return
        }
        expandedObjectIDs.insert(objectID)
        // 이미 읽었으면 다시 묻지 않는다.
        guard childrenByObjectID[objectID] == nil, let session else { return }
        childrenByObjectID[objectID] =
            (try? await session.fields(ofObject: objectID, typeSignature: row.variable.typeSignature)) ?? []
    }

    /// 테스트가 변수 목록을 직접 놓기 위한 것. 실제로는 멈춤이 채운다.
    func setVariablesForTesting(_ variables: [JavaVariable]) {
        self.variables = variables
    }

    public var selectedFrame: JavaStackFrame? {
        frames.first { $0.frameID == selectedFrameID } ?? frames.first
    }

    // MARK: 붙기 · 떼기

    public func attach(session: any DebugSession, host: String, port: UInt16) async {
        self.session = session
        connection = .attached(host: host, port: port)
        lastError = nil
        // 이 JVM 이 무엇을 허용하는지 먼저 묻는다. 못 하는 것을 메뉴에 켜 두면 사용자는
        // 눌러 보고 알 수 없는 오류를 본다.
        capabilities = (try? await session.capabilities()) ?? .none
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
        watches = []
        watchedFields = [:]
        capabilities = .none
        exceptionRule = .off
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
            breakpoints.append(DebugBreakpoint(
                path: path, line: line, className: className,
                requestID: requestID, condition: nil
            ))
            lastError = nil
        } catch {
            // 걸리지 않은 것을 목록에 넣지 않는다. 넣으면 사용자는 걸린 줄 알고, 안 멈추는
            // 것을 "아직 그 줄을 안 지났다" 로 읽는다.
            lastError = "\(className):\(line) 에 브레이크포인트를 걸지 못했습니다: \(error)"
        }
    }

    /// 예외에서 멈추는 규칙을 바꾼다.
    public func setExceptionRule(_ rule: ExceptionBreakpointRule) async {
        guard let session else { return }
        do {
            try await session.setExceptionBreakpoint(rule)
            exceptionRule = rule
            lastError = nil
        } catch {
            lastError = "예외 중단 설정을 바꾸지 못했습니다: \(error)"
        }
    }

    /// 브레이크포인트에 조건을 붙이거나 뗀다.
    ///
    /// JDWP 에는 식 조건이 없어서 JVM 에는 아무것도 안 보낸다 — 멈춘 뒤 우리가 판정한다.
    public func setCondition(_ text: String, forBreakpointWithID id: String) {
        guard let index = breakpoints.firstIndex(where: { $0.id == id }) else { return }
        breakpoints[index].condition = BreakpointCondition(text: text)
        if breakpoints[index].condition == nil, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            // 읽을 수 없는 조건을 조용히 버리면 사용자는 조건이 걸린 줄 알고 기다린다.
            lastError = "조건을 읽지 못했습니다: \(text) — `변수 == 값` 형태만 됩니다"
        } else {
            lastError = nil
        }
    }

    /// 멈춘 자리에서 식을 푼다.
    ///
    /// 변수에서 시작해 필드와 배열 첨자로 내려간다. 메서드는 안 부른다 — 물어보는 것만으로
    /// 프로그램이 바뀌면 그건 관찰이 아니다.
    public func evaluate(_ text: String) async {
        lastExpression = text
        guard connection.isStopped else {
            lastExpressionResult = "멈춰 있을 때만 물어볼 수 있습니다"
            return
        }
        guard let expression = DebugExpression(text: text) else {
            lastExpressionResult = "읽을 수 없는 식입니다 — 변수·필드·배열 첨자만 됩니다 (메서드 호출 불가)"
            return
        }
        guard let session else { return }

        guard var current = variables.first(where: { $0.name == expression.root }) else {
            // **없는 변수를 조용히 넘기지 않는다.** 값이 안 나오면 사용자는 우리가 못 읽은
            // 것인지 그 자리에 없는 것인지 구별할 수 없다.
            lastExpressionResult = "\(expression.root) 이(가) 이 자리에 없습니다"
            return
        }

        for step in expression.steps {
            guard let objectID = current.objectID else {
                lastExpressionResult = "\(current.name) 은(는) 더 들어갈 수 없는 값입니다 (\(current.value))"
                return
            }
            let children = (try? await session.fields(
                ofObject: objectID, typeSignature: current.typeSignature
            )) ?? []

            switch step {
            case .field(let name):
                guard let next = children.first(where: { $0.name == name }) else {
                    lastExpressionResult = "\(name) 필드가 없습니다"
                    return
                }
                current = next
            case .index(let index):
                // 배열 원소는 `[0]` 같은 이름으로 온다.
                guard let next = children.first(where: { $0.name == "[\(index)]" }) else {
                    lastExpressionResult = "\(index)번 원소가 없습니다"
                    return
                }
                current = next
            }
        }
        lastExpressionResult = current.value
    }

    /// 필드가 바뀔 때 멈추게 하거나, 이미 지켜보고 있으면 그만둔다.
    public func toggleFieldWatch(named name: String, inClass className: String) async {
        guard let session else { return }
        let key = "\(className).\(name)"

        if let existing = watchedFields[key] {
            try? await session.clearWatchpoint(requestID: existing)
            watchedFields[key] = nil
            return
        }
        do {
            watchedFields[key] = try await session.watchField(named: name, inClass: className)
            lastError = nil
        } catch let error as JavaDebugError {
            // 걸리지 않은 것을 목록에 넣지 않는다 — 넣으면 사용자는 지켜보는 줄 알고 기다린다.
            lastError = Self.notice(for: error)
        } catch {
            lastError = "필드를 지켜보지 못했습니다: \(error)"
        }
    }

    /// Watch 목록에 식을 더한다. 이미 있으면 뺀다.
    public func toggleWatch(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let index = watches.firstIndex(where: { $0.expression == trimmed }) {
            watches.remove(at: index)
            return
        }
        guard DebugExpression(text: trimmed) != nil else {
            lastError = "읽을 수 없는 식입니다 — 변수·필드·배열 첨자만 됩니다 (메서드 호출 불가)"
            return
        }
        watches.append(DebugWatch(expression: trimmed, value: nil))
        await refreshWatches()
    }

    /// 모든 Watch 를 다시 푼다. 멈출 때마다 부른다 — 값이 바뀌었는데 옛 값이 떠 있으면
    /// 사용자는 그것을 지금 값으로 읽는다.
    public func refreshWatches() async {
        guard connection.isStopped else {
            // 달리는 중에는 값이 없다. **옛 값을 남기지 않는다.**
            watches = watches.map { DebugWatch(expression: $0.expression, value: nil) }
            return
        }
        var refreshed: [DebugWatch] = []
        for watch in watches {
            await evaluate(watch.expression)
            refreshed.append(DebugWatch(expression: watch.expression, value: lastExpressionResult))
        }
        watches = refreshed
    }

    /// 컴파일된 클래스를 멈춘 채로 갈아 끼운다.
    public func hotSwap(className: String, bytecode: [UInt8]) async {
        guard let session else { return }
        do {
            try await session.redefineClass(named: className, bytecode: bytecode)
            lastError = nil
        } catch let error as JavaDebugError {
            lastError = Self.notice(for: error)
        } catch {
            lastError = "핫스왑에 실패했습니다: \(error)"
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
        stopReason = stop.reason
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

        // 조건이 붙어 있으면 여기서 판정한다. JDWP 에는 식 조건이 없어서, 일단 멈춘 뒤
        // 값을 읽고 아니면 다시 보낸다. **화면을 건드리기 전에** 판정해야 한다 — 먼저
        // 그리면 조건에 안 맞는 회차마다 화면이 깜빡이고, 사용자는 "멈췄다 말았다" 로 읽는다.
        if let matched = breakpoints.first(where: { $0.requestID == stop.requestID }),
           let condition = matched.condition,
           !condition.matches(variables: variables) {
            clearStoppedState()
            connection = .attached(host: host, port: port)
            try? await session?.resume()
            notifyStopHandled()
            return
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
        // Watch 는 멈춘 뒤에 다시 푼다. 조건 판정보다 **뒤**여야 한다 — 조건에 안 맞아
        // 그냥 지나갈 회차에서 Watch 를 풀면 왕복만 늘고 화면에는 안 보인다.
        await refreshWatches()
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
        case .fieldNotFound(let className, let fieldName):
            return "\(className) 에 \(fieldName) 필드가 없습니다"
        case .redefinitionNotSupported:
            return "이 JVM 은 핫스왑을 지원하지 않습니다"
        case .redefinitionRejected(let reason):
            return "핫스왑 거절 — \(reason)"
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
        // 객체 id 는 멈춘 순간에만 뜻이 있다. 들고 있으면 다음 멈춤에서 **다른 객체의 값을
        // 옛 이름으로** 보여 준다.
        expandedObjectIDs = []
        childrenByObjectID = [:]
        stoppedBreakpointPath = nil
        stoppedLine = nil
        stopReason = nil
        // 물어본 답도 버린다. 멈춘 자리가 바뀌면 그 답은 다른 자리의 값이고, 남겨 두면
        // 사용자는 지금 자리의 값으로 읽는다.
        lastExpression = nil
        lastExpressionResult = nil
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
