import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// "NullPointerException 이 나는 순간 멈춰라." 브레이크포인트를 어디에 걸어야 할지 모를 때
/// 쓰는 것이고, 그래서 디버깅에서 가장 자주 켜는 기능 중 하나다.
///
/// caught / uncaught 를 나눠 켤 수 있어야 한다. 프레임워크가 예외를 잡아 처리하는 코드에서
/// caught 를 켜면 **초당 수십 번 멈춘다** — 그러면 사용자는 디버거를 끈다.
@Suite("JDWP 예외 브레이크포인트")
struct JDWPExceptionRequestTests {

    @Test("모든 예외에 걸 때는 타입을 0 으로 둔다")
    func catchesEveryException() throws {
        let payload = try #require(JDWPExceptionRequest.payload(
            classID: nil, caught: false, uncaught: true, referenceTypeIDSize: 8
        ))
        var reader = JDWPReader(bytes: payload)
        #expect(try reader.readByte() == 4, "eventKind EXCEPTION 은 4")
        #expect(try reader.readByte() == 2, "suspendPolicy ALL")
        #expect(try reader.readInt32() == 1)
        #expect(try reader.readByte() == 8, "modKind ExceptionOnly 는 8")
        #expect(try reader.readIdentifier(size: 8) == 0, "타입 0 은 '모든 예외'")
        #expect(try reader.readByte() == 0, "caught 안 잡음")
        #expect(try reader.readByte() == 1, "uncaught 잡음")
        #expect(reader.remaining == 0)
    }

    @Test("특정 예외 타입으로 좁힐 수 있다")
    func narrowsToOneType() throws {
        let payload = try #require(JDWPExceptionRequest.payload(
            classID: 0xBEEF, caught: true, uncaught: true, referenceTypeIDSize: 8
        ))
        var reader = JDWPReader(bytes: payload)
        try reader.skip(1 + 1 + 4 + 1)
        #expect(try reader.readIdentifier(size: 8) == 0xBEEF)
        #expect(try reader.readByte() == 1)
        #expect(try reader.readByte() == 1)
    }

    /// 둘 다 끄면 JVM 은 요청을 받아들이고 **아무것도 보고하지 않는다.** 사용자에게는
    /// "켰는데 안 멈춘다" 로 보이고, 그건 고장과 구별되지 않는다.
    @Test("둘 다 끄는 요청은 만들지 않는다")
    func refusesARequestThatWouldReportNothing() {
        #expect(
            JDWPExceptionRequest.payload(
                classID: nil, caught: false, uncaught: false, referenceTypeIDSize: 8
            ) == nil
        )
    }

    /// 예외 이벤트는 위치 뒤에 **예외 객체와 잡히는 위치**가 더 붙는다. 브레이크포인트와 같은
    /// 모양으로 읽으면 그 뒤가 어긋난다.
    @Test("예외 이벤트에서 예외 객체를 읽는다")
    func readsTheThrownException() throws {
        var payload: [UInt8] = [2]
        payload += bigEndian(UInt32(1))
        payload += [4]                                   // eventKind EXCEPTION
        payload += bigEndian(UInt32(bitPattern: 31))     // requestID
        payload += identifier(5, size: 8)                // threadID
        payload += [1] + identifier(0x11, size: 8) + identifier(0x22, size: 8) + bigEndian64(9)  // 던진 위치
        payload += [UInt8(ascii: "L")] + identifier(0x99, size: 8)                                // 예외 객체
        payload += [1] + identifier(0x33, size: 8) + identifier(0x44, size: 8) + bigEndian64(0)   // 잡히는 위치

        let thrown = try #require(
            try JDWPExceptionRequest.parse(
                event: JDWPEvent(commandSet: 64, command: 100, payload: payload),
                referenceTypeIDSize: 8, methodIDSize: 8, objectIDSize: 8
            )
        )
        #expect(thrown.threadID == 5)
        #expect(thrown.exceptionObjectID == 0x99)
        #expect(thrown.classID == 0x11)
        #expect(thrown.isCaught, "잡히는 위치가 있으면 caught 다")
    }

    /// 잡히는 위치가 전부 0 이면 아무도 안 잡는다는 뜻 — uncaught 다. 이걸 구별 못 하면
    /// 화면이 "여기서 죽는다" 와 "여기서 잡힌다" 를 같은 말로 한다.
    @Test("잡히는 위치가 비면 uncaught 다")
    func recognisesAnUncaughtException() throws {
        var payload: [UInt8] = [2]
        payload += bigEndian(UInt32(1))
        payload += [4] + bigEndian(UInt32(bitPattern: 31)) + identifier(5, size: 8)
        payload += [1] + identifier(0x11, size: 8) + identifier(0x22, size: 8) + bigEndian64(9)
        payload += [UInt8(ascii: "L")] + identifier(0x99, size: 8)
        payload += [0] + identifier(0, size: 8) + identifier(0, size: 8) + bigEndian64(0)

        let thrown = try #require(
            try JDWPExceptionRequest.parse(
                event: JDWPEvent(commandSet: 64, command: 100, payload: payload),
                referenceTypeIDSize: 8, methodIDSize: 8, objectIDSize: 8
            )
        )
        #expect(!thrown.isCaught)
    }

    private func bigEndian(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.bigEndian, Array.init) }
    private func bigEndian64(_ value: UInt64) -> [UInt8] { withUnsafeBytes(of: value.bigEndian, Array.init) }
    private func identifier(_ value: UInt64, size: Int) -> [UInt8] {
        Array(withUnsafeBytes(of: value.bigEndian, Array.init).suffix(size))
    }
}
