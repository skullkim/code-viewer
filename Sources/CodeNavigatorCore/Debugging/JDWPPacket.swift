import Foundation

/// JDWP 패킷의 프레이밍.
///
/// 이 프로토콜은 조용히 틀린다. 길이를 하나 잘못 읽으면 예외가 나는 게 아니라 다음 필드를
/// 길이로 해석하고, 그때부터 읽는 값이 전부 그럴듯한 쓰레기가 된다. 스파이크가 실제로 그렇게
/// 죽었다. 그래서 프레이밍은 손으로 쓰고, 손으로 쓴 만큼 테스트로 못 박는다.
enum JDWPPacket {

    /// 모든 패킷의 헤더 크기. 길이 필드는 **이 헤더를 포함한** 전체 길이다.
    static let headerLength = 11

    static let handshake = "JDWP-Handshake"

    static func command(id: UInt32, commandSet: UInt8, command: UInt8, payload: [UInt8]) -> Encoded {
        Encoded(id: id, commandSet: commandSet, command: command, payload: payload)
    }

    struct Encoded {
        let id: UInt32
        let commandSet: UInt8
        let command: UInt8
        let payload: [UInt8]

        func encoded() -> [UInt8] {
            let length = UInt32(JDWPPacket.headerLength + payload.count)
            return bigEndian(length) + bigEndian(id) + [0, commandSet, command] + payload
        }

        private func bigEndian(_ value: UInt32) -> [UInt8] {
            withUnsafeBytes(of: value.bigEndian) { Array($0) }
        }
    }
}

/// 한 패킷의 헤더. 응답인지 이벤트인지, 그리고 응답이면 성공인지가 전부 여기 적혀 있다.
struct JDWPPacketHeader: Sendable, Hashable {
    let length: UInt32
    let id: UInt32
    let flags: UInt8
    /// 명령 패킷과 이벤트에서만 의미가 있다.
    let commandSet: UInt8
    let command: UInt8

    /// 응답에서만 의미가 있다. 0 이 성공.
    ///
    /// **오류는 페이로드가 아니라 헤더에 있다.** 이걸 안 보면 실패한 명령의 빈 페이로드를
    /// 정상 응답으로 읽는다 — 조용한 실패의 교과서적인 자리다.
    var errorCode: UInt16 {
        UInt16(commandSet) << 8 | UInt16(command)
    }

    var isReply: Bool {
        flags & 0x80 != 0
    }

    var payloadLength: Int {
        Int(length) - JDWPPacket.headerLength
    }

    init?(bytes: [UInt8]) {
        guard bytes.count >= JDWPPacket.headerLength else { return nil }
        let length = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        // 헤더보다 짧다고 주장하는 패킷은 손상된 것이다. 그대로 믿으면 payloadLength 가
        // 음수가 되고, 그 값으로 읽기를 시도한다.
        guard length >= UInt32(JDWPPacket.headerLength) else { return nil }
        self.length = length
        self.id = UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7])
        self.flags = bytes[8]
        self.commandSet = bytes[9]
        self.command = bytes[10]
    }
}
