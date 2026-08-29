import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// REQ-008 and SC-6. The rule the design states most forcefully is that a bad regular
/// expression must not be disguised as an empty result set — the previous results stay on
/// screen, dimmed, and the panel says plainly that no new search ran.
@Suite("TextSearchPresentation — 전문 검색 패널 상태 (REQ-008, SC-6)")
struct TextSearchPresentationTests {

    private func item(_ path: String, _ line: Int) -> TextSearchItem {
        TextSearchItem(path: path, line: line, previewText: "let x = 1", matchRanges: [MatchRange(start: 4, end: 5)])
    }

    private func result(_ items: [TextSearchItem], total: Int? = nil, truncated: Bool = false) -> TextSearchResult {
        TextSearchResult(items: items, total: total ?? items.count, truncated: truncated, limit: 500)
    }

    @Test("검색 전에는 입력 안내만 보인다")
    func theIdleStateInvitesAQuery() {
        let panel = TextSearchPresentation.make(phase: .idle, previousResult: nil, elapsedSeconds: nil, filesSearched: nil)
        #expect(panel.resultsAreDimmed == false)
        #expect(panel.errorText == nil)
        #expect(panel.emptyText == nil)
        #expect(panel.items.isEmpty)
    }

    @Test("결과가 있으면 건수·파일 수·소요 시간을 알린다")
    func resultsCarryTheirMetadata() {
        let panel = TextSearchPresentation.make(
            phase: .results(result([item("a.swift", 1), item("a.swift", 9), item("b.swift", 3)])),
            previousResult: nil, elapsedSeconds: 0.42, filesSearched: 1284
        )
        #expect(panel.items.count == 3)
        #expect(panel.metaText == "3건 표시 · 1,284 파일 검색 · 0.42초")
        #expect(panel.errorText == nil)
    }

    @Test("검색한 파일 수를 모르면 일치한 파일 수로 대신한다 — 숫자를 지어내지 않는다")
    func aMissingFileCountFallsBackToWhatIsKnown() {
        let panel = TextSearchPresentation.make(
            phase: .results(result([item("a.swift", 1), item("a.swift", 9), item("b.swift", 3)])),
            previousResult: nil, elapsedSeconds: 0.42, filesSearched: nil
        )
        #expect(panel.metaText == "3건 표시 · 2개 파일에서 일치 · 0.42초")
    }

    @Test("결과가 0건이면 결과 없음을 표시한다")
    func anEmptyResultSaysSo() {
        let panel = TextSearchPresentation.make(phase: .results(result([])), previousResult: nil, elapsedSeconds: 0.1, filesSearched: 10)
        #expect(panel.emptyText == "결과 없음")
        #expect(panel.items.isEmpty)
    }

    @Test("상한에 도달하면 경고 바를 띄운다")
    func hittingTheCapIsAnnounced() {
        let items = (0..<500).map { item("a.swift", $0) }
        let panel = TextSearchPresentation.make(
            phase: .results(result(items, total: 500, truncated: true)),
            previousResult: nil, elapsedSeconds: 1.0, filesSearched: 100
        )
        #expect(panel.limitWarningText == "상위 500건만 표시합니다 — 검색어를 더 구체적으로 좁혀 주세요")
    }

    @Test("상한에 닿지 않으면 경고 바가 없다")
    func noCapNoWarning() {
        let panel = TextSearchPresentation.make(
            phase: .results(result([item("a.swift", 1)])), previousResult: nil, elapsedSeconds: 0.1, filesSearched: 10
        )
        #expect(panel.limitWarningText == nil)
    }

    // MARK: The rule SC-6 exists for

    @Test("잘못된 정규식은 에러로 표시된다 — 빈 결과로 위장하지 않는다")
    func anInvalidRegexIsAnErrorNotAnEmptyResult() {
        let previous = result([item("a.swift", 1), item("b.swift", 2)])
        let panel = TextSearchPresentation.make(
            phase: .failed(.invalidRegularExpression(pattern: "([unclosed", reason: "괄호가 닫히지 않았습니다")),
            previousResult: previous, elapsedSeconds: nil, filesSearched: nil
        )
        #expect(panel.errorText == "⚠ 잘못된 정규식: 괄호가 닫히지 않았습니다")
        #expect(panel.emptyText == nil, "에러를 '결과 없음'으로 보여주면 SC-6 위반이다")
    }

    @Test("정규식 에러에도 이전 결과가 흐림 상태로 남는다")
    func previousResultsSurviveARegexError() {
        let previous = result([item("a.swift", 1), item("b.swift", 2)])
        let panel = TextSearchPresentation.make(
            phase: .failed(.invalidRegularExpression(pattern: "([", reason: "미완성")),
            previousResult: previous, elapsedSeconds: nil, filesSearched: nil
        )
        #expect(panel.items.count == 2, "이전 결과가 지워지면 사용자는 검색이 0건을 냈다고 읽는다")
        #expect(panel.resultsAreDimmed)
        #expect(panel.staleResultNotice == "이전 결과 유지 (새 검색 미실행)")
    }

    @Test("이전 결과가 없는 상태의 정규식 에러도 에러로만 보인다")
    func aRegexErrorWithNoHistoryIsStillAnError() {
        let panel = TextSearchPresentation.make(
            phase: .failed(.invalidRegularExpression(pattern: "([", reason: "미완성")),
            previousResult: nil, elapsedSeconds: nil, filesSearched: nil
        )
        #expect(panel.errorText != nil)
        #expect(panel.items.isEmpty)
        #expect(panel.staleResultNotice == nil, "유지할 이전 결과가 없으면 유지한다고 말하지 않는다")
        #expect(panel.emptyText == nil)
    }

    @Test("정규식 외의 실패도 문구를 그대로 보여준다")
    func otherFailuresAreShownToo() {
        let panel = TextSearchPresentation.make(
            phase: .failed(.noProjectOpen), previousResult: nil, elapsedSeconds: nil, filesSearched: nil
        )
        #expect(panel.errorText == "⚠ 열려 있는 프로젝트가 없습니다.")
    }

    @Test("검색 중에는 이전 결과를 흐림 없이 유지한다")
    func aRunningSearchKeepsThePreviousResultsReadable() {
        let previous = result([item("a.swift", 1)])
        let panel = TextSearchPresentation.make(phase: .searching, previousResult: previous, elapsedSeconds: nil, filesSearched: nil)
        #expect(panel.isLoading)
        #expect(panel.items.count == 1)
        #expect(!panel.resultsAreDimmed, "검색 중 흐림은 정규식 에러의 신호와 구별되지 않는다")
    }

    @Test("결과는 파일별로 묶여서 나온다")
    func resultsComeGroupedByFile() {
        let panel = TextSearchPresentation.make(
            phase: .results(result([item("a.swift", 1), item("b.swift", 2), item("a.swift", 9)])),
            previousResult: nil, elapsedSeconds: 0.1, filesSearched: 5
        )
        #expect(panel.groups.map(\.path) == ["a.swift", "b.swift"])
        #expect(panel.groups[0].count == 2)
    }
}
