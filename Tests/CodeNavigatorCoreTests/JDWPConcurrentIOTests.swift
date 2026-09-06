import Testing
import Foundation
@testable import CodeNavigatorCore

/// 라이브에서 잡은 결함. 디버거가 이벤트를 기다리는 동안 **명령이 전송조차 되지 않았다.**
///
/// 원인 둘이 겹쳐 있었다. 소켓 전송이 읽기와 쓰기에 같은 직렬 큐를 써서, 이벤트를 기다리며
/// 막혀 있는 읽기 뒤로 모든 쓰기가 줄을 섰다. 그리고 리스너와 요청이 각자 `receive` 를 불러
/// 서로의 바이트를 가져갔다.
///
/// 증상은 "브레이크포인트를 걸었는데 아무 일도 안 일어남" 이었다 — 오류도 없고, 로그도 없고,
/// 화면은 연결됨이라고 적혀 있었다. 이 스위트는 그 조합을 다시 만들 수 없게 한다.
@Suite("JDWP 동시 입출력 — 기다리는 동안에도 명령이 나간다")
struct JDWPConcurrentIOTests {

    /// 읽기가 막혀 있어도 쓰기는 통과해야 한다. 실제 소켓의 성질을 흉내 낸다 — 전이중이다.
    private actor DuplexTransport: JDWPTransport {
        private var incoming: [UInt8] = []
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var sent: [UInt8] = []

        func send(_ bytes: [UInt8]) async throws {
            sent += bytes
        }

        func receive(count: Int) async throws -> [UInt8] {
            while incoming.count < count {
                await withCheckedContinuation { waiters.append($0) }
            }
            let head = Array(incoming.prefix(count))
            incoming.removeFirst(count)
            return head
        }

        /// 상대가 바이트를 보내 온 것처럼 만든다.
        func deliver(_ bytes: [UInt8]) {
            incoming += bytes
            let pending = waiters
            waiters = []
            pending.forEach { $0.resume() }
        }

        func close() async {}
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

    /// 이게 라이브에서 죽은 그 자리다. 이벤트를 기다리는 중에 명령을 보내면, 그 명령은
    /// **나가야 하고** 답도 받아야 한다.
    @Test("이벤트를 기다리는 동안에도 명령이 나가고 답을 받는다")
    func sendsCommandsWhileWaitingForAnEvent() async throws {
        let transport = DuplexTransport()
        let connection = JDWPConnection(transport: transport)
        await connection.startReading()

        // 아무도 이벤트를 보내지 않은 채로 리스너를 띄운다.
        let listener = Task { try await connection.nextEvent() }

        // 그 사이에 명령을 보낸다. 예전 구조에서는 여기서 영원히 멈췄다.
        async let replied = connection.request(commandSet: 1, command: 7, payload: [])
        // 명령이 실제로 소켓에 나갔는지 확인한 뒤에 답을 준다.
        var attempts = 0
        while await transport.sent.isEmpty, attempts < 200 {
            try await Task.sleep(nanoseconds: 5_000_000)
            attempts += 1
        }
        #expect(await !transport.sent.isEmpty, "이벤트 대기 중에 명령이 전송되지 않았다")

        await transport.deliver(reply(id: 1, payload: [0xAB]))
        #expect(try await replied == [0xAB])

        await transport.deliver(event(payload: [0x09]))
        #expect(try await listener.value.payload == [0x09])
    }

    @Test("여러 명령이 동시에 나가도 각자 자기 답을 받는다")
    func correlatesConcurrentRequests() async throws {
        let transport = DuplexTransport()
        let connection = JDWPConnection(transport: transport)
        await connection.startReading()

        async let first = connection.request(commandSet: 1, command: 1, payload: [])
        async let second = connection.request(commandSet: 1, command: 7, payload: [])

        var attempts = 0
        while await transport.sent.count < 2 * JDWPPacket.headerLength, attempts < 200 {
            try await Task.sleep(nanoseconds: 5_000_000)
            attempts += 1
        }

        // 답을 **거꾸로** 준다. 순서로 짝지으면 여기서 뒤바뀐다.
        await transport.deliver(reply(id: 2, payload: [0x22]))
        await transport.deliver(reply(id: 1, payload: [0x11]))

        #expect(try await first == [0x11])
        #expect(try await second == [0x22])
    }

    @Test("연결이 끊기면 기다리던 쪽이 전부 깨어난다 — 조용히 매달려 있지 않는다")
    func wakesEveryWaiterWhenTheConnectionDies() async throws {
        let transport = DuplexTransport()
        let connection = JDWPConnection(transport: transport)
        await connection.startReading()

        let request = Task { try await connection.request(commandSet: 1, command: 7, payload: []) }
        var attempts = 0
        while await transport.sent.isEmpty, attempts < 200 {
            try await Task.sleep(nanoseconds: 5_000_000)
            attempts += 1
        }

        await connection.failAllWaitersForTesting(JDWPConnectionError.connectionClosed)
        await #expect(throws: (any Error).self) { _ = try await request.value }
    }
}
