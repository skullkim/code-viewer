import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 좁히기가 켜지면 안내 문구도 바뀌어야 한다. "이름 기반 검색" 이라고 계속 적혀 있으면
/// 사용자는 목록이 안 좁혀졌다고 읽고, 사라진 항목을 버그로 신고한다.
@Suite("참조 패널 안내 문구 — 좁힌 뒤")
struct NarrowedReferenceNoticeTests {

    private func notice(discarded: Int, unresolved: Int) -> String? {
        let result = ReferenceSearchResult(
            references: [Reference(path: "A.java", line: 1, previewText: "x", matchRanges: [], isDefinition: false)],
            total: 1,
            truncated: false,
            limit: 1000,
            narrowing: ReferenceNarrowing(receiverType: "Member", discarded: discarded, unresolved: unresolved)
        )
        return ReferencePresentation.make(
            symbolName: "getId",
            phase: .results(result),
            indexState: .ready
        ).approximationNotice
    }

    @Test("좁힌 타입을 말한다")
    func namesTheType() throws {
        let text = try #require(notice(discarded: 267, unresolved: 0))
        #expect(text.contains("Member"))
        // 확실하다고 말하지 않는다 — 이 해석기는 상속을 따지지 않는다.
        #expect(text.contains("상속"))
    }

    @Test("판정 못 한 건수를 밝힌다")
    func admitsWhatItCouldNotJudge() throws {
        let text = try #require(notice(discarded: 267, unresolved: 36))
        #expect(text.contains("Member"))
        #expect(text.contains("36"))
    }

    @Test("좁히지 않았으면 예전 문구 그대로다")
    func keepsTheOldNoticeWhenNothingWasNarrowed() throws {
        let result = ReferenceSearchResult(references: [], total: 0, truncated: false, limit: 1000)
        let presentation = ReferencePresentation.make(
            symbolName: "getId", phase: .results(result), indexState: .ready
        )
        #expect(presentation.approximationNotice == ReferencePresentation.approximationNoticeText)
    }
}
