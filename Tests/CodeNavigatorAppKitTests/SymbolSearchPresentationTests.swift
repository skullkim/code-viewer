import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// REQ-007 and design §3 W-3. The modal is keyboard-only, so its selection arithmetic is
/// as much an acceptance criterion as its text (AC-3).
@Suite("SymbolSearchPresentation — 심볼 검색 모달 (REQ-007)")
struct SymbolSearchPresentationTests {

    private func hit(_ name: String, line: Int = 1) -> SymbolSearchResult {
        SymbolSearchResult(
            definition: SymbolDefinition(name: name, kind: .class, path: "Sources/\(name).swift", line: line, signature: "class \(name)"),
            score: 100,
            matchRanges: [MatchRange(start: 0, end: 1)]
        )
    }

    @Test("입력 전에는 안내만 보인다")
    func theEmptyQueryShowsAHint() {
        let modal = SymbolSearchPresentation.make(query: "", results: [], indexState: .ready, selectedIndex: 0, isLoading: false)
        #expect(modal.hintText == "심볼 이름의 일부나 약어를 입력하세요")
        #expect(modal.emptyText == nil, "입력 전은 '결과 없음'이 아니다")
    }

    @Test("결과가 0건이면 결과 없음을 표시한다")
    func noResultsSaysSo() {
        let modal = SymbolSearchPresentation.make(query: "zzz", results: [], indexState: .ready, selectedIndex: 0, isLoading: false)
        #expect(modal.emptyText == "결과 없음 — 다른 이름으로 검색해 보세요")
        #expect(modal.hintText == nil)
    }

    @Test("인덱싱 중이면 결과가 부분적일 수 있음을 진행률과 함께 알린다")
    func partialResultsDuringIndexingAreDisclosed() {
        let modal = SymbolSearchPresentation.make(
            query: "sym", results: [hit("SymbolIndex")],
            indexState: .indexing(IndexProgress(completed: 120, total: 900)),
            selectedIndex: 0, isLoading: false
        )
        #expect(modal.partialResultsNotice == "인덱싱 중 — 결과가 아직 부분적일 수 있습니다 (120/900)")
    }

    @Test("인덱스가 최신이면 부분 결과 안내가 없다")
    func noNoticeWhenTheIndexIsReady() {
        let modal = SymbolSearchPresentation.make(query: "s", results: [hit("S")], indexState: .ready, selectedIndex: 0, isLoading: false)
        #expect(modal.partialResultsNotice == nil)
    }

    @Test("0건이어도 인덱싱 중이면 그 사실을 함께 알린다")
    func anEmptyResultDuringIndexingExplainsItself() {
        // Otherwise "no results" reads as "this symbol does not exist", when the truth may
        // be "it has not been indexed yet".
        let modal = SymbolSearchPresentation.make(
            query: "zzz", results: [], indexState: .indexing(IndexProgress(completed: 5, total: 900)),
            selectedIndex: 0, isLoading: false
        )
        #expect(modal.emptyText != nil)
        #expect(modal.partialResultsNotice != nil)
    }

    // MARK: Keyboard-only operation (AC-3)

    @Test("↓는 다음 항목으로 이동한다")
    func downMovesToTheNextResult() {
        #expect(SymbolSearchPresentation.nextIndex(from: 0, resultCount: 3, direction: .down) == 1)
    }

    @Test("↑는 이전 항목으로 이동한다")
    func upMovesToThePreviousResult() {
        #expect(SymbolSearchPresentation.nextIndex(from: 2, resultCount: 3, direction: .up) == 1)
    }

    @Test("마지막에서 ↓는 처음으로 돌아간다")
    func selectionWrapsAtTheEnd() {
        #expect(SymbolSearchPresentation.nextIndex(from: 2, resultCount: 3, direction: .down) == 0)
    }

    @Test("처음에서 ↑는 마지막으로 간다")
    func selectionWrapsAtTheStart() {
        #expect(SymbolSearchPresentation.nextIndex(from: 0, resultCount: 3, direction: .up) == 2)
    }

    @Test("결과가 없으면 선택 이동이 무너지지 않는다")
    func movingWithNoResultsIsSafe() {
        #expect(SymbolSearchPresentation.nextIndex(from: 0, resultCount: 0, direction: .down) == 0)
        #expect(SymbolSearchPresentation.nextIndex(from: 0, resultCount: 0, direction: .up) == 0)
    }

    @Test("결과가 줄어들면 선택이 범위 안으로 조정된다")
    func theSelectionIsClampedWhenResultsShrink() {
        // Typing another character narrows the list under a selection that pointed at the
        // old tail; an unclamped index would index out of bounds on Enter.
        let modal = SymbolSearchPresentation.make(
            query: "sym", results: [hit("A"), hit("B")], indexState: .ready, selectedIndex: 7, isLoading: false
        )
        #expect(modal.selectedIndex == 1)
    }

    @Test("결과가 없으면 선택 항목도 없다")
    func noResultsMeansNoSelection() {
        let modal = SymbolSearchPresentation.make(query: "zzz", results: [], indexState: .ready, selectedIndex: 3, isLoading: false)
        #expect(modal.selectedResult == nil)
    }

    @Test("선택된 결과를 돌려준다 — Enter가 무엇을 열지 결정한다")
    func theSelectedResultIsAvailable() {
        let modal = SymbolSearchPresentation.make(
            query: "s", results: [hit("A"), hit("B"), hit("C")], indexState: .ready, selectedIndex: 1, isLoading: false
        )
        #expect(modal.selectedResult?.definition.name == "B")
    }

    @Test("결과는 상위 50건까지만 보여준다")
    func atMostFiftyResultsAreShown() {
        let results = (0..<80).map { hit("S\($0)") }
        let modal = SymbolSearchPresentation.make(query: "s", results: results, indexState: .ready, selectedIndex: 0, isLoading: false)
        #expect(modal.results.count == 50)
    }

    @Test("로딩 표시는 200ms를 넘을 때만 — 깜빡임을 만들지 않는다")
    func theSpinnerAppearsOnlyForSlowSearches() {
        #expect(!SymbolSearchPresentation.make(query: "s", results: [], indexState: .ready, selectedIndex: 0, isLoading: false).showsSpinner)
        #expect(SymbolSearchPresentation.make(query: "s", results: [], indexState: .ready, selectedIndex: 0, isLoading: true).showsSpinner)
    }
}
