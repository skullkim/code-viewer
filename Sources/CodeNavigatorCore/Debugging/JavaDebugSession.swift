import CodeNavigatorContract
import Foundation

/// JDWP 명령 번호. 숫자를 호출부에 흩어 두면 어느 것이 무엇인지 읽을 수 없고, 하나 틀려도
/// 컴파일은 통과한다 — 그리고 틀린 명령의 응답은 그럴듯한 바이트로 온다.
private enum Command {
    static let virtualMachine: UInt8 = 1
    static let classesBySignature: UInt8 = 2
    static let allThreads: UInt8 = 4
    static let vmSuspend: UInt8 = 8
    static let vmResume: UInt8 = 9

    static let referenceType: UInt8 = 2
    static let signature: UInt8 = 1
    static let fields: UInt8 = 4
    static let methods: UInt8 = 5

    static let classType: UInt8 = 3
    static let superclass: UInt8 = 1

    static let objectReference: UInt8 = 9
    static let referenceTypeOfObject: UInt8 = 1
    static let objectGetValues: UInt8 = 2

    static let stringReference: UInt8 = 10
    static let stringValue: UInt8 = 1

    static let arrayReference: UInt8 = 13
    static let arrayLength: UInt8 = 1
    static let arrayGetValues: UInt8 = 2

    static let method: UInt8 = 6
    static let lineTable: UInt8 = 1
    static let variableTable: UInt8 = 2

    static let threadReference: UInt8 = 11
    static let threadName: UInt8 = 1
    static let threadStatus: UInt8 = 4
    static let threadResume: UInt8 = 3
    static let suspendCount: UInt8 = 12
    static let frames: UInt8 = 6
    static let frameCount: UInt8 = 7

    static let stackFrame: UInt8 = 16
    static let getValues: UInt8 = 1

    static let eventRequest: UInt8 = 15
    static let eventSet: UInt8 = 1
    static let eventClear: UInt8 = 2
}

private enum EventKind {
    static let breakpoint: UInt8 = 2
    static let classPrepare: UInt8 = 8
}

private enum SuspendPolicy {
    static let none: UInt8 = 0
    static let eventThread: UInt8 = 1
    static let all: UInt8 = 2
}

/// IntelliJ 급 Java 디버깅의 1차 범위 — 붙기, 걸기, 보기, 풀기.
///
/// 언어 서버를 쓰지 않는다. `java-debug` 경로는 Eclipse JDT(수백 MB)를 끌고 오고, 그러면
/// "작고 네이티브" 라는 이 앱의 유일한 정당성이 사라진다. JVM 이 이미 말하는 표준 프로토콜에
/// 직접 붙는 편이 작고, 그 대가로 프레이밍을 우리가 책임진다.
public actor JavaDebugSession: DebugSession {
    private let connection: JDWPConnection
    private var sizes: JDWPIdentifierSizes
    /// 클래스 시그니처 → refTypeID. `ClassPrepare` 로 늦게 채워지는 것도 여기 들어온다.
    private var classIDsBySignature: [String: UInt64] = [:]
    private var lineTablesByMethod: [UInt64: JDWPLineTable] = [:]

    /// Injectable so the failure paths can be driven without a JVM. `javac -g` 없는 클래스를
    /// 만나는 경로가 특히 그렇다 — 그걸 재려고 디버기를 따로 컴파일해 두면 아무도 안 돌린다.
    init(connection: JDWPConnection, sizes: JDWPIdentifierSizes) {
        self.connection = connection
        self.sizes = sizes
    }

    /// Attaches to a JVM started with `-agentlib:jdwp=…,server=y`.
    public static func attach(host: String, port: UInt16) async throws -> JavaDebugSession {
        let transport = try JDWPSocketTransport.connect(host: host, port: port)
        let connection = JDWPConnection(transport: transport)
        try await connection.handshake()
        // 리더는 핸드셰이크 **뒤에** 켠다. 핸드셰이크만 패킷 프레이밍이 아니라 맨 바이트라,
        // 리더가 먼저 돌면 그 14바이트를 패킷 헤더로 읽는다.
        await connection.startReading()
        // ID 폭을 먼저 읽는다. 이 값 없이 파싱한 것은 전부 못 믿는다.
        let sizes = try await connection.readIdentifierSizes()
        return JavaDebugSession(connection: connection, sizes: sizes)
    }

    public func close() async {
        await connection.close()
    }

    // MARK: - 클래스와 줄

    private func signature(forClassName className: String) -> String {
        "L" + className.replacingOccurrences(of: ".", with: "/") + ";"
    }

    /// Finds a loaded class, or nil when the JVM has not loaded it yet.
    ///
    /// **0건은 "그런 클래스가 없다" 가 아니다.** `suspend=y` 로 띄운 JVM 은 우리 클래스를 아직
    /// 로드하지 않았고, 그때 이 조회는 정상적으로 0건을 답한다. 0건을 "없음" 으로 읽으면
    /// 브레이크포인트가 조용히 아무 데도 안 걸린다 — 그리고 그건 "아직 그 줄을 안 지났다" 와
    /// 화면에서 구별되지 않는다. 그래서 nil 을 돌려주고, 위층이 `ClassPrepare` 로 기다린다.
    public func loadedClassID(named className: String) async throws -> UInt64? {
        let signature = signature(forClassName: className)
        if let cached = classIDsBySignature[signature] { return cached }

        var payload = withUnsafeBytes(of: UInt32(signature.utf8.count).bigEndian, Array.init)
        payload += Array(signature.utf8)
        let reply = try await connection.request(
            commandSet: Command.virtualMachine, command: Command.classesBySignature, payload: payload
        )

        var reader = JDWPReader(bytes: reply)
        let count = Int(try reader.readUInt32())
        guard count > 0 else { return nil }
        _ = try reader.readByte()   // refTypeTag
        let classID = try reader.readIdentifier(size: sizes.referenceTypeID)
        classIDsBySignature[signature] = classID
        return classID
    }

    /// Asks the JVM to notify us when a class is prepared, so a breakpoint can be planted on a
    /// class that has not loaded yet.
    @discardableResult
    public func requestClassPrepareNotification(forClassName className: String) async throws -> Int32 {
        // modifier kind 5 = ClassMatch, 패턴은 점 표기 그대로.
        var payload: [UInt8] = [EventKind.classPrepare, SuspendPolicy.all]
        payload += withUnsafeBytes(of: UInt32(1).bigEndian, Array.init)   // modifier count
        payload += [5]
        payload += withUnsafeBytes(of: UInt32(className.utf8.count).bigEndian, Array.init)
        payload += Array(className.utf8)

        let reply = try await connection.request(
            commandSet: Command.eventRequest, command: Command.eventSet, payload: payload
        )
        var reader = JDWPReader(bytes: reply)
        return try reader.readInt32()
    }

    private func lineTable(classID: UInt64, methodID: UInt64) async throws -> JDWPLineTable {
        if let cached = lineTablesByMethod[methodID] { return cached }
        var payload = identifierBytes(classID, size: sizes.referenceTypeID)
        payload += identifierBytes(methodID, size: sizes.methodID)
        let reply = try await connection.request(
            commandSet: Command.method, command: Command.lineTable, payload: payload
        )
        let table = try JDWPLineTable(payload: reply)
        lineTablesByMethod[methodID] = table
        return table
    }

    func methods(ofClass classID: UInt64) async throws -> [JDWPMethod] {
        let reply = try await connection.request(
            commandSet: Command.referenceType,
            command: Command.methods,
            payload: identifierBytes(classID, size: sizes.referenceTypeID)
        )
        return try JDWPMethod.parseList(payload: reply, methodIDSize: sizes.methodID)
    }

    // MARK: - 브레이크포인트

    /// Plants a breakpoint at `className:line`, returning the JVM's request id.
    ///
    /// 그 줄을 덮는 메서드를 찾아 그 안의 코드 인덱스에 건다. 실행 코드가 없는 줄이면
    /// **가까운 줄로 옮기지 않고** 실패한다 — 사용자가 찍지 않은 줄에서 멈추는 것은 편의가
    /// 아니라 디버거가 거짓말을 한 것이다.
    @discardableResult
    public func setBreakpoint(className: String, line: Int) async throws -> Int32 {
        guard let classID = try await loadedClassID(named: className) else {
            // 아직 로드 전이다. **실패로 끝내지 않는다** — `suspend=y` 로 띄운 JVM 은 우리
            // 클래스를 전부 로드 전이고, 그게 처음부터 디버깅하려는 사람의 정상 상태다.
            // 로드되면 걸도록 예약하고, 예약했다는 사실을 id 로 돌려준다.
            return try await deferBreakpoint(className: className, line: line)
        }
        return try await placeBreakpoint(classID: classID, className: className, line: line)
    }

    /// 아직 로드되지 않은 클래스에 걸어 달라는 요청. `ClassPrepare` 를 걸어 두고 기다린다.
    ///
    /// 돌려주는 id 는 **ClassPrepare 요청의 id** 다. 사용자가 그 브레이크포인트를 지우면
    /// 이 대기도 같이 지워져야 하고, 그러려면 지울 수 있는 손잡이가 하나여야 한다.
    private func deferBreakpoint(className: String, line: Int) async throws -> Int32 {
        let reply = try await connection.request(
            commandSet: Command.eventRequest,
            command: Command.eventSet,
            payload: JDWPClassPrepareRequest.payload(className: className)
        )
        var reader = JDWPReader(bytes: reply)
        let requestID = try reader.readInt32()
        deferredBreakpoints[requestID] = DeferredBreakpoint(className: className, line: line)
        return requestID
    }

    private struct DeferredBreakpoint: Sendable, Hashable {
        let className: String
        let line: Int
    }

    /// 로드를 기다리는 브레이크포인트들. 키는 ClassPrepare 요청 id.
    private var deferredBreakpoints: [Int32: DeferredBreakpoint] = [:]

    /// 예약된 브레이크포인트를 실제로 건 뒤의 요청 id. 지울 때 이 둘을 같이 지운다.
    private var placedForDeferred: [Int32: Int32] = [:]

    private func placeBreakpoint(classID: UInt64, className: String, line: Int) async throws -> Int32 {

        for method in try await methods(ofClass: classID) {
            let table = try await lineTable(classID: classID, methodID: method.id)
            guard !table.isNative, let codeIndex = table.codeIndex(forLine: line) else { continue }

            // location = typeTag(1=CLASS) + classID + methodID + codeIndex(8바이트 고정)
            var location: [UInt8] = [1]
            location += identifierBytes(classID, size: sizes.referenceTypeID)
            location += identifierBytes(method.id, size: sizes.methodID)
            location += withUnsafeBytes(of: codeIndex.bigEndian, Array.init)

            var payload: [UInt8] = [EventKind.breakpoint, SuspendPolicy.all]
            payload += withUnsafeBytes(of: UInt32(1).bigEndian, Array.init)   // modifier count
            payload += [7]                                                    // LocationOnly
            payload += location

            let reply = try await connection.request(
                commandSet: Command.eventRequest, command: Command.eventSet, payload: payload
            )
            var reader = JDWPReader(bytes: reply)
            return try reader.readInt32()
        }
        throw JavaDebugError.noExecutableCodeOnLine(className: className, line: line)
    }

    public func clearBreakpoint(requestID: Int32) async throws {
        // 예약이었다면 ClassPrepare 대기와, 이미 걸린 실제 브레이크포인트를 **둘 다** 지운다.
        // 하나만 지우면 사용자는 지웠는데 계속 멈추거나, 다음 로드에 되살아나는 것을 본다.
        if let deferred = deferredBreakpoints.removeValue(forKey: requestID) {
            _ = deferred
            try await clear(kind: JDWPClassPrepareRequest.eventKind, requestID: requestID)
            if let placed = placedForDeferred.removeValue(forKey: requestID) {
                try await clear(kind: EventKind.breakpoint, requestID: placed)
            }
            return
        }
        try await clear(kind: EventKind.breakpoint, requestID: requestID)
    }

    private func clear(kind: UInt8, requestID: Int32) async throws {
        var payload: [UInt8] = [kind]
        payload += withUnsafeBytes(of: requestID.bigEndian, Array.init)
        _ = try await connection.request(
            commandSet: Command.eventRequest, command: Command.eventClear, payload: payload
        )
    }

    // MARK: - 예외 브레이크포인트

    /// 지금 걸려 있는 예외 요청. 갈아 끼울 때 지우기 위해 들고 있다 — 안 지우면 규칙이
    /// 쌓여서 껐다고 생각한 것에서 계속 멈춘다.
    private var exceptionRequestID: Int32?

    public func setExceptionBreakpoint(_ rule: ExceptionBreakpointRule) async throws {
        if let existing = exceptionRequestID {
            try? await clear(kind: JDWPExceptionRequest.eventKind, requestID: existing)
            exceptionRequestID = nil
        }
        guard let payload = JDWPExceptionRequest.payload(
            classID: nil,
            caught: rule.breakOnCaught,
            uncaught: rule.breakOnUncaught,
            referenceTypeIDSize: sizes.referenceTypeID
        ) else {
            // 둘 다 끔 = 끄기. 요청을 안 만드는 것이 맞다.
            return
        }
        let reply = try await connection.request(
            commandSet: Command.eventRequest, command: Command.eventSet, payload: payload
        )
        var reader = JDWPReader(bytes: reply)
        exceptionRequestID = try reader.readInt32()
    }

    // MARK: - 멈춤과 재개

    /// Waits until the debuggee stops at a breakpoint.
    public func waitForBreakpoint() async throws -> JavaStopEvent {
        while true {
            let event = try await connection.nextEvent()

            // 기다리던 클래스가 로드됐다. 이제 진짜로 걸고, **다시 달리게 한다** — 여기서
            // 멈춰 있으면 사용자는 자기가 걸지도 않은 자리에서 멈춘 화면을 본다.
            if let prepared = try JDWPClassPrepareRequest.parse(
                event: event,
                referenceTypeIDSize: sizes.referenceTypeID,
                objectIDSize: sizes.objectID
            ) {
                await placeDeferredBreakpoint(for: prepared)
                try? await resume()
                continue
            }

            // 예외 이벤트는 페이로드 모양이 브레이크포인트와 다르다 — 위치 뒤에 예외 객체와
            // 잡히는 위치가 더 붙는다. 먼저 시도해서 맞으면 그것이다.
            if let thrown = try JDWPExceptionRequest.parse(
                event: event,
                referenceTypeIDSize: sizes.referenceTypeID,
                methodIDSize: sizes.methodID,
                objectIDSize: sizes.objectID
            ) {
                await clearPendingStepRequest()
                return JavaStopEvent(
                    threadID: thrown.threadID,
                    requestID: thrown.requestID,
                    classID: thrown.classID,
                    methodID: thrown.methodID,
                    codeIndex: thrown.codeIndex,
                    reason: .exception(isCaught: thrown.isCaught, objectID: thrown.exceptionObjectID)
                )
            }

            guard let stop = try parseStop(event) else { continue }
            // 스텝으로 멈췄든 브레이크포인트로 멈췄든, 살아 있는 스텝 요청은 여기서 거둔다.
            // 안 거두면 그 다음부터 매 줄 멈춘다.
            await clearPendingStepRequest()
            return stop
        }
    }

    /// `Event.Composite` (64, 100) 하나에 이벤트가 여러 개 들어올 수 있다. 첫 개만 읽고
    /// 나머지를 버리면, 같은 순간에 걸린 다른 브레이크포인트가 소리 없이 사라진다.
    private func parseStop(_ event: JDWPEvent) throws -> JavaStopEvent? {
        guard event.commandSet == 64, event.command == 100 else { return nil }
        var reader = JDWPReader(bytes: event.payload)
        _ = try reader.readByte()   // suspend policy
        let count = Int(try reader.readInt32())
        for _ in 0..<count {
            let kind = try reader.readByte()
            let requestID = try reader.readInt32()
            // 스텝과 브레이크포인트는 페이로드 모양이 같다(스레드 + 위치). 둘 다 받는다 —
            // 화면에서 "왜 여기서 멈췄지" 의 답은 하나여야 한다.
            guard kind == EventKind.breakpoint || kind == JDWPStepRequest.eventKind else {
                // 우리가 아직 다루지 않는 종류다. 페이로드 폭을 모르므로 **이어서 읽지
                // 않는다** — 모르는 채로 계속 읽으면 그 뒤가 전부 쓰레기가 된다.
                return nil
            }
            let threadID = try reader.readIdentifier(size: sizes.objectID)
            _ = try reader.readByte()   // location typeTag
            let classID = try reader.readIdentifier(size: sizes.referenceTypeID)
            let methodID = try reader.readIdentifier(size: sizes.methodID)
            let codeIndex = try reader.readUInt64()
            return JavaStopEvent(
                threadID: threadID, requestID: requestID,
                classID: classID, methodID: methodID, codeIndex: codeIndex,
                reason: kind == JDWPStepRequest.eventKind ? .step : .breakpoint
            )
        }
        return nil
    }

    /// 진단용 — 멈췄다고 믿는 스레드가 실제로 몇 겹 멈춰 있는지.
    public func suspendCount(threadID: UInt64) async throws -> Int32 {
        let reply = try await connection.request(
            commandSet: Command.threadReference,
            command: Command.suspendCount,
            payload: identifierBytes(threadID, size: sizes.objectID)
        )
        var reader = JDWPReader(bytes: reply)
        return try reader.readInt32()
    }

    /// Steps one line and resumes.
    ///
    /// **요청을 쓰고 곧바로 지운다.** 안 지우면 매 줄 멈춘다 — 사용자는 "스텝을 한 번
    /// 눌렀는데 계속 멈춘다" 를 겪고, 그게 브레이크포인트 때문인지 스텝 때문인지 화면에서
    /// 구별하지 못한다. JVM 은 요청이 살아 있는 한 계속 보고한다.
    ///
    /// 지우는 것이 **재개보다 먼저**다. 재개한 뒤에 지우면 그 사이에 이미 한 걸음이 보고돼
    /// 두 번 멈춘다.
    public func step(_ step: DebugStep, threadID: UInt64) async throws {
        let payload = JDWPStepRequest.payload(
            threadID: threadID, depth: Self.depth(for: step), objectIDSize: sizes.objectID
        )
        let reply = try await connection.request(
            commandSet: Command.eventRequest, command: Command.eventSet, payload: payload
        )
        var reader = JDWPReader(bytes: reply)
        let requestID = try reader.readInt32()

        try await resume()
        // 한 걸음이 보고된 뒤에 지운다. 여기서 실패해도 재개는 이미 됐으므로 조용히 넘기지
        // 않고 남긴다 — 안 지워진 스텝 요청은 다음 실행 내내 사용자를 붙잡는다.
        pendingStepRequestID = requestID
    }

    /// 마지막 스텝 요청. 다음 멈춤을 받으면 지운다.
    private var pendingStepRequestID: Int32?

    /// 스텝으로 멈춘 뒤 그 요청을 거둔다. 안 거두면 매 줄 멈춘다.
    /// 로드된 클래스에 예약된 브레이크포인트를 건다.
    ///
    /// 실패해도 던지지 않는다 — 이벤트 루프 한가운데다. 던지면 리스너가 끝나고, 그러면
    /// **그 뒤의 모든 멈춤이 사라진다.** 브레이크포인트 하나를 못 건 것보다 훨씬 크다.
    private func placeDeferredBreakpoint(for prepared: JDWPPreparedClass) async {
        guard let deferred = deferredBreakpoints[prepared.requestID],
              deferred.className == prepared.className
        else {
            return
        }
        classIDsBySignature[signature(forClassName: prepared.className)] = prepared.classID
        if let placed = try? await placeBreakpoint(
            classID: prepared.classID, className: prepared.className, line: deferred.line
        ) {
            placedForDeferred[prepared.requestID] = placed
        }
    }

    func clearPendingStepRequest() async {
        guard let requestID = pendingStepRequestID else { return }
        pendingStepRequestID = nil
        var payload: [UInt8] = [JDWPStepRequest.eventKind]
        payload += withUnsafeBytes(of: requestID.bigEndian, Array.init)
        _ = try? await connection.request(
            commandSet: Command.eventRequest, command: Command.eventClear, payload: payload
        )
    }

    private static func depth(for step: DebugStep) -> JDWPStepDepth {
        switch step {
        case .into: return .into
        case .over: return .over
        case .out: return .out
        }
    }

    public func resume() async throws {
        _ = try await connection.request(
            commandSet: Command.virtualMachine, command: Command.vmResume, payload: []
        )
    }

    // MARK: - 스택과 변수

    public func stackFrames(threadID: UInt64) async throws -> [JavaStackFrame] {
        var payload = identifierBytes(threadID, size: sizes.objectID)
        payload += withUnsafeBytes(of: UInt32(0).bigEndian, Array.init)   // start index
        // **length 는 -1 이어야 한다** — "남은 전부" 라는 뜻이다. 넉넉한 수를 주면 되겠거니
        // 하고 64 를 넘겼더니 JVM 이 504(INVALID_LENGTH)로 거절했다. 실제 프레임 수보다 큰
        // 값은 오류이지 상한이 아니다.
        //
        // 이 오류를 THREAD_NOT_SUSPENDED 로 잘못 읽고 한참 헤맬 뻔했다. `SuspendCount` 를
        // 물어 1 이 나온 것이 그 가설을 깼다 — 멈춰 있는데도 거절당했으니 원인은 다른 데
        // 있었다.
        payload += withUnsafeBytes(of: Int32(-1).bigEndian, Array.init)   // length
        let reply = try await connection.request(
            commandSet: Command.threadReference, command: Command.frames, payload: payload
        )

        var reader = JDWPReader(bytes: reply)
        let count = Int(try reader.readInt32())
        var raw: [(frameID: UInt64, classID: UInt64, methodID: UInt64, codeIndex: UInt64)] = []
        for _ in 0..<count {
            let frameID = try reader.readIdentifier(size: sizes.frameID)
            _ = try reader.readByte()   // location typeTag
            let classID = try reader.readIdentifier(size: sizes.referenceTypeID)
            let methodID = try reader.readIdentifier(size: sizes.methodID)
            let codeIndex = try reader.readUInt64()
            raw.append((frameID, classID, methodID, codeIndex))
        }

        // 이름과 줄은 따로 물어야 나온다. 프레임 하나마다 왕복하지 않도록 클래스 단위로 묶는다.
        var frames: [JavaStackFrame] = []
        for entry in raw {
            let className = try await className(ofClass: entry.classID)
            let methodName = try await methods(ofClass: entry.classID)
                .first { $0.id == entry.methodID }?.name ?? "?"
            let table = try? await lineTable(classID: entry.classID, methodID: entry.methodID)
            frames.append(JavaStackFrame(
                frameID: entry.frameID,
                className: className,
                methodName: methodName,
                // 줄을 못 알아내면 0 이 아니라 그대로 0 을 둔다 — 위층이 "줄 모름" 으로 그린다.
                line: table?.line(forCodeIndex: entry.codeIndex) ?? 0,
                classID: entry.classID,
                methodID: entry.methodID
            ))
        }
        return frames
    }

    private var classNamesByID: [UInt64: String] = [:]

    /// `Lcom/example/Probe;` → `com.example.Probe`.
    public func className(ofClass classID: UInt64) async throws -> String {
        if let cached = classNamesByID[classID] { return cached }
        let reply = try await connection.request(
            commandSet: Command.referenceType,
            command: Command.signature,
            payload: identifierBytes(classID, size: sizes.referenceTypeID)
        )
        var reader = JDWPReader(bytes: reply)
        let signature = try reader.readString()
        let name = signature
            .trimmingCharacters(in: CharacterSet(charactersIn: "L;"))
            .replacingOccurrences(of: "/", with: ".")
        classNamesByID[classID] = name
        return name
    }

    /// The locals visible at this frame's current position.
    ///
    /// `VariableTable` 은 메서드의 **모든** 지역 변수를 준다 — 아직 선언 전인 것까지. 각 항목의
    /// 유효 범위(codeIndex, length)를 보고 지금 위치에 살아 있는 것만 남긴다. 안 거르면 아직
    /// 초기화되지 않은 슬롯의 쓰레기 값을 변수 값이라고 보여 준다.
    public func localVariables(frame: JavaStackFrame, threadID: UInt64, codeIndex: UInt64) async throws -> [JavaVariable] {
        var tablePayload = identifierBytes(frame.classID, size: sizes.referenceTypeID)
        tablePayload += identifierBytes(frame.methodID, size: sizes.methodID)
        let tableReply: [UInt8]
        do {
            tableReply = try await connection.request(
                commandSet: Command.method, command: Command.variableTable, payload: tablePayload
            )
        } catch JDWPConnectionError.commandFailed(_, _, let errorCode) where errorCode == 101 {
            // 101 = ABSENT_INFORMATION. `javac -g` 없이 컴파일된 클래스다.
            throw JavaDebugError.noLocalVariableInformation(
                className: frame.className, methodName: frame.methodName
            )
        }

        var reader = JDWPReader(bytes: tableReply)
        _ = try reader.readInt32()   // argCnt
        let count = Int(try reader.readInt32())
        struct Slot { let name: String; let signature: String; let index: Int32 }
        var slots: [Slot] = []
        for _ in 0..<count {
            let start = try reader.readUInt64()
            let name = try reader.readString()
            let signature = try reader.readString()
            let length = try reader.readUInt32()
            let index = try reader.readInt32()
            let isLive = codeIndex >= start && codeIndex < start + UInt64(length)
            if isLive {
                slots.append(Slot(name: name, signature: signature, index: index))
            }
        }
        guard !slots.isEmpty else { return [] }

        var valuesPayload = identifierBytes(threadID, size: sizes.objectID)
        valuesPayload += identifierBytes(frame.frameID, size: sizes.frameID)
        valuesPayload += withUnsafeBytes(of: Int32(slots.count).bigEndian, Array.init)
        for slot in slots {
            valuesPayload += withUnsafeBytes(of: slot.index.bigEndian, Array.init)
            // 태그는 시그니처의 첫 글자다. `Lcom/…;` 는 `L`, `[I` 는 `[`.
            valuesPayload += [UInt8(slot.signature.utf8.first ?? UInt8(ascii: "L"))]
        }

        let valuesReply = try await connection.request(
            commandSet: Command.stackFrame, command: Command.getValues, payload: valuesPayload
        )
        var valuesReader = JDWPReader(bytes: valuesReply)
        let valueCount = Int(try valuesReader.readInt32())
        var variables: [JavaVariable] = []
        for index in 0..<min(valueCount, slots.count) {
            let value = try valuesReader.readTaggedValue(objectIDSize: sizes.objectID)
            variables.append(JavaVariable(
                name: slots[index].name,
                typeSignature: slots[index].signature,
                value: value.displayText,
                objectID: Self.expandableID(of: value)
            ))
        }
        return variables
    }

    // MARK: - 객체 안 들여다보기

    /// What is inside one object.
    ///
    /// 세 갈래다. 문자열은 내용을, 배열은 원소를, 나머지는 필드를 준다. 못 여는 것이면 빈
    /// 배열이다 — **던지지 않는다.** 변수 하나를 못 열었다고 패널 전체가 사라지면 안 된다.
    public func fields(ofObject objectID: UInt64, typeSignature: String) async throws -> [JavaVariable] {
        guard objectID != 0 else { return [] }

        if typeSignature == "Ljava/lang/String;" {
            guard let text = try? await stringValue(ofObject: objectID) else { return [] }
            return [JavaVariable(name: "value", typeSignature: typeSignature, value: "\"\(text)\"")]
        }
        if typeSignature.hasPrefix("[") {
            return (try? await arrayElements(ofArray: objectID, elementSignature: String(typeSignature.dropFirst()))) ?? []
        }
        return (try? await instanceFields(ofObject: objectID)) ?? []
    }

    private func stringValue(ofObject objectID: UInt64) async throws -> String {
        let reply = try await connection.request(
            commandSet: Command.stringReference,
            command: Command.stringValue,
            payload: JDWPObjectFields.stringValuePayload(objectID: objectID, objectIDSize: sizes.objectID)
        )
        var reader = JDWPReader(bytes: reply)
        return try reader.readString()
    }

    private func arrayElements(ofArray arrayID: UInt64, elementSignature: String) async throws -> [JavaVariable] {
        let lengthReply = try await connection.request(
            commandSet: Command.arrayReference,
            command: Command.arrayLength,
            payload: identifierBytes(arrayID, size: sizes.objectID)
        )
        var lengthReader = JDWPReader(bytes: lengthReply)
        let length = try lengthReader.readInt32()
        guard length > 0 else { return [] }

        // 앞의 것만 읽는다. 백만 개짜리 배열을 통째로 가져오면 화면이 멈추고, 사용자가
        // 보려던 것은 대개 앞쪽 몇 개다.
        let shown = min(length, Self.maximumArrayElementsShown)
        let reply = try await connection.request(
            commandSet: Command.arrayReference,
            command: Command.arrayGetValues,
            payload: JDWPObjectFields.arrayValuesPayload(
                arrayID: arrayID, firstIndex: 0, length: shown, objectIDSize: sizes.objectID
            )
        )

        var reader = JDWPReader(bytes: reply)
        // 배열 값은 **한 번만** 태그가 온다 — 원소마다가 아니라 배열 전체에 하나다.
        let tag = Character(UnicodeScalar(try reader.readByte()))
        let count = Int(try reader.readInt32())
        var elements: [JavaVariable] = []
        for index in 0..<count {
            // 객체 배열은 원소마다 태그가 다시 붙는다(`[` 나 `L` 로 시작하는 태그).
            let value = "[L".contains(tag)
                ? try reader.readTaggedValue(objectIDSize: sizes.objectID)
                : try reader.readValue(tag: tag, objectIDSize: sizes.objectID)
            elements.append(JavaVariable(
                name: "[\(index)]",
                typeSignature: elementSignature,
                value: value.displayText,
                objectID: Self.expandableID(of: value)
            ))
        }
        if length > shown {
            elements.append(JavaVariable(
                name: "…", typeSignature: "", value: "\(length - shown)개 더", objectID: nil
            ))
        }
        return elements
    }

    /// 배열에서 한 번에 보여 주는 원소 수.
    static let maximumArrayElementsShown: Int32 = 100

    private func instanceFields(ofObject objectID: UInt64) async throws -> [JavaVariable] {
        // 객체의 **실제 타입**을 묻는다. 선언 타입으로 필드를 물으면 하위 타입의 필드가
        // 통째로 빠진다 — 사용자는 있는 값을 없다고 읽는다.
        let typeReply = try await connection.request(
            commandSet: Command.objectReference,
            command: Command.referenceTypeOfObject,
            payload: identifierBytes(objectID, size: sizes.objectID)
        )
        var typeReader = JDWPReader(bytes: typeReply)
        _ = try typeReader.readByte()   // refTypeTag
        let classID = try typeReader.readIdentifier(size: sizes.referenceTypeID)

        let allFields = try await fieldsIncludingInherited(ofClass: classID)
        // 정적 필드는 인스턴스에 없다. 섞어서 물으면 JVM 이 거절하고 **필드가 하나도 안
        // 보인다** — 하나 때문에 전부를 잃는다.
        let instanceOnly = allFields.filter { !$0.isStatic }
        guard !instanceOnly.isEmpty else { return [] }

        let valuesReply = try await connection.request(
            commandSet: Command.objectReference,
            command: Command.objectGetValues,
            payload: JDWPObjectFields.getValuesPayload(
                objectID: objectID,
                fieldIDs: instanceOnly.map(\.id),
                objectIDSize: sizes.objectID,
                fieldIDSize: sizes.fieldID
            )
        )
        var reader = JDWPReader(bytes: valuesReply)
        let count = Int(try reader.readInt32())
        var variables: [JavaVariable] = []
        for index in 0..<min(count, instanceOnly.count) {
            let value = try reader.readTaggedValue(objectIDSize: sizes.objectID)
            variables.append(JavaVariable(
                name: instanceOnly[index].name,
                typeSignature: instanceOnly[index].signature,
                value: value.displayText,
                objectID: Self.expandableID(of: value)
            ))
        }
        return variables
    }

    /// Fields declared here **and in every superclass**.
    ///
    /// `ReferenceType.Fields` 는 그 클래스가 **선언한** 필드만 준다. 상속받은 것은 안 준다.
    /// 실측으로 걸렸다: `IllegalStateException` 을 열었더니 필드가 0개였는데, 예외 메시지는
    /// `Throwable.detailMessage` 라 한 단계 위에 있었다. 사용자에게는 "예외를 열었는데
    /// 아무것도 없다" 로 보이고, 그건 우리가 못 읽은 것과 구별되지 않는다.
    ///
    /// 자기 것부터 올라간다 — 하위 클래스가 같은 이름으로 가린 필드가 있으면 가까운 쪽이
    /// 먼저 보이는 편이 자연스럽다.
    private func fieldsIncludingInherited(ofClass classID: UInt64) async throws -> [JDWPField] {
        var fields: [JDWPField] = []
        var seenIDs: Set<UInt64> = []
        var current: UInt64? = classID
        var depth = 0

        while let typeID = current, depth < Self.maximumSuperclassDepth {
            depth += 1
            let reply = try await connection.request(
                commandSet: Command.referenceType,
                command: Command.fields,
                payload: identifierBytes(typeID, size: sizes.referenceTypeID)
            )
            for field in try JDWPField.parseList(payload: reply, fieldIDSize: sizes.fieldID)
            where seenIDs.insert(field.id).inserted {
                fields.append(field)
            }
            current = try? await superclass(ofClass: typeID)
        }
        return fields
    }

    /// `Object` 까지 올라가면 멈춘다. 상한을 두는 것은 깊이 때문이 아니라, 응답이 이상할 때
    /// 무한 루프에 빠지지 않기 위해서다 — 이벤트 루프 안에서 그러면 디버거가 통째로 멈춘다.
    static let maximumSuperclassDepth = 32

    private func superclass(ofClass classID: UInt64) async throws -> UInt64? {
        let reply = try await connection.request(
            commandSet: Command.classType,
            command: Command.superclass,
            payload: identifierBytes(classID, size: sizes.referenceTypeID)
        )
        var reader = JDWPReader(bytes: reply)
        let superclassID = try reader.readIdentifier(size: sizes.referenceTypeID)
        // 0 은 `Object` 위, 즉 없다는 뜻이다.
        return superclassID == 0 ? nil : superclassID
    }

    /// 열 수 있는 값이면 그 id. `null`(id 0)과 기본형은 nil 이다.
    static func expandableID(of value: JDWPValue) -> UInt64? {
        guard case .object(_, let id) = value, id != 0 else { return nil }
        return id
    }

    // MARK: - 도구

    private func identifierBytes(_ value: UInt64, size: Int) -> [UInt8] {
        let all = withUnsafeBytes(of: value.bigEndian, Array.init)
        return Array(all.suffix(size))
    }
}
