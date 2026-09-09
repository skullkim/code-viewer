import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 참조·검색 결과는 **탭마다 따로** 남아야 한다.
///
/// 사용자가 겪은 것: "참조, 검색은 탭 단위로 프로젝트를 바꿔도 그대로인데 이거 프로젝트
/// 단위로 다르게 해봐."
///
/// 지금은 다른 탭의 결과를 **숨기기만** 한다 — 하나뿐인 자리에 마지막 검색이 덮어쓰므로,
/// A 에서 찾고 B 에서 찾은 뒤 A 로 돌아오면 A 의 결과는 사라져 있다. 프로젝트를 오가며
/// 읽는 사람에게는 매번 다시 찾으라는 말과 같다.
@Suite("탭별 검색 상태")
@MainActor
struct PerTabSearchStateTests {

    private let tabA = ProjectTabIdentifier()
    private let tabB = ProjectTabIdentifier()

    private final class ActiveTab: @unchecked Sendable {
        var identifier: ProjectTabIdentifier?
    }

    private func makeModel() -> (SearchModel, ActiveTab, FakeProjectSession) {
        let active = ActiveTab()
        let project = FakeProjectSession()
        let model = SearchModel(
            sessionProvider: { project },
            activeTabProvider: { active.identifier }
        )
        return (model, active, project)
    }

    @Test("탭을 오가도 각 탭의 전문 검색 결과가 남는다")
    func keepsTextSearchResultsPerTab() async {
        let (model, active, project) = makeModel()

        active.identifier = tabA
        project.textSearchResult = TextSearchResult(
            items: [TextSearchItem(path: "A.java", line: 1, previewText: "a", matchRanges: [])],
            total: 1, truncated: false, limit: 100
        )
        model.textSearchQuery = "찾을것-A"
        await model.runTextSearch()

        active.identifier = tabB
        project.textSearchResult = TextSearchResult(
            items: [TextSearchItem(path: "B.java", line: 2, previewText: "b", matchRanges: [])],
            total: 1, truncated: false, limit: 100
        )
        model.textSearchQuery = "찾을것-B"
        await model.runTextSearch()
        #expect(model.lastTextSearchResult?.items.map(\.path) == ["B.java"])

        // A 로 돌아오면 A 의 결과가 그대로 있어야 한다.
        active.identifier = tabA
        #expect(
            model.lastTextSearchResult?.items.map(\.path) == ["A.java"],
            "A 의 결과가 사라졌다 — 다시 찾으라는 말과 같다"
        )
        #expect(model.textSearchQuery == "찾을것-A", "검색어도 탭을 따라와야 한다")
    }

    @Test("참조 결과도 탭마다 남는다")
    func keepsReferenceResultsPerTab() async {
        let (model, active, project) = makeModel()

        active.identifier = tabA
        project.referenceResult = ReferenceSearchResult(
            references: [Reference(path: "A.java", line: 1, previewText: "a", matchRanges: [], isDefinition: true)],
            total: 1, truncated: false, limit: 100
        )
        await model.showReferences(to: "thing")

        active.identifier = tabB
        project.referenceResult = ReferenceSearchResult(references: [], total: 0, truncated: false, limit: 100)
        await model.showReferences(to: "other")

        active.identifier = tabA
        #expect(model.referenceSymbolName == "thing", "A 의 참조 검색어가 사라졌다")
    }

    /// 아직 한 번도 안 찾은 탭은 비어 있어야 한다. 옆 탭의 결과가 보이면 그 줄 번호로
    /// 엉뚱한 파일이 열린다.
    @Test("검색한 적 없는 탭은 비어 있다")
    func aFreshTabShowsNothing() async {
        let (model, active, project) = makeModel()

        active.identifier = tabA
        project.textSearchResult = TextSearchResult(
            items: [TextSearchItem(path: "A.java", line: 1, previewText: "a", matchRanges: [])],
            total: 1, truncated: false, limit: 100
        )
        model.textSearchQuery = "찾을것"
        await model.runTextSearch()

        active.identifier = tabB
        #expect(model.lastTextSearchResult == nil)
        #expect(model.textSearchQuery.isEmpty, "옆 탭의 검색어가 남아 있다")
    }

    /// 탭을 닫으면 그 상태도 버린다. 안 버리면 오래 쓸수록 쌓이기만 한다.
    @Test("닫은 탭의 상태는 버린다")
    func forgetsAClosedTab() async {
        let (model, active, project) = makeModel()

        active.identifier = tabA
        project.textSearchResult = TextSearchResult(
            items: [TextSearchItem(path: "A.java", line: 1, previewText: "a", matchRanges: [])],
            total: 1, truncated: false, limit: 100
        )
        model.textSearchQuery = "찾을것"
        await model.runTextSearch()

        model.forgetTab(tabA)
        #expect(model.lastTextSearchResult == nil)
    }
}
