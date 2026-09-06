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
    static let methods: UInt8 = 5

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

enum JavaDebugError: Error, Sendable {
    case classNotLoaded(String)
    case noExecutableCodeOnLine(className: String, line: Int)
    case notSuspended
    /// 클래스가 `javac -g` 없이 컴파일돼 지역 변수 이름표가 없다.
    ///
    /// 흔한 일이고 우리 잘못이 아니지만, **빈 목록으로 넘기면 안 된다** — 사용자는 "이 자리에
    /// 지역 변수가 없다" 로 읽는다. 없는 것과 알 수 없는 것은 다른 사건이다.
    case noLocalVariableInformation(className: String, methodName: String)
}

/// One stack frame as the debugger shows it.
struct JavaStackFrame: Sendable, Hashable {
    let frameID: UInt64
    let className: String
    let methodName: String
    let line: Int
    let classID: UInt64
    let methodID: UInt64
}

struct JavaVariable: Sendable, Hashable {
    let name: String
    let typeSignature: String
    let value: String
}

/// Where the debuggee stopped.
struct JavaStopEvent: Sendable, Hashable {
    let threadID: UInt64
    let requestID: Int32
    let classID: UInt64
    let methodID: UInt64
    let codeIndex: UInt64
}

/// IntelliJ 급 Java 디버깅의 1차 범위 — 붙기, 걸기, 보기, 풀기.
///
/// 언어 서버를 쓰지 않는다. `java-debug` 경로는 Eclipse JDT(수백 MB)를 끌고 오고, 그러면
/// "작고 네이티브" 라는 이 앱의 유일한 정당성이 사라진다. JVM 이 이미 말하는 표준 프로토콜에
/// 직접 붙는 편이 작고, 그 대가로 프레이밍을 우리가 책임진다.
actor JavaDebugSession {
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
    static func attach(host: String, port: UInt16) async throws -> JavaDebugSession {
        let transport = try JDWPSocketTransport.connect(host: host, port: port)
        let connection = JDWPConnection(transport: transport)
        try await connection.handshake()
        // ID 폭을 먼저 읽는다. 이 값 없이 파싱한 것은 전부 못 믿는다.
        let sizes = try await connection.readIdentifierSizes()
        return JavaDebugSession(connection: connection, sizes: sizes)
    }

    func close() async {
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
    func loadedClassID(named className: String) async throws -> UInt64? {
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
    func requestClassPrepareNotification(forClassName className: String) async throws -> Int32 {
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
    func setBreakpoint(className: String, line: Int) async throws -> Int32 {
        guard let classID = try await loadedClassID(named: className) else {
            throw JavaDebugError.classNotLoaded(className)
        }

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

    func clearBreakpoint(requestID: Int32) async throws {
        var payload: [UInt8] = [EventKind.breakpoint]
        payload += withUnsafeBytes(of: requestID.bigEndian, Array.init)
        _ = try await connection.request(
            commandSet: Command.eventRequest, command: Command.eventClear, payload: payload
        )
    }

    // MARK: - 멈춤과 재개

    /// Waits until the debuggee stops at a breakpoint.
    func waitForBreakpoint() async throws -> JavaStopEvent {
        while true {
            let event = try await connection.nextEvent()
            guard let stop = try parseBreakpoint(event) else { continue }
            return stop
        }
    }

    /// `Event.Composite` (64, 100) 하나에 이벤트가 여러 개 들어올 수 있다. 첫 개만 읽고
    /// 나머지를 버리면, 같은 순간에 걸린 다른 브레이크포인트가 소리 없이 사라진다.
    private func parseBreakpoint(_ event: JDWPEvent) throws -> JavaStopEvent? {
        guard event.commandSet == 64, event.command == 100 else { return nil }
        var reader = JDWPReader(bytes: event.payload)
        _ = try reader.readByte()   // suspend policy
        let count = Int(try reader.readInt32())
        for _ in 0..<count {
            let kind = try reader.readByte()
            let requestID = try reader.readInt32()
            guard kind == EventKind.breakpoint else {
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
                classID: classID, methodID: methodID, codeIndex: codeIndex
            )
        }
        return nil
    }

    /// 진단용 — 멈췄다고 믿는 스레드가 실제로 몇 겹 멈춰 있는지.
    func suspendCount(threadID: UInt64) async throws -> Int32 {
        let reply = try await connection.request(
            commandSet: Command.threadReference,
            command: Command.suspendCount,
            payload: identifierBytes(threadID, size: sizes.objectID)
        )
        var reader = JDWPReader(bytes: reply)
        return try reader.readInt32()
    }

    func resume() async throws {
        _ = try await connection.request(
            commandSet: Command.virtualMachine, command: Command.vmResume, payload: []
        )
    }

    // MARK: - 스택과 변수

    func stackFrames(threadID: UInt64) async throws -> [JavaStackFrame] {
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
    func className(ofClass classID: UInt64) async throws -> String {
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
    func localVariables(frame: JavaStackFrame, threadID: UInt64, codeIndex: UInt64) async throws -> [JavaVariable] {
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
                value: value.displayText
            ))
        }
        return variables
    }

    // MARK: - 도구

    private func identifierBytes(_ value: UInt64, size: Int) -> [UInt8] {
        let all = withUnsafeBytes(of: value.bigEndian, Array.init)
        return Array(all.suffix(size))
    }
}
