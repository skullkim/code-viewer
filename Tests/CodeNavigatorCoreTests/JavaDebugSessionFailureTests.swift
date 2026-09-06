import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// 디버거가 사용자를 가장 크게 오도하는 순간은 실패할 때다. "변수가 없다" 와 "변수 이름을
/// 알 수 없다" 는 화면에서 똑같이 빈 목록이지만 사용자가 해야 할 일이 다르다.
@Suite("Java 디버그 세션 — 실패를 구분한다")
struct JavaDebugSessionFailureTests {

    /// 바이트가 떨어지면 던지지 않고 기다린다 — 실제 소켓이 그렇다.
    private actor ScriptedTransport: JDWPTransport {
        private var incoming: [UInt8]
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var isClosed = false
        init(incoming: [UInt8]) { self.incoming = incoming }
        func send(_ bytes: [UInt8]) async throws {}
        func receive(count: Int) async throws -> [UInt8] {
            while incoming.count < count {
                if isClosed { throw JDWPConnectionError.connectionClosed }
                await withCheckedContinuation { waiters.append($0) }
            }
            let head = Array(incoming.prefix(count))
            incoming.removeFirst(count)
            return head
        }
        func close() async {
            isClosed = true
            let pending = waiters; waiters = []
            pending.forEach { $0.resume() }
        }
    }

    /// 리더를 켠 세션. 안 켜면 요청이 답을 못 받는데, 이제는 그게 무한 대기가 아니라
    /// `readerNotStarted` 오류다.
    private func session(_ transport: ScriptedTransport) async -> JavaDebugSession {
        let connection = JDWPConnection(transport: transport)
        await connection.startReading()
        return JavaDebugSession(connection: connection, sizes: sizes)
    }

    private func reply(id: UInt32, payload: [UInt8], errorCode: UInt16) -> [UInt8] {
        let length = UInt32(JDWPPacket.headerLength + payload.count)
        return withUnsafeBytes(of: length.bigEndian, Array.init)
            + withUnsafeBytes(of: id.bigEndian, Array.init)
            + [0x80, UInt8(errorCode >> 8), UInt8(errorCode & 0xFF)]
            + payload
    }

    private var sizes: JDWPIdentifierSizes {
        JDWPIdentifierSizes(fieldID: 8, methodID: 8, objectID: 8, referenceTypeID: 8, frameID: 8)
    }

    private var frame: JavaStackFrame {
        JavaStackFrame(
            frameID: 1, className: "Probe", methodName: "step",
            line: 6, classID: 2, methodID: 3
        )
    }

    /// 101 = ABSENT_INFORMATION. `javac -g` 없이 컴파일된 클래스에서 실제로 나온 코드다.
    @Test("변수 이름표가 없으면 빈 목록이 아니라 그렇다고 말한다")
    func reportsMissingDebugInformation() async throws {
        let session = await session(ScriptedTransport(incoming: reply(id: 1, payload: [], errorCode: 101)))

        await #expect(throws: JavaDebugError.self) {
            _ = try await session.localVariables(frame: frame, threadID: 1, codeIndex: 4)
        }
    }

    /// 다른 오류까지 "정보 없음" 으로 뭉뚱그리면 진짜 고장이 숨는다.
    @Test("다른 오류는 그대로 전달한다 — 전부 '정보 없음' 으로 뭉뚱그리지 않는다")
    func doesNotSwallowOtherErrors() async throws {
        let session = await session(ScriptedTransport(incoming: reply(id: 1, payload: [], errorCode: 13)))

        await #expect(throws: JDWPConnectionError.self) {
            _ = try await session.localVariables(frame: frame, threadID: 1, codeIndex: 4)
        }
    }

    /// `ClassesBySignature` 의 0건은 "그런 클래스가 없다" 가 아니라 "아직 로드 전" 일 수 있다.
    /// 0건을 없음으로 읽으면 브레이크포인트가 조용히 아무 데도 안 걸린다.
    @Test("로드 전 클래스는 nil 이다 — 없다고 단정하지 않는다")
    func treatsAnUnloadedClassAsUnknown() async throws {
        let empty = withUnsafeBytes(of: UInt32(0).bigEndian, Array.init)
        let session = await session(ScriptedTransport(incoming: reply(id: 1, payload: empty, errorCode: 0)))
        #expect(try await session.loadedClassID(named: "com.example.NotYet") == nil)
    }
}
