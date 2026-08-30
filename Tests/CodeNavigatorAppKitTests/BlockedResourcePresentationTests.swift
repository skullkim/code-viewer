import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// Design 02b §3 W-15: the sandbox is announced whether or not it blocked anything.
///
/// The chip at zero is the part that looks redundant and is not. A block the user cannot
/// see becomes "why is this image missing", and the conclusion is that the app is broken —
/// so the standing chip is what makes the blocking legible rather than mysterious.
@Suite("BlockedResourcePresentation — 차단 고지 (INV-6, §3 W-15)")
struct BlockedResourcePresentationTests {

    private func blocked(_ kind: BlockedResourceKind, _ detail: String) -> BlockedResource {
        BlockedResource(kind: kind, detail: detail)
    }

    // MARK: 칩

    @Test("차단이 0건이어도 샌드박스 칩은 남는다")
    func theChipIsShownEvenWithNothingBlocked() {
        let panel = BlockedResourcePresentation.make(blocked: [])

        #expect(panel.chipLabel == "🛡 샌드박스")
        #expect(panel.blockedCount == 0)
        #expect(panel.emptyText == "차단된 항목이 없습니다")
        #expect(panel.rows.isEmpty)
    }

    @Test("차단이 있으면 칩이 건수를 센다")
    func theChipCountsWhatWasBlocked() {
        let panel = BlockedResourcePresentation.make(blocked: [
            blocked(.remoteImage, "a.com"),
            blocked(.script, "(인라인)"),
        ])

        #expect(panel.chipLabel == "🛡 차단됨 2")
        #expect(panel.blockedCount == 2)
        #expect(panel.emptyText == nil)
    }

    @Test("건수가 크면 천 단위로 끊어 읽는다")
    func largeCountsAreGrouped() {
        let many = (0..<1_284).map { blocked(.remoteImage, "host\($0).com") }
        #expect(BlockedResourcePresentation.make(blocked: many).chipLabel == "🛡 차단됨 1,284")
    }

    @Test("정책 문구는 언제나 있다")
    func thePolicyTextIsAlwaysPresent() {
        // "해제할 수 없다"는 것 자체가 사용자가 알아야 할 정보다 — 없으면 어딘가에
        // 토글이 있을 거라고 찾게 된다.
        for blockedList in [[], [blocked(.script, "(인라인)")]] {
            let panel = BlockedResourcePresentation.make(blocked: blockedList)
            #expect(panel.policyText.contains("네트워크 요청을 하지 않고"))
            #expect(panel.policyText.contains("해제할 수 없습니다"))
        }
    }

    // MARK: 팝오버 집계

    @Test("종류별로 한 줄씩 집계한다")
    func rowsAreAggregatedByKind() {
        let panel = BlockedResourcePresentation.make(blocked: [
            blocked(.remoteImage, "raw.githubusercontent.com"),
            blocked(.remoteImage, "raw.githubusercontent.com"),
            blocked(.script, "(인라인)"),
            blocked(.remoteStylesheet, "cdn.jsdelivr.net"),
            blocked(.outsideProjectRoot, "../../.ssh/config"),
        ])

        #expect(panel.rows.count == 4)
        #expect(panel.rows.first { $0.kind == .remoteImage }?.count == 2)
        #expect(panel.rows.first { $0.kind == .script }?.count == 1)
    }

    @Test("차단이 아주 많아도 줄 수는 여섯을 넘지 않는다")
    func thePopoverNeverGrowsPastSixRows() {
        // 40건이 40줄이면 아무도 안 읽는다 — W-15가 종류별 집계를 지정한 이유다.
        let many = BlockedResourceKind.allCases.flatMap { kind in
            (0..<20).map { blocked(kind, "src\($0)") }
        }
        let panel = BlockedResourcePresentation.make(blocked: many)

        #expect(panel.rows.count <= 6)
        #expect(panel.blockedCount == BlockedResourceKind.allCases.count * 20)
    }

    @Test("출처가 하나면 그대로 보여 준다")
    func aSingleSourceIsNamedOutright() {
        let panel = BlockedResourcePresentation.make(blocked: [
            blocked(.remoteImage, "raw.githubusercontent.com"),
            blocked(.remoteImage, "raw.githubusercontent.com"),
        ])
        #expect(panel.rows.first?.detail == "raw.githubusercontent.com")
    }

    @Test("출처가 여럿이면 첫 곳과 나머지 수를 적는다")
    func severalSourcesCollapseToAnOutrightCount() {
        let panel = BlockedResourcePresentation.make(blocked: [
            blocked(.remoteImage, "a.com"),
            blocked(.remoteImage, "b.com"),
            blocked(.remoteImage, "c.com"),
        ])
        #expect(panel.rows.first?.detail == "a.com 외 2곳")
    }

    @Test("빈 종류는 줄을 만들지 않는다")
    func kindsWithNothingBlockedGetNoRow() {
        let panel = BlockedResourcePresentation.make(blocked: [blocked(.script, "(인라인)")])
        #expect(panel.rows.map(\.kind) == [.script])
    }

    @Test("줄은 §3 W-15의 종류 순서를 따른다")
    func rowsFollowTheDocumentsOrder() {
        // 순서가 문서와 다르면 화면과 명세를 나란히 놓고 읽을 수 없다.
        let panel = BlockedResourcePresentation.make(blocked: BlockedResourceKind.allCases.map {
            blocked($0, "src")
        })
        #expect(panel.rows.map(\.kind) == BlockedResourceKind.allCases)
    }

    @Test("모든 줄이 화면 문구와 건수를 갖는다")
    func everyRowIsRenderable() {
        let panel = BlockedResourcePresentation.make(blocked: BlockedResourceKind.allCases.map {
            blocked($0, "src")
        })
        #expect(!panel.rows.isEmpty)
        for row in panel.rows {
            #expect(!row.label.isEmpty, "\(row.kind.rawValue)")
            #expect(row.count > 0, "\(row.kind.rawValue)")
        }
    }
}
