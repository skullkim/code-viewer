import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// 스텝은 JDWP 에서 브레이크포인트와 같은 기계로 만든다 — 이벤트 요청이다. 다른 점 둘이
/// 중요하다:
///
/// 1. **한 번 쓰고 지워야 한다.** 안 지우면 매 줄 멈춘다. 사용자는 "스텝을 한 번 눌렀는데
///    계속 멈춘다" 를 겪고, 그게 브레이크포인트 때문인지 스텝 때문인지 화면에서 구별 못 한다.
/// 2. **깊이 숫자가 직관과 반대다.** INTO=0, OVER=1, OUT=2. 바꿔 쓰면 "한 줄 넘기기" 가
///    함수 속으로 들어가고, 그건 오류가 아니라 그냥 다른 곳에서 멈춘 것으로 보인다.
@Suite("JDWP 스텝 요청")
struct JDWPStepRequestTests {

    @Test("깊이 값이 JDWP 규격과 같다")
    func matchesTheProtocolDepths() {
        #expect(JDWPStepDepth.into.rawValue == 0)
        #expect(JDWPStepDepth.over.rawValue == 1)
        #expect(JDWPStepDepth.out.rawValue == 2)
    }

    /// 페이로드를 바이트 단위로 못 박는다. 이 순서가 틀리면 JVM 이 거절하는 게 아니라
    /// **다른 요청을 만든다** — 예를 들어 크기와 깊이가 바뀌면 명령어 단위로 멈춘다.
    @Test("스텝 요청 페이로드가 규격대로다")
    func buildsTheStepRequestPayload() throws {
        let payload = JDWPStepRequest.payload(
            threadID: 0x0102, depth: .over, objectIDSize: 8
        )

        var reader = JDWPReader(bytes: payload)
        #expect(try reader.readByte() == 1, "eventKind SINGLE_STEP 은 1")
        #expect(try reader.readByte() == 2, "suspendPolicy ALL 은 2")
        #expect(try reader.readInt32() == 1, "수식어는 하나")
        #expect(try reader.readByte() == 10, "modKind Step 은 10")
        #expect(try reader.readIdentifier(size: 8) == 0x0102)
        #expect(try reader.readInt32() == 1, "size LINE 은 1 — 명령어가 아니라 줄 단위")
        #expect(try reader.readInt32() == 1, "depth OVER 는 1")
        #expect(reader.remaining == 0, "안 읽은 바이트가 남았다 — 페이로드가 규격보다 길다")
    }

    @Test("into 와 out 도 같은 모양이고 깊이만 다르다")
    func onlyTheDepthChanges() throws {
        for (depth, expected) in [(JDWPStepDepth.into, Int32(0)), (.over, 1), (.out, 2)] {
            let payload = JDWPStepRequest.payload(threadID: 7, depth: depth, objectIDSize: 8)
            var reader = JDWPReader(bytes: payload)
            try reader.skip(1 + 1 + 4 + 1 + 8 + 4)
            #expect(try reader.readInt32() == expected)
        }
    }

    /// ID 폭이 4 인 JVM 도 있다. 8 로 박으면 그 JVM 에서 페이로드가 네 바이트 길어지고,
    /// JVM 은 그 뒤를 깊이로 읽는다.
    @Test("스레드 ID 폭을 따른다")
    func honoursTheIdentifierWidth() throws {
        let payload = JDWPStepRequest.payload(threadID: 7, depth: .into, objectIDSize: 4)
        #expect(payload.count == 1 + 1 + 4 + 1 + 4 + 4 + 4)
    }
}
