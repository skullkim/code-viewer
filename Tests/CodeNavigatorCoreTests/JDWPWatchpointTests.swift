import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// "이 필드가 언제 바뀌는지 알고 싶다." 값이 이상해졌는데 어디서 바뀌었는지 모를 때 쓴다 —
/// 브레이크포인트를 하나씩 걸어 가며 찾는 대신 JVM 에게 물어본다.
///
/// 읽기(ACCESS)와 쓰기(MODIFICATION)가 다른 종류다. 읽기를 켜면 getter 한 번에도 멈추므로,
/// 대개 원하는 것은 쓰기다.
@Suite("JDWP 필드 watchpoint")
struct JDWPWatchpointTests {

    @Test("쓰기 watchpoint 는 kind 21 이다")
    func modificationIsKind21() throws {
        let payload = JDWPWatchpointRequest.payload(
            kind: .modification, classID: 0x11, fieldID: 0x22,
            referenceTypeIDSize: 8, fieldIDSize: 8
        )
        var reader = JDWPReader(bytes: payload)
        #expect(try reader.readByte() == 21)
        #expect(try reader.readByte() == 2, "suspendPolicy ALL")
        #expect(try reader.readInt32() == 1)
        #expect(try reader.readByte() == 9, "modKind FieldOnly 는 9")
        #expect(try reader.readIdentifier(size: 8) == 0x11)
        #expect(try reader.readIdentifier(size: 8) == 0x22)
        #expect(reader.remaining == 0)
    }

    @Test("읽기 watchpoint 는 kind 20 이다")
    func accessIsKind20() throws {
        let payload = JDWPWatchpointRequest.payload(
            kind: .access, classID: 1, fieldID: 2, referenceTypeIDSize: 8, fieldIDSize: 8
        )
        #expect(payload.first == 20)
    }

    /// 쓰기 이벤트는 **새 값**을 함께 준다. 그것이 이 기능의 요점이다 — 어디서 바뀌었는지와
    /// 무엇으로 바뀌었는지를 같이 봐야 한다.
    @Test("쓰기 이벤트에서 새 값을 읽는다")
    func readsTheNewValue() throws {
        var payload: [UInt8] = [2]
        payload += bigEndian(UInt32(1))
        payload += [21]                                       // MODIFICATION
        payload += bigEndian(UInt32(bitPattern: 44))          // requestID
        payload += identifier(7, size: 8)                     // threadID
        payload += [1] + identifier(0x11, size: 8) + identifier(0x22, size: 8) + bigEndian64(3)  // 위치
        payload += [1] + identifier(0xAA, size: 8)            // 필드가 속한 타입
        payload += identifier(0xBB, size: 8)                  // fieldID
        payload += [UInt8(ascii: "L")] + identifier(0xCC, size: 8)   // 대상 객체
        payload += [UInt8(ascii: "I")] + bigEndian(UInt32(bitPattern: 99))  // 새 값

        let change = try #require(
            try JDWPWatchpointRequest.parse(
                event: JDWPEvent(commandSet: 64, command: 100, payload: payload),
                referenceTypeIDSize: 8, methodIDSize: 8, objectIDSize: 8, fieldIDSize: 8
            )
        )
        #expect(change.threadID == 7)
        #expect(change.fieldID == 0xBB)
        #expect(change.newValue == .int(99))
    }

    /// 읽기 이벤트에는 새 값이 없다. 있다고 읽으면 그 뒤가 어긋난다.
    @Test("읽기 이벤트에는 새 값이 없다")
    func accessEventsCarryNoValue() throws {
        var payload: [UInt8] = [2]
        payload += bigEndian(UInt32(1))
        payload += [20]                                       // ACCESS
        payload += bigEndian(UInt32(bitPattern: 45))
        payload += identifier(7, size: 8)
        payload += [1] + identifier(0x11, size: 8) + identifier(0x22, size: 8) + bigEndian64(3)
        payload += [1] + identifier(0xAA, size: 8)
        payload += identifier(0xBB, size: 8)
        payload += [UInt8(ascii: "L")] + identifier(0xCC, size: 8)

        let change = try #require(
            try JDWPWatchpointRequest.parse(
                event: JDWPEvent(commandSet: 64, command: 100, payload: payload),
                referenceTypeIDSize: 8, methodIDSize: 8, objectIDSize: 8, fieldIDSize: 8
            )
        )
        #expect(change.newValue == nil)
    }

    private func bigEndian(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.bigEndian, Array.init) }
    private func bigEndian64(_ value: UInt64) -> [UInt8] { withUnsafeBytes(of: value.bigEndian, Array.init) }
    private func identifier(_ value: UInt64, size: Int) -> [UInt8] {
        Array(withUnsafeBytes(of: value.bigEndian, Array.init).suffix(size))
    }
}
