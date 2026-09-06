import Foundation

/// Speaks JDWP over a transport: handshake, one request at a time, and the events that arrive
/// in between.
///
/// **응답과 이벤트는 같은 소켓으로 섞여 온다.** 브레이크포인트가 걸리는 순간이 곧 이벤트가
/// 도착하는 순간이고, 그때 우리는 보통 다른 명령의 답을 기다리고 있다. 순서로 짝지으면 그
/// 자리에서 어긋나고, 어긋난 뒤로는 모든 값이 그럴듯한 쓰레기가 된다. 그래서 헤더의 플래그와
/// id 로 가른다.
///
/// An actor because the correlation only works if one request is in flight at a time: two
/// concurrent readers would race for each other's replies.
actor JDWPConnection {
    private let transport: any JDWPTransport
    private var nextIdentifier: UInt32 = 1
    private var pendingEvents: [JDWPEvent] = []

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

    /// Sends one command and returns its reply payload, stepping over any events that arrive first.
    func request(commandSet: UInt8, command: UInt8, payload: [UInt8]) async throws -> [UInt8] {
        let identifier = nextIdentifier
        nextIdentifier += 1

        let packet = JDWPPacket.command(
            id: identifier, commandSet: commandSet, command: command, payload: payload
        )
        try await transport.send(packet.encoded())

        while true {
            let headerBytes = try await transport.receive(count: JDWPPacket.headerLength)
            guard let header = JDWPPacketHeader(bytes: headerBytes) else {
                throw JDWPConnectionError.malformedPacket
            }
            let body = header.payloadLength > 0
                ? try await transport.receive(count: header.payloadLength)
                : []

            guard header.isReply else {
                // 우리 답이 아니라 소식이다. **버리지 않는다** — 이게 브레이크포인트가
                // 걸렸다는 통지이고, 버리면 멈춘 사실 자체가 사라진다.
                pendingEvents.append(
                    JDWPEvent(commandSet: header.commandSet, command: header.command, payload: body)
                )
                continue
            }
            guard header.id == identifier else {
                // 다른 명령의 답이 남아 있다는 뜻이다. 한 번에 하나만 보내므로 정상적으로는
                // 오지 않지만, 왔다면 짝짓기가 이미 어긋난 것이라 조용히 넘기지 않는다.
                throw JDWPConnectionError.malformedPacket
            }
            guard header.errorCode == 0 else {
                throw JDWPConnectionError.commandFailed(
                    commandSet: commandSet, command: command, errorCode: header.errorCode
                )
            }
            return body
        }
    }

    /// Hands over the events seen so far and forgets them.
    func drainEvents() -> [JDWPEvent] {
        defer { pendingEvents.removeAll() }
        return pendingEvents
    }

    /// Waits for the next event, stepping over nothing — used while the debuggee runs.
    func nextEvent() async throws -> JDWPEvent {
        if !pendingEvents.isEmpty {
            return pendingEvents.removeFirst()
        }
        while true {
            let headerBytes = try await transport.receive(count: JDWPPacket.headerLength)
            guard let header = JDWPPacketHeader(bytes: headerBytes) else {
                throw JDWPConnectionError.malformedPacket
            }
            let body = header.payloadLength > 0
                ? try await transport.receive(count: header.payloadLength)
                : []
            guard !header.isReply else { continue }
            return JDWPEvent(commandSet: header.commandSet, command: header.command, payload: body)
        }
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
        await transport.close()
    }
}
