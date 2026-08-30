import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// REQ-012 AC-2 · AC-3 and design 02b §4.1.
///
/// The rule that costs work if it is wrong is closing: `⌘W` closes a *tab* now (§12 ruling
/// 3), so a user reaching for it must never lose the window — and closing the last tab has
/// to land somewhere with a way back, not on an empty window.
@Suite("ProjectTabCommand — 탭 선택과 닫기 (REQ-012 AC-2·AC-3)")
struct ProjectTabCommandTests {

    private func tabs(_ count: Int) -> [ProjectTabDescriptor] {
        (0..<count).map {
            ProjectTabDescriptor(id: "t\($0)", rootPath: "/repo/p\($0)", name: "p\($0)")
        }
    }

    private func action(
        _ key: ProjectTabKey,
        _ list: [ProjectTabDescriptor],
        active: String?
    ) -> ProjectTabAction {
        ProjectTabCommand.action(for: key, tabs: list, activeTabID: active)
    }

    // MARK: 전환

    @Test("⇧⌘] 는 다음 탭으로 간다")
    func nextMovesForward() {
        let list = tabs(3)
        #expect(action(.next, list, active: "t0") == .activate(tabID: "t1"))
    }

    @Test("⇧⌘[ 는 이전 탭으로 간다")
    func previousMovesBack() {
        let list = tabs(3)
        #expect(action(.previous, list, active: "t2") == .activate(tabID: "t1"))
    }

    @Test("양 끝에서 순환한다")
    func cyclingWrapsAtBothEnds() {
        // 탭 몇 개짜리에서 끝에 멈추면 키가 고장 난 것처럼 느껴진다 — Safari 도 순환한다.
        let list = tabs(3)
        #expect(action(.next, list, active: "t2") == .activate(tabID: "t0"))
        #expect(action(.previous, list, active: "t0") == .activate(tabID: "t2"))
    }

    @Test("활성 탭을 모르면 첫 탭을 고른다")
    func noActiveTabFallsBackToTheFirst() {
        #expect(action(.next, tabs(3), active: nil) == .activate(tabID: "t0"))
    }

    @Test("탭이 없으면 어떤 키도 아무 일을 하지 않는다")
    func noTabsMeansNoAction() {
        let keys: [ProjectTabKey] = [.next, .previous, .index(1), .closeActive]
        for key in keys {
            #expect(action(key, [], active: nil) == .none, "\(key)")
        }
    }

    // MARK: ⌘1~⌘9

    @Test("⌘1~⌘8 은 그 자리의 탭을 고른다")
    func theNumberKeysSelectByPosition() {
        let list = tabs(8)
        #expect(action(.index(1), list, active: "t0") == .activate(tabID: "t0"))
        #expect(action(.index(4), list, active: "t0") == .activate(tabID: "t3"))
        #expect(action(.index(8), list, active: "t0") == .activate(tabID: "t7"))
    }

    @Test("⌘9 는 아홉 번째가 아니라 마지막 탭이다")
    func theNinthShortcutMeansTheLastTab() {
        // Safari·Finder·Terminal 이 그렇게 한다 — 02b 가 다른 결정에서 근거로 삼은 바로
        // 그 관례다. 아홉 번째로 두면 프로젝트를 아홉 개 열기 전까지 죽은 키가 된다.
        #expect(action(.index(9), tabs(3), active: "t0") == .activate(tabID: "t2"))
        #expect(action(.index(9), tabs(12), active: "t0") == .activate(tabID: "t11"))
    }

    @Test("빈 자리를 가리키는 번호는 아무 일도 하지 않는다")
    func anEmptyPositionDoesNothing() {
        #expect(action(.index(5), tabs(3), active: "t0") == .none)
    }

    @Test("범위 밖 번호는 무시한다")
    func outOfRangeNumbersAreIgnored() {
        for position in [0, -1, 10, 99] {
            #expect(action(.index(position), tabs(3), active: "t0") == .none, "\(position)")
        }
    }

    // MARK: 닫기 요청

    @Test("⌘W 는 활성 탭 닫기를 요청한다")
    func closeAsksAboutTheActiveTab() {
        // 지시가 아니라 요청이다 — 저장 안 한 변경이 있으면 W-13 시트가 먼저 뜬다.
        #expect(action(.closeActive, tabs(3), active: "t1") == .requestClose(tabID: "t1"))
    }

    @Test("활성 탭이 목록에 없으면 닫기 요청을 만들지 않는다")
    func aStaleActiveIDClosesNothing() {
        #expect(action(.closeActive, tabs(3), active: "gone") == .none)
    }

    // MARK: 닫은 뒤

    @Test("활성 탭을 닫으면 오른쪽 탭이 활성이 된다")
    func closingTheActiveTabSelectsTheOneAfterIt() {
        let result = ProjectTabCommand.closing(tabID: "t1", tabs: tabs(3), activeTabID: "t1")
        #expect(result.activeTabID == "t2")
        #expect(result.remaining.map(\.id) == ["t0", "t2"])
        #expect(!result.showsWelcome)
    }

    @Test("마지막 자리의 활성 탭을 닫으면 왼쪽이 활성이 된다")
    func closingTheLastPositionFallsBackLeft() {
        let result = ProjectTabCommand.closing(tabID: "t2", tabs: tabs(3), activeTabID: "t2")
        #expect(result.activeTabID == "t1")
    }

    @Test("배경 탭을 닫아도 보고 있던 탭은 그대로다")
    func closingABackgroundTabDoesNotMoveTheUser() {
        let result = ProjectTabCommand.closing(tabID: "t0", tabs: tabs(3), activeTabID: "t2")
        #expect(result.activeTabID == "t2")
        #expect(result.remaining.map(\.id) == ["t1", "t2"])
    }

    @Test("마지막 탭을 닫으면 웰컴 화면으로 돌아간다")
    func closingTheLastTabReturnsToWelcome() {
        // §12 판정 3. 빈 창을 남기면 돌아갈 길이 화면에 없다.
        let result = ProjectTabCommand.closing(tabID: "t0", tabs: tabs(1), activeTabID: "t0")
        #expect(result.remaining.isEmpty)
        #expect(result.activeTabID == nil)
        #expect(result.showsWelcome)
    }

    @Test("없는 탭을 닫으라고 하면 아무것도 바뀌지 않는다")
    func closingAnUnknownTabChangesNothing() {
        let list = tabs(3)
        let result = ProjectTabCommand.closing(tabID: "nope", tabs: list, activeTabID: "t1")
        #expect(result.remaining.map(\.id) == list.map(\.id))
        #expect(result.activeTabID == "t1")
        #expect(!result.showsWelcome)
    }

    @Test("어느 탭을 닫아도 활성 탭은 남아 있는 탭 중 하나다")
    func theActiveTabAlwaysExistsAfterAClose() {
        // 활성 ID 가 사라진 탭을 가리키면 화면이 빈 채로 남는다.
        let list = tabs(4)
        for closing in list {
            for active in list {
                let result = ProjectTabCommand.closing(
                    tabID: closing.id, tabs: list, activeTabID: active.id
                )
                guard !result.showsWelcome else { continue }
                #expect(
                    result.remaining.contains { $0.id == result.activeTabID },
                    "\(closing.id) 를 닫고 \(active.id) 가 활성일 때 활성 탭이 사라졌다"
                )
            }
        }
    }
}
