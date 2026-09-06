import Testing
import Foundation
@testable import CodeNavigatorCore

/// 연결 계층이 답해야 하는 것은 하나다 — **내가 보낸 명령의 답이 어느 것인가.**
///
/// JVM 은 응답과 이벤트를 같은 소켓으로 섞어 보낸다. 브레이크포인트가 걸리는 순간이 곧
/// 이벤트가 도착하는 순간이고, 그때 우리는 보통 다른 명령의 답을 기다리고 있다. 순서로
/// 짝지으면 그 자리에서 어긋나고, 어긋난 뒤에는 전부 그럴듯한 쓰레기가 된다.
@Suite("JDWP 연결 — 응답과 이벤트를 가른다")
struct JDWPConnectionTests {

    /// 대본대로 답하는 가짜 소켓. JVM 없이 프레이밍과 짝짓기를 재기 위한 것이다.
    /// 대본대로 답하는 가짜 소켓.
    ///
    /// 바이트가 떨어지면 **던지지 않고 기다린다** — 실제 소켓이 그렇다. 던지게 두었더니
    /// 리더가 대본을 다 읽자마자 연결 실패로 판정하고, 아직 등록 중이던 요청까지 깨웠다.
    /// 그건 전송의 성질이 아니라 대본이 끝난 것뿐이다.
    private actor ScriptedTransport: JDWPTransport {
        private var incoming: [UInt8]
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var sent: [UInt8] = []
        private(set) var isClosed = false

        init(incoming: [UInt8]) { self.incoming = incoming }

        func send(_ bytes: [UInt8]) async throws { sent += bytes }

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
            let pending = waiters
            waiters = []
            pending.forEach { $0.resume() }
        }
    }

    private func reply(id: UInt32, payload: [UInt8], errorCode: UInt16 = 0) -> [UInt8] {
        let length = UInt32(JDWPPacket.headerLength + payload.count)
        return withUnsafeBytes(of: length.bigEndian, Array.init)
            + withUnsafeBytes(of: id.bigEndian, Array.init)
            + [0x80, UInt8(errorCode >> 8), UInt8(errorCode & 0xFF)]
            + payload
    }

    private func event(payload: [UInt8]) -> [UInt8] {
        let length = UInt32(JDWPPacket.headerLength + payload.count)
        return withUnsafeBytes(of: length.bigEndian, Array.init)
            + withUnsafeBytes(of: UInt32(0).bigEndian, Array.init)
            + [0, 64, 100]
            + payload
    }

    @Test("핸드셰이크를 주고받는다")
    func performsTheHandshake() async throws {
        let transport = ScriptedTransport(incoming: Array(JDWPPacket.handshake.utf8))
        let connection = JDWPConnection(transport: transport)
        try await connection.handshake()
        #expect(await transport.sent == Array(JDWPPacket.handshake.utf8))
    }

    @Test("상대가 다른 인사를 보내면 실패다 — 디버그 포트가 아니었다는 뜻이다")
    func rejectsAWrongHandshake() async throws {
        let transport = ScriptedTransport(incoming: Array("NOT-JDWP-HELLO".utf8))
        let connection = JDWPConnection(transport: transport)
        await #expect(throws: (any Error).self) { try await connection.handshake() }
    }

    private func reading(_ transport: ScriptedTransport) async -> JDWPConnection {
        let connection = JDWPConnection(transport: transport)
        await connection.startReading()
        return connection
    }

    @Test("응답을 id 로 짝짓는다")
    func matchesRepliesByIdentifier() async throws {
        let connection = await reading(ScriptedTransport(incoming: reply(id: 1, payload: [0xAA])))
        #expect(try await connection.request(commandSet: 1, command: 7, payload: []) == [0xAA])
    }

    /// 이게 이 계층의 존재 이유다. 답을 기다리는 동안 도착한 이벤트를 답으로 읽으면
    /// 브레이크포인트가 걸릴 때마다 그 다음 명령이 전부 어긋난다.
    @Test("답을 기다리는 도중 도착한 이벤트를 답으로 착각하지 않는다")
    func doesNotMistakeAnEventForAReply() async throws {
        let connection = await reading(
            ScriptedTransport(incoming: event(payload: [0x01]) + reply(id: 1, payload: [0xBB]))
        )
        #expect(try await connection.request(commandSet: 1, command: 7, payload: []) == [0xBB])
    }

    @Test("가로챈 이벤트는 버리지 않고 모아 둔다 — 그게 브레이크포인트가 걸렸다는 소식이다")
    func keepsTheEventsItStepsOver() async throws {
        let connection = await reading(
            ScriptedTransport(incoming: event(payload: [0x07]) + reply(id: 1, payload: []))
        )
        _ = try await connection.request(commandSet: 1, command: 7, payload: [])
        #expect(await connection.drainEvents().map(\.payload) == [[0x07]])
    }

    /// 오류는 헤더에 있고 페이로드는 비어 있다. 코드를 안 보면 "성공했는데 답이 없다"로 읽는다.
    @Test("오류 코드가 붙은 응답은 던진다 — 빈 페이로드를 성공으로 읽지 않는다")
    func throwsOnAnErrorReply() async throws {
        let connection = await reading(ScriptedTransport(incoming: reply(id: 1, payload: [], errorCode: 13)))
        await #expect(throws: (any Error).self) {
            try await connection.request(commandSet: 1, command: 7, payload: [])
        }
    }

    @Test("id 는 명령마다 올라간다 — 두 명령이 같은 번호를 쓰면 짝짓기가 무너진다")
    func usesAFreshIdentifierPerCommand() async throws {
        let transport = ScriptedTransport(incoming: reply(id: 1, payload: []) + reply(id: 2, payload: []))
        let connection = await reading(transport)
        _ = try await connection.request(commandSet: 1, command: 7, payload: [])
        _ = try await connection.request(commandSet: 1, command: 1, payload: [])

        let sent = await transport.sent
        #expect(Array(sent[4..<8]) == [0, 0, 0, 1])
        #expect(Array(sent[(JDWPPacket.headerLength + 4)..<(JDWPPacket.headerLength + 8)]) == [0, 0, 0, 2])
    }

    @Test("연결이 끊기면 기다리던 명령이 깨어난다 — 조용히 매달려 있지 않는다")
    func reportsAClosedConnection() async throws {
        let transport = ScriptedTransport(incoming: [])
        let connection = await reading(transport)
        let request = Task { try await connection.request(commandSet: 1, command: 7, payload: []) }
        await transport.close()
        await #expect(throws: (any Error).self) { _ = try await request.value }
    }

    @Test("IDSizes 응답을 읽는다 — 이후 모든 ID 읽기가 이 값에 달려 있다")
    func readsTheIdentifierSizes() async throws {
        // fieldID, methodID, objectID, referenceTypeID, frameID 순서로 각 4바이트.
        var payload: [UInt8] = []
        for size in [UInt32(8), 8, 8, 8, 8] {
            payload += withUnsafeBytes(of: size.bigEndian, Array.init)
        }
        let connection = await reading(ScriptedTransport(incoming: reply(id: 1, payload: payload)))
        let sizes = try await connection.readIdentifierSizes()
        #expect(sizes.methodID == 8)
        #expect(sizes.referenceTypeID == 8)
        #expect(sizes.frameID == 8)
    }
}
