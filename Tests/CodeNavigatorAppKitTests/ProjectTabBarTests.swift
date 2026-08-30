import Testing
import CoreGraphics
import Foundation
@testable import CodeNavigatorAppKit

/// REQ-012 AC-1 and design 02b §3 W-11.
///
/// The two rules with teeth are about *not losing the project's identity*: the bar stays
/// visible at one tab because nothing else on screen names the open project any more, and
/// same-named tabs gain a parent folder because two checkouts of one repository are
/// otherwise indistinguishable.
@Suite("ProjectTabBar — 탭 목록 표시 (REQ-012 AC-1, §3 W-11)")
struct ProjectTabBarTests {

    private func tab(
        _ name: String,
        path: String? = nil,
        dirty: Int = 0,
        index: IndexStateSnapshot = .ready
    ) -> ProjectTabDescriptor {
        let root = path ?? "/Users/dev/\(name)"
        return ProjectTabDescriptor(
            id: root, rootPath: root, name: name, dirtyBufferCount: dirty, indexState: index
        )
    }

    private func make(
        _ tabs: [ProjectTabDescriptor],
        active: String? = nil,
        width: CGFloat = 1600
    ) -> ProjectTabBarPresentation {
        ProjectTabBarPresentation.make(
            tabs: tabs, activeTabID: active ?? tabs.first?.id, barWidth: width
        )
    }

    // MARK: 표시 여부

    @Test("탭이 없으면 탭 바 자체가 없다")
    func noTabsMeansNoBar() {
        let bar = ProjectTabBarPresentation.make(tabs: [], activeTabID: nil, barWidth: 1600)
        #expect(!bar.isVisible)
        #expect(bar.items.isEmpty)
    }

    @Test("탭이 하나여도 탭 바를 보여 준다")
    func oneTabStillShowsTheBar() {
        // §12 판정 1. 툴바 프로젝트 팝업이 제거됐으므로, 여기서 숨기면 열린 프로젝트
        // 이름이 화면 어디에도 남지 않는다 — 관례(Safari)를 따르다 정보를 잃는 경우다.
        let bar = make([tab("repo")])
        #expect(bar.isVisible)
        #expect(bar.items.count == 1)
    }

    // MARK: 동명 구분

    @Test("이름이 겹치면 상위 폴더를 보조 라벨로 붙인다")
    func duplicateNamesGainTheirParentFolder() {
        // 같은 레포의 두 체크아웃이 흔하다. 이름만으로는 두 탭이 완전히 같아 보인다.
        let bar = make([
            tab("app", path: "/Users/dev/frontend/app"),
            tab("app", path: "/Users/dev/backend/app"),
        ])

        #expect(bar.items.map(\.secondaryLabel) == ["frontend", "backend"])
    }

    @Test("이름이 안 겹치면 보조 라벨을 붙이지 않는다")
    func uniqueNamesStayBare() {
        // 늘 붙이면 112pt 폭에서 정작 이름이 밀려난다.
        let bar = make([tab("repo"), tab("other")])
        #expect(bar.items.allSatisfy { $0.secondaryLabel == nil })
    }

    @Test("세 개가 같은 이름이어도 전부 구분된다")
    func threeWayCollisionsAreAllDisambiguated() {
        let bar = make([
            tab("app", path: "/a/one/app"),
            tab("app", path: "/a/two/app"),
            tab("app", path: "/a/three/app"),
        ])
        #expect(bar.items.compactMap(\.secondaryLabel).count == 3)
    }

    // MARK: 상태 표시

    @Test("활성 탭 하나만 활성으로 표시된다")
    func exactlyOneTabIsActive() {
        let tabs = [tab("a"), tab("b"), tab("c")]
        let bar = make(tabs, active: tabs[1].id)
        #expect(bar.items.filter(\.isActive).map(\.id) == [tabs[1].id])
    }

    @Test("더티 탭에 표시와 툴팁이 붙는다")
    func aDirtyTabIsMarked() {
        // 배경 탭의 저장 안 된 변경은 다른 어디에도 보이지 않는다 — 상태바는 활성 탭 것이다.
        let bar = make([tab("repo", dirty: 3)])
        #expect(bar.items[0].isDirty)
        #expect(bar.items[0].dirtyTooltip == "저장하지 않은 변경 3건")
    }

    @Test("깨끗한 탭에는 더티 표시가 없다")
    func aCleanTabIsNotMarked() {
        let bar = make([tab("repo")])
        #expect(!bar.items[0].isDirty)
        #expect(bar.items[0].dirtyTooltip == nil)
    }

    @Test("인덱싱 중인 탭에 스피너와 툴팁이 붙는다")
    func anIndexingTabSpins() {
        // 배경 탭의 인덱싱은 상태바에 안 보이므로 탭이 유일한 표면이다.
        let bar = make([tab("repo", index: .working(label: "인덱싱 중 1,284/4,812"))])
        #expect(bar.items[0].showsIndexingSpinner)
        #expect(bar.items[0].indexingTooltip == "인덱싱 중 1,284/4,812")
    }

    @Test("인덱스가 최신이면 아무 글리프도 없다")
    func aReadyTabIsQuiet() {
        // 조용한 것이 정상 상태다(W-11).
        let bar = make([tab("repo")])
        #expect(!bar.items[0].showsIndexingSpinner)
        #expect(bar.items[0].indexingTooltip == nil)
    }

    @Test("전체 경로는 탭이 아니라 툴팁에 있다")
    func theFullPathLivesInTheTooltip() {
        let bar = make([tab("repo", path: "/Users/dev/work/repo")])
        #expect(bar.items[0].pathTooltip == "/Users/dev/work/repo")
        #expect(bar.items[0].label == "repo")
    }

    // MARK: 폭과 넘침

    @Test("탭이 적으면 상한 폭에서 멈춘다")
    func fewTabsStopAtTheMaximumWidth() {
        // 220을 넘겨 늘리지 않는다 — 남는 자리는 창 드래그 영역이다(W-11).
        let bar = make([tab("a"), tab("b")], width: 1600)
        #expect(bar.tabWidth == ProjectTabBarPresentation.Metrics.maximumTabWidth)
        #expect(bar.overflowCount == 0)
    }

    @Test("탭이 늘면 남는 폭을 균등 분배한다")
    func manyTabsShareTheWidthEvenly() {
        // 균등 분배가 실제로 걸리려면 몫이 상한(220) 아래여야 한다. 여섯 개는 262가
        // 나와 상한에서 잘리므로 분배를 검증하지 못한다 — 앞 테스트가 그 경우다.
        let tabs = (0..<10).map { tab("p\($0)") }
        let bar = make(tabs, width: 1600)

        let expected = (1600 - ProjectTabBarPresentation.Metrics.addButtonWidth) / 10
        #expect(expected < ProjectTabBarPresentation.Metrics.maximumTabWidth)
        #expect(expected > ProjectTabBarPresentation.Metrics.minimumTabWidth)
        #expect(bar.tabWidth == expected)
        #expect(bar.overflowCount == 0)
    }

    @Test("폭이 모자라면 최소 폭에서 멈추고 넘침을 센다")
    func tabsThatDoNotFitBecomeOverflow() {
        // 112 밑으로는 줄이지 않고 넘침 처리한다(W-11).
        let tabs = (0..<12).map { tab("p\($0)") }
        let bar = make(tabs, width: 800)

        #expect(bar.tabWidth == ProjectTabBarPresentation.Metrics.minimumTabWidth)
        #expect(bar.overflowCount > 0)
        #expect(bar.visibleCount + bar.overflowCount == tabs.count)
    }

    @Test("넘침이 없을 때는 넘침 버튼 폭을 잡아먹지 않는다")
    func theOverflowButtonIsNotReservedWhenUnused() {
        // 항상 예약하면 경계선상의 탭 하나가 밀려나 `≫ 1` 이 뜬다 — 들어갔을 탭이다.
        let width = ProjectTabBarPresentation.Metrics.addButtonWidth
            + ProjectTabBarPresentation.Metrics.minimumTabWidth * 4
        let bar = make((0..<4).map { tab("p\($0)") }, width: width)

        #expect(bar.overflowCount == 0, "딱 맞는 폭인데 넘침으로 셌다")
    }

    @Test("창이 아무리 좁아도 탭 하나는 남는다")
    func atLeastOneTabSurvivesANarrowWindow() {
        // 탭이 0개로 그려지면 열린 프로젝트가 화면에서 사라진다 — §12 판정 1이 막는 것.
        let bar = make((0..<5).map { tab("p\($0)") }, width: 120)
        #expect(bar.visibleCount >= 1)
    }

    @Test("보이는 수와 넘친 수의 합은 언제나 전체다")
    func visibleAndOverflowAlwaysAccountForEveryTab() {
        for count in [1, 3, 8, 20] {
            for width in [CGFloat(320), 800, 1600, 3000] {
                let bar = make((0..<count).map { tab("p\($0)") }, width: width)
                #expect(
                    bar.visibleCount + bar.overflowCount == count,
                    "탭 \(count)개 · 폭 \(width) 에서 합이 안 맞는다"
                )
                #expect(bar.overflowCount >= 0)
            }
        }
    }

    // MARK: 활성 탭은 언제나 보인다 (§5.3, 시니어 리뷰 지적)

    @Test("넘침이 있어도 활성 탭은 보이는 쪽에 있다")
    func theActiveTabIsNeverHiddenInOverflow() {
        // 시니어가 실측한 그 경우: 탭 8개, 활성 = 마지막. 폭 900 에서 딱 하나 넘치는데
        // 그 하나가 하필 활성 탭이었다 — `⌘9` 로 전환하면 화면은 바뀌는데 탭 바에는
        // 선택된 탭이 없다.
        let tabs = (0..<8).map { tab("p\($0)") }

        for width in [CGFloat(400), 600, 900] {
            let bar = make(tabs, active: tabs[7].id, width: width)
            let active = bar.items.first { $0.isActive }

            #expect(active?.isVisible == true, "폭 \(width) 에서 활성 탭이 넘침에 숨었다")
            #expect(bar.visibleItems.contains { $0.isActive }, "폭 \(width)")
        }
    }

    @Test("어떤 탭 수·폭·활성 위치에서도 활성 탭이 보인다")
    func theActiveTabIsVisibleInEveryArrangement() {
        for count in [1, 2, 5, 8, 20] {
            let tabs = (0..<count).map { tab("p\($0)") }
            for width in [CGFloat(200), 400, 800, 1600, 3000] {
                for activeIndex in [0, count / 2, count - 1] {
                    let bar = make(tabs, active: tabs[activeIndex].id, width: width)
                    #expect(
                        bar.visibleItems.contains { $0.isActive },
                        "탭 \(count)개 · 폭 \(width) · 활성 \(activeIndex) 에서 활성 탭이 숨었다"
                    )
                }
            }
        }
    }

    @Test("보이는 항목 수가 visibleCount 와 일치한다")
    func theVisibleItemsMatchTheReportedCount() {
        // 둘이 어긋나면 뷰가 어느 쪽을 믿어야 할지 모른다.
        for count in [1, 6, 15] {
            for width in [CGFloat(300), 900, 2000] {
                let tabs = (0..<count).map { tab("p\($0)") }
                let bar = make(tabs, active: tabs[count - 1].id, width: width)
                #expect(bar.visibleItems.count == bar.visibleCount, "탭 \(count) · 폭 \(width)")
                #expect(bar.overflowItems.count == bar.overflowCount, "탭 \(count) · 폭 \(width)")
            }
        }
    }

    @Test("보이는 탭은 연속 구간이다")
    func theVisibleTabsAreContiguous() {
        // 스크롤되는 바이므로 보이는 것은 한 덩어리여야 한다 — 중간이 빈 채로 앞뒤가
        // 보이는 탭 바는 없다.
        let tabs = (0..<10).map { tab("p\($0)") }
        let bar = make(tabs, active: tabs[9].id, width: 600)

        let visibleIndices = bar.items.enumerated().filter { $0.element.isVisible }.map(\.offset)
        guard let first = visibleIndices.first, let last = visibleIndices.last else {
            Issue.record("보이는 탭이 하나도 없다")
            return
        }
        #expect(visibleIndices.count == last - first + 1, "보이는 구간이 끊겼다: \(visibleIndices)")
    }

    @Test("넘침이 없으면 전부 보인다")
    func withoutOverflowEverythingIsVisible() {
        let bar = make((0..<3).map { tab("p\($0)") }, width: 1600)
        #expect(bar.items.allSatisfy { $0.isVisible })
        #expect(bar.overflowItems.isEmpty)
    }
}
