import Foundation

/// Speaks JDWP over a transport: handshake, commands, and the events that arrive in between.
///
/// **하나의 리더가 소켓을 읽고, 읽은 것을 나눠 준다.** 이 구조가 아니면 안 된다는 것을 라이브에서
/// 배웠다. 처음에는 `request` 가 직접 답을 읽고 이벤트는 건너뛰는 방식이었는데, 디버거가
/// 이벤트를 기다리기 시작하자 **명령이 전송조차 되지 않았다.** 원인 둘이 겹쳐 있었다:
///
/// 1. 소켓 전송이 읽기와 쓰기에 같은 직렬 큐를 써서, 이벤트를 기다리며 막힌 읽기 뒤로 모든
///    쓰기가 줄을 섰다.
/// 2. 리스너와 요청이 각자 `receive` 를 불러 서로의 바이트를 가져갔다.
///
/// 증상은 "브레이크포인트를 걸었는데 아무 일도 안 일어남" 이었다 — 오류도, 로그도 없고,
/// 화면에는 연결됨이라고 적혀 있었다. 조용한 실패의 전형이다.
///
/// 그래서 지금은 리더가 하나뿐이고, 응답은 id 로 기다리는 쪽에 배달하고, 이벤트는 줄을 세운다.
/// 명령은 보내고 나서 자기 id 로 기다리기만 하므로 서로를 막지 않는다.
actor JDWPConnection {
    private let transport: any JDWPTransport
    private var nextIdentifier: UInt32 = 1

    /// 답을 기다리는 명령들. 키는 패킷 id — **순서가 아니다.** JVM 은 보낸 순서대로 답하지
    /// 않고, 순서로 짝지으면 그 자리에서 어긋난 뒤로 모든 값이 그럴듯한 쓰레기가 된다.
    private var pendingReplies: [UInt32: CheckedContinuation<[UInt8], any Error>] = [:]
    /// 등록보다 **먼저 도착한** 답. 실제로 겪은 경쟁이다 — `request` 가 `await send` 에서
    /// 액터를 놓는 사이에 리더가 답을 배달할 수 있고, 그때 기다리는 이가 아직 없다. 그걸
    /// 버리면 그 명령은 영원히 안 끝난다. 오류도 안 나고, 화면은 "처리 중" 에서 멈춘다.
    private var earlyReplies: [UInt32: Result<[UInt8], any Error>] = [:]
    private var queuedEvents: [JDWPEvent] = []
    private var eventWaiters: [CheckedContinuation<JDWPEvent, any Error>] = []

    private var readerTask: Task<Void, Never>?
    /// 연결이 끝난 이유. 끝난 뒤에 들어온 요청도 여기서 즉시 실패한다 — 조용히 매달려 있게
    /// 두면 화면이 "명령 처리 중" 에서 영원히 멈춘다.
    private var failure: (any Error)?

    init(transport: any JDWPTransport) {
        self.transport = transport
    }

    func handshake() async throws {
        let greeting = Array(JDWPPacket.handshake.utf8)
        try await transport.send(greeting)
        let received = try await transport.receive(count: greeting.count)
        guard received == greeting else {
            throw JDWPConnectionError.notADebugPort(
                received: String(decoding: received, as: UTF8.self)
            )
        }
    }

    /// Starts the single reader. Must be called after the handshake and before any command:
    /// the handshake is the one exchange that is not framed as a packet.
    func startReading() {
        guard readerTask == nil else { return }
        readerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let packet = try await self.readOnePacket()
                    await self.deliver(packet)
                } catch {
                    await self.failAllWaiters(error)
                    return
                }
            }
        }
    }

    private func readOnePacket() async throws -> (header: JDWPPacketHeader, body: [UInt8]) {
        let headerBytes = try await transport.receive(count: JDWPPacket.headerLength)
        guard let header = JDWPPacketHeader(bytes: headerBytes) else {
            throw JDWPConnectionError.malformedPacket
        }
        let body = header.payloadLength > 0
            ? try await transport.receive(count: header.payloadLength)
            : []
        return (header, body)
    }

    private func deliver(_ packet: (header: JDWPPacketHeader, body: [UInt8])) {
        let header = packet.header
        guard header.isReply else {
            let event = JDWPEvent(
                commandSet: header.commandSet, command: header.command, payload: packet.body
            )
            if eventWaiters.isEmpty {
                // 아무도 안 기다려도 **버리지 않는다.** 이게 브레이크포인트가 걸렸다는
                // 통지이고, 버리면 멈춘 사실 자체가 사라진다.
                queuedEvents.append(event)
            } else {
                eventWaiters.removeFirst().resume(returning: event)
            }
            return
        }

        let outcome: Result<[UInt8], any Error> = header.errorCode != 0
            ? .failure(JDWPConnectionError.commandFailed(
                commandSet: header.commandSet, command: header.command, errorCode: header.errorCode
            ))
            : .success(packet.body)

        if let waiting = pendingReplies.removeValue(forKey: header.id) {
            waiting.resume(with: outcome)
        } else {
            // 아직 등록 전이다 — 보내는 쪽이 `await send` 에서 돌아오는 중이다. 여기서
            // 버리면 그 명령은 영원히 안 끝난다.
            earlyReplies[header.id] = outcome
        }
    }

    private func failAllWaiters(_ error: any Error) {
        failure = error
        earlyReplies.removeAll()
        let replies = pendingReplies
        pendingReplies = [:]
        replies.values.forEach { $0.resume(throwing: error) }

        let events = eventWaiters
        eventWaiters = []
        events.forEach { $0.resume(throwing: error) }
    }

    /// 테스트가 연결 종료를 재현하기 위한 것. 실제 종료는 리더가 스스로 알아챈다.
    func failAllWaitersForTesting(_ error: any Error) {
        failAllWaiters(error)
    }

    /// Sends one command and waits for the reply with its identifier.
    func request(commandSet: UInt8, command: UInt8, payload: [UInt8]) async throws -> [UInt8] {
        if let failure { throw failure }
        // 리더가 없으면 답을 받아 줄 사람이 없다. 그대로 두면 **조용히 영원히 매달린다** —
        // 오류도 로그도 없이. 매달리는 것보다 말하는 편이 언제나 낫다.
        guard readerTask != nil else { throw JDWPConnectionError.readerNotStarted }

        let identifier = nextIdentifier
        nextIdentifier += 1

        let packet = JDWPPacket.command(
            id: identifier, commandSet: commandSet, command: command, payload: payload
        )
        try await transport.send(packet.encoded())

        return try await withCheckedThrowingContinuation { continuation in
            // 답이 등록보다 먼저 왔을 수 있다. `await send` 가 액터를 놓는 사이에 리더가
            // 배달할 시간이 있고, 실제로 그 창에서 답을 잃었다.
            if let early = earlyReplies.removeValue(forKey: identifier) {
                continuation.resume(with: early)
            } else {
                pendingReplies[identifier] = continuation
            }
        }
    }

    /// Waits for the next event, or hands over one that already arrived.
    func nextEvent() async throws -> JDWPEvent {
        if !queuedEvents.isEmpty {
            return queuedEvents.removeFirst()
        }
        if let failure { throw failure }
        return try await withCheckedThrowingContinuation { continuation in
            eventWaiters.append(continuation)
        }
    }

    /// Hands over the events seen so far and forgets them.
    func drainEvents() -> [JDWPEvent] {
        defer { queuedEvents.removeAll() }
        return queuedEvents
    }

    /// `VirtualMachine.IDSizes` (1, 7). Must be read before anything that parses an identifier.
    func readIdentifierSizes() async throws -> JDWPIdentifierSizes {
        let payload = try await request(commandSet: 1, command: 7, payload: [])
        var reader = JDWPReader(bytes: payload)
        return JDWPIdentifierSizes(
            fieldID: Int(try reader.readUInt32()),
            methodID: Int(try reader.readUInt32()),
            objectID: Int(try reader.readUInt32()),
            referenceTypeID: Int(try reader.readUInt32()),
            frameID: Int(try reader.readUInt32())
        )
    }

    func close() async {
        readerTask?.cancel()
        readerTask = nil
        failAllWaiters(JDWPConnectionError.connectionClosed)
        await transport.close()
    }
}
