public enum JavaDebugError: Error, Sendable {
    case classNotLoaded(String)
    case noExecutableCodeOnLine(className: String, line: Int)
    case notSuspended
    /// 클래스가 `javac -g` 없이 컴파일돼 지역 변수 이름표가 없다.
    ///
    /// 흔한 일이고 우리 잘못이 아니지만, **빈 목록으로 넘기면 안 된다** — 사용자는 "이 자리에
    /// 지역 변수가 없다" 로 읽는다. 없는 것과 알 수 없는 것은 다른 사건이다.
    case noLocalVariableInformation(className: String, methodName: String)
}

/// One stack frame, as the debugger shows it.
public struct JavaStackFrame: Sendable, Hashable, Identifiable {
    public let frameID: UInt64
    public let className: String
    public let methodName: String
    /// 1-based. **0 은 "줄을 알 수 없다"** 는 뜻이지 첫 줄이 아니다 — 네이티브 프레임이나
    /// 디버그 정보 없이 컴파일된 클래스에서 그렇게 된다. 화면은 이 둘을 다르게 그려야 한다.
    public let line: Int
    public let classID: UInt64
    public let methodID: UInt64

    public var id: UInt64 { frameID }

    public init(
        frameID: UInt64, className: String, methodName: String,
        line: Int, classID: UInt64, methodID: UInt64
    ) {
        self.frameID = frameID
        self.className = className
        self.methodName = methodName
        self.line = line
        self.classID = classID
        self.methodID = methodID
    }
}

public struct JavaVariable: Sendable, Hashable, Identifiable {
    public let name: String
    /// JVM 시그니처 그대로 (`I`, `Ljava/lang/String;`). 화면용 축약은 표현 계층의 몫이다.
    public let typeSignature: String
    public let value: String
    /// 안을 열어 볼 수 있는 객체면 그 id. `null` 과 기본형은 nil 이다.
    ///
    /// **펼칠 수 있는지와 자식이 있는지는 다르다.** 필드가 하나도 없는 객체도 열 수는 있고,
    /// 그때 화면은 "필드 없음" 이라고 말해야 한다 — 삼각형이 아예 없으면 사용자는 이 값이
    /// 객체가 아니라고 읽는다.
    public let objectID: UInt64?

    public var id: String { name }
    public var isExpandable: Bool { objectID != nil }

    public init(name: String, typeSignature: String, value: String, objectID: UInt64? = nil) {
        self.name = name
        self.typeSignature = typeSignature
        self.value = value
        self.objectID = objectID
    }
}

/// Where the debuggee stopped.
public struct JavaStopEvent: Sendable, Hashable {
    public let threadID: UInt64
    public let requestID: Int32
    public let classID: UInt64
    public let methodID: UInt64
    public let codeIndex: UInt64

    public init(
        threadID: UInt64, requestID: Int32,
        classID: UInt64, methodID: UInt64, codeIndex: UInt64
    ) {
        self.threadID = threadID
        self.requestID = requestID
        self.classID = classID
        self.methodID = methodID
        self.codeIndex = codeIndex
    }
}

/// What the application needs from a debugger, so the shell can be built and tested without
/// starting a JVM.
///
/// 계약을 여기 두는 이유는 `ProjectSession` 과 같다 — 화면 상태 기계를 검증하는 데 실제
/// 디버기가 필요하면 아무도 그 테스트를 돌리지 않는다.
/// 한 걸음의 깊이. 화면 낱말과 JDWP 숫자를 잇는다.
public enum DebugStep: Sendable, Hashable, CaseIterable {
    /// 다음 줄로 — 함수 호출은 통째로 지나간다.
    case over
    /// 호출 안으로.
    case into
    /// 지금 함수를 끝내고 부른 자리로.
    case out
}

public protocol DebugSession: Sendable {
    func setBreakpoint(className: String, line: Int) async throws -> Int32
    func clearBreakpoint(requestID: Int32) async throws
    /// Blocks until the debuggee stops.
    func waitForBreakpoint() async throws -> JavaStopEvent
    func stackFrames(threadID: UInt64) async throws -> [JavaStackFrame]
    func localVariables(frame: JavaStackFrame, threadID: UInt64, codeIndex: UInt64) async throws -> [JavaVariable]
    func resume() async throws
    /// 한 걸음 나아가고 다시 멈춘다. 멈춤은 `waitForBreakpoint` 로 도착한다 — 브레이크포인트와
    /// 같은 통로다. 화면이 둘을 다르게 다루면 "왜 여기서 멈췄지" 가 두 가지 답을 갖게 된다.
    func step(_ step: DebugStep, threadID: UInt64) async throws
    /// Reads the fields inside one object — what the user sees when they open a variable.
    ///
    /// 배열이면 원소를, 문자열이면 내용을 준다. 못 여는 것이면 빈 배열이다 — **던지지
    /// 않는다.** 변수 하나를 못 열었다고 패널 전체가 사라지면 안 된다.
    func fields(ofObject objectID: UInt64, typeSignature: String) async throws -> [JavaVariable]
    func close() async
}


/// How the shell obtains a debug session. The application supplies the real one; a test supplies
/// a fake. 모델이 Core 를 직접 부르면 화면 상태를 재는 데 JVM 이 필요해진다.
public typealias DebugSessionFactory = @Sendable (String, UInt16) async throws -> any DebugSession
