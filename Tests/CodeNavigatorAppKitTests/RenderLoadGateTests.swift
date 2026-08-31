import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// 규칙이 붙기 전에는 아무것도 그리지 않는다 (ADR-0109 "실패는 닫히는 쪽으로", INV-6).
@Suite("RenderLoadGate — 규칙이 붙기 전엔 로드하지 않는다 (INV-6)")
struct RenderLoadGateTests {

    private let document = "<p>문서</p>"

    // MARK: 로드 게이트

    @Test("규칙이 붙은 뒤에만 문서를 넘긴다")
    func onlyAReadySandboxGetsTheDocument() {
        #expect(RenderLoadGate.documentToLoad(document, readiness: .ready) == document)
    }

    @Test("컴파일 중에는 아무것도 넘기지 않는다")
    func nothingIsHandedOverWhileCompiling() {
        // 규칙 목록은 **비동기로** 컴파일된다. 그 사이에 문서를 넣으면 그 순간의 웹뷰에는
        // 전면 차단이 없다 — 원격 참조가 나가는 창이 열린다.
        #expect(RenderLoadGate.documentToLoad(document, readiness: .compiling) == nil)
    }

    @Test("컴파일에 실패하면 그리지 않는다 — 비어 있는 화면이 새는 화면보다 낫다")
    func aFailedCompileRefusesToRender() {
        #expect(RenderLoadGate.documentToLoad(document, readiness: .failed(reason: "무엇이든")) == nil)
    }

    @Test("문서를 넘기는 상태는 ready 하나뿐이다")
    func readyIsTheOnlyStateThatLoads() {
        // 상태를 하나씩 세는 대신 **전수로** 확인한다. 나중에 상태가 늘었을 때 "그 상태에서도
        // 로드되나"를 아무도 안 묻는 것이 이 종류의 구멍이 생기는 방식이다.
        let states: [RenderSandboxReadiness] = [
            .compiling,
            .ready,
            .failed(reason: "컴파일 실패"),
        ]

        let loading = states.filter { RenderLoadGate.documentToLoad(document, readiness: $0) != nil }

        #expect(loading == [.ready], "규칙 없이 그리는 상태가 있다: \(loading)")
    }

    // MARK: 실패를 말한다

    @Test("실패하면 무슨 일인지 화면에 말한다")
    func aFailureIsExplainedOnScreen() {
        // 조용히 빈 화면이면 AC-6 위반이고, 사용자는 문서가 비었다고 믿는다.
        let notice = RenderLoadGate.notice(for: .failed(reason: "규칙 컴파일 실패"))

        #expect(notice != nil)
        #expect(notice?.actions.contains(.viewSource) == true, "막다른 곳에는 빠져나갈 길이 있다")
        #expect(notice?.detail.contains("규칙 컴파일 실패") == true, "사유를 마스킹하지 않는다")
    }

    @Test("정상 상태에서는 카드를 띄우지 않는다")
    func noNoticeWhenThingsAreFine() {
        #expect(RenderLoadGate.notice(for: .ready) == nil)
        #expect(RenderLoadGate.notice(for: .compiling) == nil)
    }

    // MARK: 규칙 자체

    @Test("규칙은 전면 차단이다 — 스킴을 열거하지 않는다")
    func theRuleBlocksEverything() throws {
        // ADR-0109 실측: 정규식에 분기(`|`)를 못 쓰므로 스킴 열거는 규칙을 여러 개로 쪼개야
        // 하고, 그건 **빠뜨린 스킴이 열린다**는 뜻이다.
        let data = try #require(RenderContentRules.blockEverything.data(using: .utf8))
        let rules = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        #expect(rules.count == 1, "규칙이 여럿이면 그중 빠진 것이 곧 구멍이다")
        let trigger = try #require(rules[0]["trigger"] as? [String: Any])
        let action = try #require(rules[0]["action"] as? [String: Any])
        #expect(trigger["url-filter"] as? String == ".*")
        #expect(action["type"] as? String == "block")
    }

    @Test("되살리는 규칙이 없다")
    func nothingIsExemptedBackIn() {
        // ADR-0109 실측: `ignore-previous-rules` 로는 커스텀 스킴조차 되살아나지 않았다.
        // 그런 규칙이 들어 있다면 누군가 되살릴 수 있다고 **믿고** 넣은 것이다.
        #expect(!RenderContentRules.blockEverything.contains("ignore-previous-rules"))
        #expect(!RenderContentRules.blockEverything.contains("allow"))
    }
}
