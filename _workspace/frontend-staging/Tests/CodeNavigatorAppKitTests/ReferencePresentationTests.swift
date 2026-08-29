import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// REQ-006. The acceptance criterion most easily lost is AC-3: the notice that reference
/// search is name-based approximation is shown *permanently*, including when there are no
/// results. A panel that drops the caveat on the empty state is claiming more certainty
/// exactly where it has least.
@Suite("ReferencePresentation — 참조 패널 상태 (REQ-006)")
struct ReferencePresentationTests {

    private func reference(_ path: String, _ line: Int, isDefinition: Bool = false) -> Reference {
        Reference(path: path, line: line, previewText: "index.buildIndex()", isDefinition: isDefinition)
    }

    private func result(_ references: [Reference], truncated: Bool = false) -> ReferenceSearchResult {
        ReferenceSearchResult(references: references, total: references.count, truncated: truncated, limit: 500)
    }

    @Test("심볼을 고르기 전에는 사용법 안내가 나온다")
    func theInitialStateExplainsHowToUseIt() {
        let panel = ReferencePresentation.make(symbolName: nil, phase: .idle, indexState: .ready)
        #expect(panel.placeholderText == "심볼에 커서를 두고 ⇧⌘B를 누르면 참조 목록이 여기에 표시됩니다")
        #expect(panel.groups.isEmpty)
    }

    @Test("근사 안내 배너는 상시 표시된다")
    func theApproximationNoticeIsAlwaysVisible() {
        // AC-3. Every phase, including the empty one.
        let phases: [ReferencePhase] = [
            .idle,
            .searching,
            .results(result([reference("a.swift", 1)])),
            .results(result([])),
            .failed(.noProjectOpen),
        ]
        for phase in phases {
            let panel = ReferencePresentation.make(symbolName: "buildIndex", phase: phase, indexState: .ready)
            #expect(panel.approximationNotice == "이름 기반 검색 — 동명 이의어 포함 가능", "\(phase)에서 배너가 사라졌다")
        }
    }

    @Test("건수와 정의 수가 헤더에 나온다")
    func theHeaderCountsReferencesAndDefinitions() {
        let panel = ReferencePresentation.make(
            symbolName: "buildIndex",
            phase: .results(result([
                reference("a.swift", 8, isDefinition: true),
                reference("b.swift", 42),
                reference("b.swift", 96),
            ])),
            indexState: .ready
        )
        #expect(panel.headerText == "buildIndex · 3건 (정의 1)")
    }

    @Test("참조가 0건이면 그렇게 말하고 배너는 남긴다")
    func anEmptyResultKeepsTheNotice() {
        // AC-4 plus AC-3 together: this is the combination a panel usually gets wrong.
        let panel = ReferencePresentation.make(symbolName: "nowhere", phase: .results(result([])), indexState: .ready)
        #expect(panel.emptyText == "'nowhere' 참조 없음")
        #expect(panel.approximationNotice != nil)
    }

    @Test("정의 위치가 배지로 구분된다")
    func definitionsAreFlagged() {
        let panel = ReferencePresentation.make(
            symbolName: "f",
            phase: .results(result([reference("a.swift", 8, isDefinition: true), reference("b.swift", 42)])),
            indexState: .ready
        )
        let rows = panel.groups.flatMap(\.items)
        #expect(rows.filter(\.isDefinition).count == 1)
    }

    @Test("결과는 파일별로 묶인다")
    func resultsAreGroupedByFile() {
        let panel = ReferencePresentation.make(
            symbolName: "f",
            phase: .results(result([reference("a.swift", 1), reference("b.swift", 2), reference("a.swift", 9)])),
            indexState: .ready
        )
        #expect(panel.groups.map(\.path) == ["a.swift", "b.swift"])
    }

    @Test("인덱싱 중이면 결과가 부분적일 수 있음을 알린다")
    func partialResultsDuringIndexingAreDisclosed() {
        let panel = ReferencePresentation.make(
            symbolName: "f",
            phase: .results(result([reference("a.swift", 1)])),
            indexState: .indexing(IndexProgress(completed: 40, total: 900))
        )
        #expect(panel.partialResultsNotice == "인덱싱 중 — 결과가 아직 부분적일 수 있습니다")
    }

    @Test("인덱스가 최신이면 부분 결과 안내는 없다")
    func noPartialNoticeWhenTheIndexIsReady() {
        let panel = ReferencePresentation.make(
            symbolName: "f", phase: .results(result([reference("a.swift", 1)])), indexState: .ready
        )
        #expect(panel.partialResultsNotice == nil)
    }

    @Test("상한에 닿으면 알린다")
    func hittingTheCapIsAnnounced() {
        let panel = ReferencePresentation.make(
            symbolName: "f",
            phase: .results(result([reference("a.swift", 1)], truncated: true)),
            indexState: .ready
        )
        #expect(panel.limitWarningText == "상위 500건만 표시합니다 — 검색어를 더 구체적으로 좁혀 주세요")
    }
}
