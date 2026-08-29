import Testing

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-006 AC-1 · REQ-008 AC-1 (파일:라인 + 미리보기),
/// 계약 §3.1 MatchRange (오프셋은 UTF-16 코드 유닛)
@Suite("PreviewTextBuilder")
struct PreviewTextBuilderTests {

    // UTF-8 바이트 오프셋 → UTF-16 코드 유닛 오프셋 환산.

    @Test("한글이 앞에 있는 줄의 UTF-8 구간이 UTF-16 구간으로 환산된다")
    func byteRangeConvertsToUtf16RangeOnHangulLine() {
        // "한글 needle 값" — needle 앞은 한(3) + 글(3) + 공백(1) = UTF-8 7바이트,
        // 같은 자리가 UTF-16으로는 2 + 1 = 3 코드 유닛이다.
        let line = "한글 needle 값"

        let preview = PreviewTextBuilder.makePreview(line: line, utf8MatchRanges: [7..<13])

        #expect(preview.previewText == line)
        #expect(preview.matchRanges == [MatchRange(start: 3, end: 9)])
    }

    @Test("선행 공백이 구간을 그만큼 왼쪽으로 민다")
    func leadingWhitespaceShiftsRangesLeft() {
        // "    let x = needle" — needle은 UTF-8 12바이트 뒤. 공백 4칸이 잘리므로 8로 밀린다.
        let line = "    let x = needle"

        let preview = PreviewTextBuilder.makePreview(line: line, utf8MatchRanges: [12..<18])

        #expect(preview.previewText == "let x = needle")
        #expect(preview.matchRanges == [MatchRange(start: 8, end: 14)])
    }

    // 절단 — 200 UTF-16 코드 유닛.

    @Test("200 코드 유닛을 넘는 줄은 절단된다")
    func longLineIsTruncated() {
        let line = String(repeating: "a", count: 250)

        let preview = PreviewTextBuilder.makePreview(line: line, utf8MatchRanges: [])

        #expect(preview.previewText.utf16.count == 200)
    }

    @Test("절단 뒤로 밀려난 구간은 버려진다")
    func rangeBeyondTruncationIsDropped() {
        let line = String(repeating: "a", count: 250)

        let preview = PreviewTextBuilder.makePreview(line: line, utf8MatchRanges: [210..<220])

        #expect(preview.matchRanges.isEmpty)
    }

    @Test("절단 경계에 걸친 구간은 미리보기 길이로 잘린다")
    func rangeCrossingTruncationIsClamped() {
        let line = String(repeating: "a", count: 250)

        let preview = PreviewTextBuilder.makePreview(line: line, utf8MatchRanges: [195..<205])

        #expect(preview.matchRanges == [MatchRange(start: 195, end: 200)])
    }

    @Test("절단이 서로게이트 페어를 가운데서 쪼개지 않는다")
    func truncationNeverSplitsSurrogatePair() {
        // 이모지는 UTF-16 2 코드 유닛이라, 199자 뒤에 두면 200 경계에 정확히 걸친다.
        let line = String(repeating: "a", count: 199) + "😀" + "bbb"

        let preview = PreviewTextBuilder.makePreview(line: line, utf8MatchRanges: [])

        #expect(preview.previewText == String(repeating: "a", count: 199))
        #expect(preview.previewText.utf16.count == 199)
    }

    // 시그니처 — 120 UTF-16 코드 유닛.

    @Test("시그니처는 앞뒤 공백을 제거하고 120 코드 유닛으로 절단한다")
    func signatureIsTrimmedAndTruncated() {
        let line = "  " + String(repeating: "b", count: 150) + "  "

        let signature = PreviewTextBuilder.makeSignature(line: line)

        #expect(signature == String(repeating: "b", count: 120))
    }

    @Test("짧은 시그니처는 그대로 유지된다")
    func shortSignatureIsUnchanged() {
        let signature = PreviewTextBuilder.makeSignature(line: "    fun index(path: String)  ")

        #expect(signature == "fun index(path: String)")
    }
}
