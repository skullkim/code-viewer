import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// `MatchRange` carries UTF-16 code-unit offsets — the contract says so explicitly. Swift
/// strings are indexed by grapheme cluster, so treating those offsets as character counts
/// silently misplaces the highlight on any line containing Korean, an emoji or an accent.
/// This repository's own source is full of Korean comments, so "silently" would not last
/// long, but it would still ship if nothing checked it.
@Suite("MatchHighlighter — UTF-16 오프셋을 안전하게 구간으로 (REQ-007·008)")
struct MatchHighlighterTests {

    private func range(_ start: Int, _ end: Int) -> MatchRange {
        MatchRange(start: start, end: end)
    }

    @Test("ASCII 문자열의 일치 구간이 정확히 잘린다")
    func asciiRangesSplitCorrectly() {
        let segments = MatchHighlighter.segments(text: "buildIndex", ranges: [range(5, 10)])
        #expect(segments.map(\.text) == ["build", "Index"])
        #expect(segments.map(\.isMatch) == [false, true])
    }

    @Test("한글이 섞여도 구간이 밀리지 않는다")
    func koreanTextDoesNotShiftTheHighlight() {
        // "인덱스 " is 4 UTF-16 units; the match on "abc" therefore starts at 4.
        let segments = MatchHighlighter.segments(text: "인덱스 abc", ranges: [range(4, 7)])
        #expect(segments.map(\.text) == ["인덱스 ", "abc"])
        #expect(segments.map(\.isMatch) == [false, true])
    }

    @Test("서로게이트 쌍(이모지)을 두 코드 유닛으로 센다")
    func emojiCountAsTwoCodeUnits() {
        // "a👍b": 'a' is 1 unit, the emoji is 2, so 'b' starts at offset 3.
        let segments = MatchHighlighter.segments(text: "a👍b", ranges: [range(3, 4)])
        #expect(segments.map(\.text) == ["a👍", "b"])
        #expect(segments.map(\.isMatch) == [false, true])
    }

    @Test("이모지 자체를 강조할 수 있다")
    func anEmojiItselfCanBeHighlighted() {
        let segments = MatchHighlighter.segments(text: "a👍b", ranges: [range(1, 3)])
        #expect(segments.map(\.text) == ["a", "👍", "b"])
        #expect(segments.map(\.isMatch) == [false, true, false])
    }

    @Test("여러 구간이 순서대로 처리된다")
    func severalRangesAreHandledInOrder() {
        let segments = MatchHighlighter.segments(text: "abcdef", ranges: [range(0, 1), range(3, 4)])
        #expect(segments.map(\.text) == ["a", "bc", "d", "ef"])
        #expect(segments.map(\.isMatch) == [true, false, true, false])
    }

    @Test("구간이 정렬돼 있지 않아도 올바르게 처리된다")
    func unsortedRangesStillWork() {
        let segments = MatchHighlighter.segments(text: "abcdef", ranges: [range(3, 4), range(0, 1)])
        #expect(segments.map(\.text) == ["a", "bc", "d", "ef"])
        #expect(segments.map(\.isMatch) == [true, false, true, false])
    }

    @Test("겹치는 구간은 하나로 합쳐진다")
    func overlappingRangesMerge() {
        let segments = MatchHighlighter.segments(text: "abcdef", ranges: [range(1, 4), range(2, 5)])
        #expect(segments.map(\.text) == ["a", "bcde", "f"])
        #expect(segments.map(\.isMatch) == [false, true, false])
    }

    @Test("문자열 전체가 일치일 수 있다")
    func theWholeStringCanMatch() {
        let segments = MatchHighlighter.segments(text: "abc", ranges: [range(0, 3)])
        #expect(segments.map(\.text) == ["abc"])
        #expect(segments.map(\.isMatch) == [true])
    }

    @Test("일치 구간이 없으면 통짜 한 구간이다")
    func noRangesGivesOneSegment() {
        let segments = MatchHighlighter.segments(text: "abc", ranges: [])
        #expect(segments.map(\.text) == ["abc"])
        #expect(segments.map(\.isMatch) == [false])
    }

    @Test("빈 문자열은 구간을 만들지 않는다")
    func anEmptyStringHasNoSegments() {
        #expect(MatchHighlighter.segments(text: "", ranges: [range(0, 1)]).isEmpty)
    }

    // MARK: Defensive — a bad range must not take the window down

    @Test("범위를 벗어난 구간은 잘라 낸다 — 크래시하지 않는다")
    func outOfBoundsRangesAreClamped() {
        // Highlighting is cosmetic; an off-by-one from the engine must degrade the
        // highlight, not kill the panel (REQ-NF-004).
        let segments = MatchHighlighter.segments(text: "abc", ranges: [range(1, 99)])
        #expect(segments.map(\.text) == ["a", "bc"])
        #expect(segments.map(\.isMatch) == [false, true])
    }

    @Test("완전히 범위 밖이거나 뒤집힌 구간은 무시된다")
    func nonsensicalRangesAreIgnored() {
        #expect(MatchHighlighter.segments(text: "abc", ranges: [range(10, 20)]).map(\.text) == ["abc"])
        #expect(MatchHighlighter.segments(text: "abc", ranges: [range(2, 1)]).map(\.text) == ["abc"])
        #expect(MatchHighlighter.segments(text: "abc", ranges: [range(-5, 2)]).map(\.text) == ["ab", "c"])
        #expect(MatchHighlighter.segments(text: "abc", ranges: [range(1, 1)]).map(\.text) == ["abc"])
    }

    @Test("서로게이트 쌍 한가운데를 가리켜도 무너지지 않는다")
    func aRangeSplittingASurrogatePairIsSurvivable() {
        // No valid engine output does this, but a UTF-16 offset can name a position that
        // is not a character boundary, and the panel must not crash on it.
        let segments = MatchHighlighter.segments(text: "a👍b", ranges: [range(1, 2)])
        #expect(segments.map(\.text).joined() == "a👍b", "글자가 사라지거나 중복되면 안 된다")
    }
}
