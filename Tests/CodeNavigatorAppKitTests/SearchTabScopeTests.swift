import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 사용자 문장: **"탭 단위로 보고 싶어"** (REQ-012).
///
/// 세션은 이미 활성 탭을 따라간다 — 다음 검색은 옳은 프로젝트에 간다. 하지만 **이미 화면에
/// 그려진 결과**는 탭을 옮겨도 그대로 남아 있었다. 그리고 결과가 든 것은 *상대* 경로다.
/// 에디터의 루트는 탭을 따라 옮겨가므로(엔진 `activateProjectTab`), 남아 있는 A 의 결과를
/// 누르면 `B_루트 + A_상대경로` 로 열린다:
///
/// - 그 경로가 B 에 없으면 nvim 은 **빈 버퍼를 새로 만든다**(`:edit` 은 에러가 아니다)
/// - 그 경로가 B 에도 있으면(`src/main.rs` 처럼 흔한 이름) **B 의 다른 파일이 조용히 열린다**
///
/// 두 번째가 위험하다 — 사용자는 A 의 검색 결과를 눌렀는데 B 의 파일을 보고 있고, 아무 것도
/// 잘못됐다고 말해 주지 않는다.
@MainActor
@Suite("검색 결과는 탭을 따라간다 (REQ-012 — 사용자 문장 \"탭 단위로 보고 싶어\")")
struct SearchTabScopeTests {

    private func reference(path: String) -> ReferenceSearchResult {
        ReferenceSearchResult(
            references: [
                SymbolReference(path: path, line: 12, columnStart: 0, columnEnd: 7, previewText: "handler()")
            ],
            total: 1,
            truncated: false,
            limit: 500
        )
    }

    @Test("탭을 옮기면 앞 프로젝트의 참조 결과가 화면에 남지 않는다")
    func referenceResultsDoNotSurviveATabSwitch() async {
        let tabA = ProjectTabIdentifier()
        let tabB = ProjectTabIdentifier()
        var active = tabA

        let session = FakeProjectSession()
        session.referenceResult = reference(path: "src/handler.rs")

        let search = SearchModel(
            sessionProvider: { session },
            activeTabProvider: { active }
        )

        await search.showReferences(to: "handler")
        guard case .results = search.referencePhase else {
            Issue.record("A 에서 검색이 결과를 내지 못했다 — 이 테스트의 전제가 깨졌다")
            return
        }

        active = tabB

        guard case .idle = search.referencePhase else {
            Issue.record("B 로 옮겼는데 A 의 참조 결과가 그대로 있다 — 누르면 B 루트로 풀린다")
            return
        }
    }

    @Test("탭을 옮기면 앞 프로젝트의 텍스트 검색 결과가 화면에 남지 않는다")
    func textSearchResultsDoNotSurviveATabSwitch() async {
        let tabA = ProjectTabIdentifier()
        let tabB = ProjectTabIdentifier()
        var active = tabA

        let session = FakeProjectSession()
        session.textSearchResult = TextSearchResult(
            items: [TextSearchItem(path: "src/main.rs", line: 3, columnStart: 0, columnEnd: 4, previewText: "todo")],
            total: 1, truncated: false, limit: 500
        )

        let search = SearchModel(
            sessionProvider: { session },
            activeTabProvider: { active }
        )

        search.textSearchQuery = "todo"
        await search.runTextSearch()
        guard case .results = search.textSearchPhase else {
            Issue.record("A 에서 텍스트 검색이 결과를 내지 못했다 — 전제가 깨졌다")
            return
        }

        active = tabB

        guard case .idle = search.textSearchPhase else {
            Issue.record("B 로 옮겼는데 A 의 텍스트 검색 결과가 그대로 있다")
            return
        }
    }

    @Test("같은 탭에 머무르면 결과는 그대로 있다")
    func resultsSurviveWhenTheTabDoesNotChange() async {
        let tabA = ProjectTabIdentifier()
        let session = FakeProjectSession()
        session.referenceResult = reference(path: "src/handler.rs")

        let search = SearchModel(
            sessionProvider: { session },
            activeTabProvider: { tabA }
        )

        await search.showReferences(to: "handler")

        // 반대 방향의 실측: 탭 확인이 결과를 *항상* 지우면 위 두 테스트는 통과하면서
        // 검색 패널은 영원히 비어 있다. 통과하는 초록이 기능을 죽인 경우다.
        guard case .results = search.referencePhase else {
            Issue.record("탭을 옮기지 않았는데 결과가 사라졌다 — 검색 패널이 죽었다")
            return
        }
    }
}
