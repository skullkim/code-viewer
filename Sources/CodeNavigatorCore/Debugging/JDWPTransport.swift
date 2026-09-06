import Foundation

/// The bytes in and out. Separated from the protocol so the framing can be tested without a JVM —
/// and because the one thing this project cannot do in a unit test is start a debuggee.
protocol JDWPTransport: Sendable {
    func send(_ bytes: [UInt8]) async throws
    /// Reads exactly `count` bytes, or throws. Partial reads are the transport's problem, not the
    /// protocol's — a framing layer that has to cope with half a header cannot be reasoned about.
    func receive(count: Int) async throws -> [UInt8]
    func close() async
}

enum JDWPConnectionError: Error, Sendable {
    case connectionClosed
    /// The other end did not answer with `JDWP-Handshake`, so it is not a debug port.
    case notADebugPort(received: String)
    /// The JVM refused the command. The code is JDWP's own.
    case commandFailed(commandSet: UInt8, command: UInt8, errorCode: UInt16)
    case malformedPacket
    case connectFailed(String)
}

/// The identifier widths this JVM uses.
///
/// **가변이다.** 스파이크가 붙은 JVM 은 전부 8이었지만 그건 그 JVM 의 사실이지 프로토콜의
/// 사실이 아니다. 8 로 박으면 다른 JVM 에서 모든 파싱이 한 칸씩 밀린다 — 그리고 밀린 값은
/// 예외가 아니라 그럴듯한 숫자로 나온다.
struct JDWPIdentifierSizes: Sendable, Hashable {
    let fieldID: Int
    let methodID: Int
    let objectID: Int
    let referenceTypeID: Int
    let frameID: Int
}

/// One event packet, kept until somebody asks for it.
struct JDWPEvent: Sendable, Hashable {
    let commandSet: UInt8
    let command: UInt8
    let payload: [UInt8]
}
