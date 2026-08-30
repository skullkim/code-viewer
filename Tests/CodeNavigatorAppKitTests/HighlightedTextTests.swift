import SwiftUI
import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// The step between `MatchHighlighter` and the screen (REQ-006 AC-1 · REQ-007 AC-1 · REQ-008 AC-1).
///
/// `MatchHighlighter` is well covered, but assembly is where a highlight can still go
/// wrong in a way nobody sees in a diff: a run dropped, a run doubled, a Korean line cut
/// mid-character. The invariant worth pinning is that marking text never *changes* it —
/// the preview must still read as the source line it came from.
@Suite("HighlightedText — 일치 강조 조립 (REQ-006·007·008)")
struct HighlightedTextTests {

    private func attributed(_ text: String, _ ranges: [MatchRange]) -> AttributedString {
        HighlightedText.attributedString(
            segments: MatchHighlighter.segments(text: text, ranges: ranges),
            baseColor: DesignTokens.textSecondary
        )
    }

    private func plainText(_ attributed: AttributedString) -> String {
        String(attributed.characters)
    }

    @Test("강조를 입혀도 원래 줄과 글자가 같다")
    func markingNeverChangesTheText() {
        let line = "index.buildIndex(files: scanner.sourceFiles())"
        let ranges = [MatchRange(start: 6, end: 16)]

        #expect(plainText(attributed(line, ranges)) == line)
    }

    @Test("한글 줄도 글자가 그대로 남는다")
    func koreanLinesSurviveIntact() {
        // 이 레포의 소스에는 한글이 실제로 들어 있다. UTF-16 오프셋을 문자 인덱스로
        // 착각해 자르면 여기서 글자가 깨진다 — 03 §3.1이 경고하는 바로 그 자리다.
        let line = "/// 디바운스 후 증분 갱신을 요청한다"
        let ranges = [MatchRange(start: 11, end: 16)]

        let result = attributed(line, ranges)

        #expect(plainText(result) == line)
        #expect(result.runs.count > 1)
    }

    @Test("이모지가 든 줄도 글자가 그대로 남는다")
    func emojiSurviveIntact() {
        // 서로게이트 쌍 중간에서 자르면 이모지가 대체 문자 둘로 깨진다.
        // MatchHighlighter가 경계로 물러나는지를 조립 결과에서 확인한다.
        let line = "let status = \"✅ 완료\""
        let ranges = [MatchRange(start: 14, end: 15)]

        #expect(plainText(attributed(line, ranges)) == line)
    }

    @Test("일치 구간에만 배경이 칠해진다")
    func onlyMatchedRunsGetTheTint() {
        let result = attributed("abcdef", [MatchRange(start: 2, end: 4)])

        let tinted = result.runs.filter { $0.backgroundColor != nil }
        let plain = result.runs.filter { $0.backgroundColor == nil }

        #expect(tinted.count == 1)
        #expect(plain.count == 2)
        #expect(tinted.first.map { String(result[$0.range].characters) } == "cd")
    }

    @Test("일치가 없으면 배경이 하나도 없다")
    func noMatchesMeansNoTint() {
        let result = attributed("abcdef", [])

        #expect(plainText(result) == "abcdef")
        #expect(result.runs.allSatisfy { $0.backgroundColor == nil })
    }

    @Test("한 줄에 여러 번 일치하면 강조도 여러 곳이다")
    func severalHitsOnOneLineAreAllMarked() {
        // 계약이 항목을 줄당 하나로 접기 때문에(`id`가 "경로:라인"), 한 줄의 여러
        // 일치는 행이 아니라 matchRanges 복수로 온다. 하나만 칠하면 나머지를 잃는다.
        let result = attributed("index.buildIndex(buildIndex)", [
            MatchRange(start: 6, end: 16),
            MatchRange(start: 17, end: 27),
        ])

        #expect(result.runs.filter { $0.backgroundColor != nil }.count == 2)
    }

    @Test("빈 줄은 빈 결과가 된다")
    func anEmptyLineStaysEmpty() {
        #expect(plainText(attributed("", [MatchRange(start: 0, end: 3)])).isEmpty)
    }
}
