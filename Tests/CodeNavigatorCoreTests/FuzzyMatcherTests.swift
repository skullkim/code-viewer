import Testing

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-007 AC-1 (부분 일치·순서 보존 퍼지 매칭이 관련도순으로 나온다)
@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {

    // 매칭 성립 여부 — 순서를 보존하는 부분수열이어야 한다.

    @Test("약어 질의가 캐멀케이스 이름에 매치된다")
    func abbreviationMatchesCamelCaseName() {
        #expect(FuzzyMatcher.match(query: "SymIdx", candidate: "SymbolIndex") != nil)
    }

    @Test("대소문자를 무시하고 매치된다")
    func matchIgnoresLetterCase() {
        #expect(FuzzyMatcher.match(query: "symidx", candidate: "SymbolIndex") != nil)
    }

    @Test("순서가 뒤집힌 질의는 매치되지 않는다")
    func outOfOrderQueryDoesNotMatch() {
        #expect(FuzzyMatcher.match(query: "xdi", candidate: "index") == nil)
    }

    @Test("이름에 없는 문자가 있으면 매치되지 않는다")
    func queryWithAbsentCharacterDoesNotMatch() {
        #expect(FuzzyMatcher.match(query: "symz", candidate: "SymbolIndex") == nil)
    }

    @Test("빈 질의는 매치되지 않는다")
    func emptyQueryDoesNotMatch() {
        #expect(FuzzyMatcher.match(query: "", candidate: "SymbolIndex") == nil)
    }

    // 강조 구간 — 연속 인덱스는 하나로 병합된 반열린 구간.

    @Test("연속 매치는 하나의 구간으로 병합된다")
    func consecutiveMatchesMergeIntoOneRange() throws {
        let result = try #require(FuzzyMatcher.match(query: "sym", candidate: "SymbolIndex"))

        #expect(result.matchRanges == [MatchRange(start: 0, end: 3)])
    }

    @Test("떨어진 매치는 각각의 구간으로 남는다")
    func scatteredMatchesStaySeparateRanges() throws {
        let result = try #require(FuzzyMatcher.match(query: "Idx", candidate: "SymbolIndex"))

        #expect(
            result.matchRanges == [
                MatchRange(start: 6, end: 7),
                MatchRange(start: 8, end: 9),
                MatchRange(start: 10, end: 11),
            ]
        )
    }

    // 점수 — 완전 일치 > 접두 일치 > 흩어진 일치.

    @Test("완전 일치가 접두 일치보다, 접두 일치가 흩어진 일치보다 높은 점수를 받는다")
    func exactMatchOutranksPrefixMatchOutranksScatteredMatch() throws {
        let exact = try #require(FuzzyMatcher.match(query: "sym", candidate: "sym"))
        let prefix = try #require(FuzzyMatcher.match(query: "sym", candidate: "SymbolIndex"))
        let scattered = try #require(FuzzyMatcher.match(query: "sym", candidate: "SystemMemory"))

        #expect(exact.score > prefix.score)
        #expect(prefix.score > scattered.score)
    }

    @Test("구분자 뒤 매치가 구분자 없는 같은 길이 이름보다 높은 점수를 받는다")
    func matchAfterSeparatorScoresHigherThanPlainMatch() throws {
        let afterSeparator = try #require(FuzzyMatcher.match(query: "ab", candidate: "xa_bc"))
        let plain = try #require(FuzzyMatcher.match(query: "ab", candidate: "xazbc"))

        #expect(afterSeparator.score > plain.score)
    }
}
