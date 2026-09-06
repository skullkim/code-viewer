import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// 아직 로드되지 않은 클래스에 브레이크포인트를 걸 수 있어야 한다.
///
/// 이게 없으면 `suspend=y` 로 띄운 JVM — 즉 **처음부터 디버깅하려는 경우** — 에서 아무 데도
/// 못 건다. 그 JVM 은 우리 클래스를 아직 로드하지 않았고, `ClassesBySignature` 는 정상적으로
/// 0건을 답한다. 0건을 "그런 클래스 없음" 으로 읽으면 브레이크포인트가 조용히 사라진다.
@Suite("JDWP 클래스 로드 대기")
struct JDWPClassPrepareTests {

    /// ClassPrepare 요청의 페이로드. 수식어를 틀리면 JVM 이 거절하는 게 아니라 **모든**
    /// 클래스 로드를 보고한다 — 수천 개다.
    @Test("ClassPrepare 요청이 클래스 이름으로 좁혀진다")
    func narrowsToOneClass() throws {
        let payload = JDWPClassPrepareRequest.payload(className: "com.example.Thing")

        var reader = JDWPReader(bytes: payload)
        #expect(try reader.readByte() == 8, "eventKind CLASS_PREPARE 는 8")
        #expect(try reader.readByte() == 2, "suspendPolicy ALL — 로드 직후 멈춰야 브레이크포인트를 걸 수 있다")
        #expect(try reader.readInt32() == 1)
        #expect(try reader.readByte() == 5, "modKind ClassMatch 는 5")
        #expect(try reader.readString() == "com.example.Thing")
        #expect(reader.remaining == 0)
    }

    /// 이벤트에서 무엇을 읽어야 하는지. 여기서 밀리면 클래스 id 자리에 엉뚱한 값이 들어오고,
    /// 그 id 로 건 브레이크포인트는 아무 데도 안 걸린다.
    @Test("ClassPrepare 이벤트에서 클래스 이름과 id 를 읽는다")
    func readsThePreparedClass() throws {
        var payload: [UInt8] = [2]                                   // suspendPolicy
        payload += bigEndian(UInt32(1))                              // 이벤트 1개
        payload += [8]                                               // eventKind CLASS_PREPARE
        payload += bigEndian(UInt32(bitPattern: 77))                 // requestID
        payload += identifier(9, size: 8)                            // threadID
        payload += [1]                                               // refTypeTag CLASS
        payload += identifier(0xABCD, size: 8)                       // typeID
        payload += string("Lcom/example/Thing;")                     // signature
        payload += bigEndian(UInt32(7))                              // status

        let prepared = try #require(
            try JDWPClassPrepareRequest.parse(
                event: JDWPEvent(commandSet: 64, command: 100, payload: payload),
                referenceTypeIDSize: 8,
                objectIDSize: 8
            )
        )
        #expect(prepared.className == "com.example.Thing")
        #expect(prepared.classID == 0xABCD)
        #expect(prepared.threadID == 9)
        #expect(prepared.requestID == 77)
    }

    /// 다른 종류의 이벤트를 ClassPrepare 로 읽으면 안 된다 — 페이로드 모양이 달라서 그 뒤가
    /// 전부 쓰레기가 된다.
    @Test("브레이크포인트 이벤트는 ClassPrepare 가 아니다")
    func doesNotMistakeABreakpoint() throws {
        var payload: [UInt8] = [2]
        payload += bigEndian(UInt32(1))
        payload += [2]                                               // eventKind BREAKPOINT
        payload += bigEndian(UInt32(bitPattern: 5))
        payload += identifier(1, size: 8)

        #expect(
            try JDWPClassPrepareRequest.parse(
                event: JDWPEvent(commandSet: 64, command: 100, payload: payload),
                referenceTypeIDSize: 8, objectIDSize: 8
            ) == nil
        )
    }

    @Test("서명을 점 표기 이름으로 되돌린다")
    func turnsTheSignatureIntoAName() {
        #expect(JDWPClassPrepareRequest.className(fromSignature: "LProbe;") == "Probe")
        #expect(
            JDWPClassPrepareRequest.className(fromSignature: "Lcom/example/deep/Thing;")
                == "com.example.deep.Thing"
        )
        // 중첩 클래스는 `$` 로 온다. 이름을 그대로 둔다 — 우리가 거는 클래스와 비교만 하면 된다.
        #expect(JDWPClassPrepareRequest.className(fromSignature: "LOuter$Inner;") == "Outer$Inner")
    }

    private func bigEndian(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian, Array.init)
    }
    private func identifier(_ value: UInt64, size: Int) -> [UInt8] {
        Array(withUnsafeBytes(of: value.bigEndian, Array.init).suffix(size))
    }
    private func string(_ text: String) -> [UInt8] {
        bigEndian(UInt32(text.utf8.count)) + Array(text.utf8)
    }
}
