import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// 핫스왑 — 멈춘 채로 코드를 고쳐 다시 넣는다. 고칠 때마다 프로그램을 다시 띄우지 않아도
/// 되는 것이 요점이다.
///
/// **JVM 이 거절할 수 있다.** 메서드를 더하거나 시그니처를 바꾸면 표준 JVM 은 못 받는다 —
/// 본문만 바꿀 수 있다. 그걸 미리 말해 주지 않으면 사용자는 저장할 때마다 알 수 없는
/// 오류를 본다.
@Suite("JDWP 클래스 다시 넣기")
struct JDWPRedefineTests {

    @Test("한 클래스의 바이트코드를 싣는다")
    func carriesOneClass() throws {
        let bytes: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE, 0x00]
        let payload = JDWPRedefineRequest.payload(
            classes: [(classID: 0x77, bytes: bytes)], referenceTypeIDSize: 8
        )
        var reader = JDWPReader(bytes: payload)
        #expect(try reader.readInt32() == 1, "클래스 수")
        #expect(try reader.readIdentifier(size: 8) == 0x77)
        #expect(try reader.readInt32() == Int32(bytes.count))
        var read: [UInt8] = []
        for _ in bytes { read.append(try reader.readByte()) }
        #expect(read == bytes)
        #expect(reader.remaining == 0)
    }

    @Test("여러 클래스를 한 번에 싣는다 — 서로 참조하는 클래스는 같이 넣어야 한다")
    func carriesSeveralClasses() throws {
        let payload = JDWPRedefineRequest.payload(
            classes: [(0x11, [0x01]), (0x22, [0x02, 0x03])], referenceTypeIDSize: 8
        )
        var reader = JDWPReader(bytes: payload)
        #expect(try reader.readInt32() == 2)
        #expect(try reader.readIdentifier(size: 8) == 0x11)
        #expect(try reader.readInt32() == 1)
        _ = try reader.readByte()
        #expect(try reader.readIdentifier(size: 8) == 0x22)
        #expect(try reader.readInt32() == 2)
    }

    /// `CapabilitiesNew` 응답에서 우리가 쓰는 세 가지를 읽는다. 못 하는 것을 메뉴에 켜 두면
    /// 사용자는 눌러 보고 알 수 없는 오류를 본다.
    @Test("JVM 이 무엇을 허용하는지 읽는다")
    func readsTheCapabilities() throws {
        // 불리언이 줄줄이 오는 응답이다. 우리가 보는 것은 정해진 자리에 있다.
        var payload = [UInt8](repeating: 0, count: 32)
        payload[JDWPCapabilities.canRedefineClassesIndex] = 1
        payload[JDWPCapabilities.canPopFramesIndex] = 0
        payload[JDWPCapabilities.canGetInstanceInfoIndex] = 1

        let capabilities = try JDWPCapabilities(payload: payload)
        #expect(capabilities.canRedefineClasses)
        #expect(!capabilities.canPopFrames)
        #expect(capabilities.canGetInstanceInfo)
    }

    /// 응답이 짧으면 **모른다고 답한다.** 없는 자리를 0 으로 읽으면 "못 한다" 가 되고,
    /// 그러면 되는 JVM 에서도 기능이 조용히 꺼진다.
    @Test("응답이 짧으면 읽지 않는다")
    func refusesAShortReply() {
        #expect(throws: (any Error).self) {
            _ = try JDWPCapabilities(payload: [1, 0, 1])
        }
    }
}
