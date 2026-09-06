import Testing
import Foundation
@testable import CodeNavigatorCore

/// JDWP 는 조용히 틀리는 프로토콜이다. 길이를 하나 잘못 읽으면 예외가 나는 게 아니라 **다음
/// 필드를 길이로 해석**하고, 그때부터 읽는 모든 값이 그럴듯한 쓰레기가 된다. 스파이크에서
/// 실제로 그렇게 크래시했다.
///
/// 그래서 프레이밍과 읽기를 먼저 못 박는다. 여기가 틀리면 위층은 전부 무의미하다.
@Suite("JDWP 와이어 포맷")
struct JDWPWireFormatTests {

    // MARK: 패킷 프레이밍

    @Test("명령 패킷은 11바이트 헤더 뒤에 페이로드가 온다")
    func encodesACommandPacket() {
        let packet = JDWPPacket.command(id: 1, commandSet: 1, command: 7, payload: [0xAB])
        let bytes = packet.encoded()

        #expect(bytes.count == 12)
        #expect(Array(bytes[0..<4]) == [0, 0, 0, 12], "길이는 헤더를 포함한 전체다")
        #expect(Array(bytes[4..<8]) == [0, 0, 0, 1])
        #expect(bytes[8] == 0, "명령 패킷의 플래그는 0")
        #expect(bytes[9] == 1)
        #expect(bytes[10] == 7)
        #expect(bytes[11] == 0xAB)
    }

    @Test("페이로드가 없어도 헤더 11바이트는 그대로다")
    func encodesAnEmptyPayload() {
        #expect(JDWPPacket.command(id: 9, commandSet: 1, command: 1, payload: []).encoded().count == 11)
    }

    @Test("응답 헤더를 읽는다 — 플래그 0x80 이 응답 표시다")
    func decodesAReplyHeader() throws {
        let header: [UInt8] = [0, 0, 0, 15, 0, 0, 0, 42, 0x80, 0, 0]
        let decoded = try #require(JDWPPacketHeader(bytes: header))
        #expect(decoded.length == 15)
        #expect(decoded.id == 42)
        #expect(decoded.isReply)
        #expect(decoded.payloadLength == 4)
    }

    @Test("이벤트는 응답이 아니다 — 응답 대기 중에 섞여 들어온다")
    func distinguishesAnEventFromAReply() throws {
        let event: [UInt8] = [0, 0, 0, 11, 0, 0, 0, 7, 0, 64, 100]
        let decoded = try #require(JDWPPacketHeader(bytes: event))
        #expect(!decoded.isReply)
        #expect(decoded.commandSet == 64, "이벤트는 command set 64")
    }

    /// 응답의 오류 코드는 페이로드가 아니라 헤더에 있다. 이걸 안 보면 실패한 명령의 빈
    /// 페이로드를 정상 응답으로 읽는다 — 조용한 실패의 교과서적인 자리다.
    @Test("응답의 오류 코드를 읽는다")
    func readsTheErrorCodeOfAReply() throws {
        let failed: [UInt8] = [0, 0, 0, 11, 0, 0, 0, 3, 0x80, 0, 99]
        let decoded = try #require(JDWPPacketHeader(bytes: failed))
        #expect(decoded.errorCode == 99)
        #expect(JDWPPacketHeader(bytes: [0, 0, 0, 11, 0, 0, 0, 3, 0x80, 0, 0])?.errorCode == 0)
    }

    @Test("헤더가 11바이트가 안 되면 읽지 않는다")
    func refusesAShortHeader() {
        #expect(JDWPPacketHeader(bytes: [0, 0, 0, 11, 0, 0]) == nil)
    }

    /// 길이가 헤더보다 짧다고 주장하는 패킷은 손상된 것이다. 그대로 믿으면 payloadLength 가
    /// 음수가 되고, 그걸로 읽기를 시도한다.
    @Test("길이가 11보다 작다고 적힌 패킷은 거절한다")
    func refusesALengthSmallerThanTheHeader() {
        #expect(JDWPPacketHeader(bytes: [0, 0, 0, 4, 0, 0, 0, 1, 0x80, 0, 0]) == nil)
    }

    // MARK: 값 읽기

    @Test("빅엔디언 정수를 읽는다")
    func readsBigEndianIntegers() throws {
        var reader = JDWPReader(bytes: [0x00, 0x00, 0x01, 0x00, 0xFF])
        #expect(try reader.readInt32() == 256)
        #expect(try reader.readByte() == 0xFF)
    }

    @Test("문자열은 길이 접두 UTF-8 이다")
    func readsALengthPrefixedString() throws {
        var reader = JDWPReader(bytes: [0, 0, 0, 3] + Array("abc".utf8))
        #expect(try reader.readString() == "abc")
    }

    /// **ID 크기는 프로토콜상 가변이다.** 8 로 박으면 다른 JVM 에서 전부 어긋난다 — 스파이크가
    /// 확인한 이 JVM 은 8이었지만, 그건 이 JVM 의 사실이지 프로토콜의 사실이 아니다.
    @Test("ID 는 IDSizes 가 말한 크기로 읽는다")
    func readsIdentifiersAtTheAnnouncedWidth() throws {
        var wide = JDWPReader(bytes: [0, 0, 0, 0, 0, 0, 0, 7])
        #expect(try wide.readIdentifier(size: 8) == 7)

        var narrow = JDWPReader(bytes: [0, 0, 0, 7])
        #expect(try narrow.readIdentifier(size: 4) == 7)
    }

    @Test("남은 바이트보다 많이 읽으려 하면 던진다 — 0 을 돌려주지 않는다")
    func throwsRatherThanReturningZero() {
        var reader = JDWPReader(bytes: [0, 0])
        #expect(throws: (any Error).self) { try reader.readInt32() }
    }

    /// 스파이크에서 실제로 크래시한 자리. `Methods`(cmd 5)는 문자열이 **둘**이고
    /// `MethodsWithGeneric`(cmd 15)이 셋이다. 하나 더 읽으면 다음 메서드의 ID 를 길이로
    /// 해석하고, 그 길이는 보통 거대한 수라 그 자리에서 죽는다.
    @Test("Methods 응답은 메서드당 문자열 둘이다")
    func parsesAMethodsReply() throws {
        var payload: [UInt8] = [0, 0, 0, 2]
        for (id, name, signature) in [(UInt64(11), "step", "()V"), (UInt64(12), "main", "([Ljava/lang/String;)V")] {
            payload += withUnsafeBytes(of: id.bigEndian) { Array($0) }
            for text in [name, signature] {
                payload += withUnsafeBytes(of: UInt32(text.utf8.count).bigEndian) { Array($0) }
                payload += Array(text.utf8)
            }
            payload += [0, 0, 0, 1]   // modifiers
        }

        let methods = try JDWPMethod.parseList(payload: payload, methodIDSize: 8)
        #expect(methods.count == 2)
        #expect(methods[0].name == "step")
        #expect(methods[0].id == 11)
        #expect(methods[1].name == "main")
        #expect(methods[1].signature == "([Ljava/lang/String;)V")
    }
}
