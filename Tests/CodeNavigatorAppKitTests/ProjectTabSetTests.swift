import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Tabs as the unit that owns state (ADR-0107, INV-5).
///
/// The invariant these tests exist for is the one INV-5 states and 02b §1.1 turns into a
/// screen contract: what happens in one tab does not change another. The way to keep that
/// promise is not discipline but ownership — a tab's tree and index belong to the tab, so
/// there is no reachable path from one tab to another's state.
@MainActor
@Suite("ProjectTabSet — 탭이 상태의 단위 (REQ-012 AC-2·AC-3·AC-5, INV-5)")
struct ProjectTabSetTests {

    private func makeTab(_ name: String, dirtyBuffers: Int = 0) -> ProjectTab {
        ProjectTab(
            id: "/tmp/\(name)",
            rootPath: "/tmp/\(name)",
            name: name,
            projectSession: FakeProjectSession(),
            editorSession: FakeEditorSession()
        )
    }

    // MARK: INV-5

    @Test("탭마다 자기 트리와 인덱스를 갖는다 — 한쪽을 바꿔도 다른 쪽은 그대로다 (INV-5)")
    func eachTabOwnsItsOwnTreeAndIndex() {
        let set = ProjectTabSet()
        let alpha = makeTab("alpha")
        let beta = makeTab("beta")
        set.open(alpha)
        set.open(beta)

        alpha.setIndexState(.ready)
        beta.setIndexState(.indexing(IndexProgress(completed: 3, total: 10)))

        #expect(alpha.indexState == .ready, "다른 탭의 인덱싱이 이 탭의 상태를 바꿨다")
        #expect(beta.indexState != .ready)
        #expect(alpha.fileTree !== beta.fileTree, "트리를 공유하면 한 탭에서 펼친 폴더가 다른 탭에도 펼쳐진다")
    }

    @Test("탭을 닫아도 남은 탭의 상태는 그대로다 (INV-5, AC-3)")
    func closingATabLeavesTheOthersAlone() {
        let set = ProjectTabSet()
        let alpha = makeTab("alpha")
        let beta = makeTab("beta")
        set.open(alpha)
        set.open(beta)
        alpha.setIndexState(.ready)

        _ = set.close(id: beta.id)

        #expect(set.tabs.count == 1)
        #expect(set.tabs.first === alpha)
        #expect(alpha.indexState == .ready)
    }

    // MARK: AC-5

    @Test("이미 열린 프로젝트를 다시 열면 새 탭 대신 그 탭이 활성화된다 (AC-5)")
    func reopeningAnOpenProjectActivatesItsTab() {
        let set = ProjectTabSet()
        let alpha = makeTab("alpha")
        let beta = makeTab("beta")
        set.open(alpha)
        set.open(beta)
        #expect(set.activeTabID == beta.id)

        let again = makeTab("alpha")
        set.open(again)

        #expect(set.tabs.count == 2, "같은 프로젝트로 탭이 하나 더 생겼다")
        #expect(set.activeTabID == alpha.id)
        #expect(set.tabs.contains { $0 === alpha }, "기존 탭을 버리고 새 인스턴스로 갈아치우면 그 탭의 트리·인덱스가 날아간다")
    }

    // MARK: AC-2

    @Test("전환은 활성 id 하나를 바꾸는 일이다 — 탭 상태는 살아 있다 (AC-2 즉시)")
    func switchingOnlyMovesTheActiveIdentifier() {
        let set = ProjectTabSet()
        let alpha = makeTab("alpha")
        let beta = makeTab("beta")
        set.open(alpha)
        set.open(beta)
        alpha.setIndexState(.ready)

        set.activate(id: alpha.id)

        #expect(set.activeTab === alpha)
        #expect(alpha.indexState == .ready, "전환하며 인덱스를 버리면 AC-2의 '재인덱싱 대기 없이'가 깨진다")
        #expect(set.tabs.count == 2)
    }

    @Test("없는 탭을 활성화하려 하면 활성 탭이 바뀌지 않는다")
    func activatingAnUnknownTabChangesNothing() {
        let set = ProjectTabSet()
        let alpha = makeTab("alpha")
        set.open(alpha)

        set.activate(id: "/tmp/없는프로젝트")

        #expect(set.activeTabID == alpha.id, "활성 탭이 실재하지 않는 id를 가리키면 화면이 빈다")
    }

    // MARK: AC-3

    @Test("활성 탭을 닫으면 이웃이 승계한다 (AC-3)")
    func closingTheActiveTabPromotesANeighbour() {
        let set = ProjectTabSet()
        let tabs = ["a", "b", "c"].map { makeTab($0) }
        tabs.forEach { set.open($0) }
        set.activate(id: tabs[1].id)

        _ = set.close(id: tabs[1].id)

        #expect(set.activeTabID == tabs[2].id, "닫힌 자리로 밀려온 탭이 승계해야 한다")
    }

    @Test("마지막 탭을 닫으면 활성 탭이 없고 웰컴으로 간다 (AC-3, §12 판정 3)")
    func closingTheLastTabReturnsToTheWelcomeScreen() {
        let set = ProjectTabSet()
        let alpha = makeTab("alpha")
        set.open(alpha)

        let showsWelcome = set.close(id: alpha.id)

        #expect(showsWelcome)
        #expect(set.tabs.isEmpty)
        #expect(set.activeTabID == nil)
        #expect(set.activeTab == nil)
    }

    @Test("배경 탭을 닫아도 활성 탭은 그대로다 (AC-3)")
    func closingABackgroundTabDoesNotMoveTheUser() {
        let set = ProjectTabSet()
        let tabs = ["a", "b", "c"].map { makeTab($0) }
        tabs.forEach { set.open($0) }
        set.activate(id: tabs[0].id)

        _ = set.close(id: tabs[2].id)

        #expect(set.activeTabID == tabs[0].id)
    }

    // MARK: 프레젠테이션 입력

    @Test("탭 바에 넘기는 서술자가 각 탭의 실제 상태를 담는다")
    func theDescriptorsCarryEachTabsRealState() {
        // The tab bar draws dirty and indexing glyphs from these. Building them from
        // anything but the tab's own state is how a bar ends up showing the active tab's
        // spinner on every row.
        let set = ProjectTabSet()
        let alpha = makeTab("alpha")
        let beta = makeTab("beta")
        set.open(alpha)
        set.open(beta)
        alpha.setIndexState(.indexing(IndexProgress(completed: 1, total: 4)))
        beta.setIndexState(.ready)
        beta.setDirtyBufferCount(2)

        let descriptors = set.descriptors()

        #expect(descriptors.map(\.id) == [alpha.id, beta.id], "서술자 순서가 탭 순서와 달라지면 화면 순서가 어긋난다")
        #expect(descriptors[0].indexState != .ready)
        #expect(descriptors[0].isDirty == false)
        #expect(descriptors[1].indexState == .ready)
        #expect(descriptors[1].dirtyBufferCount == 2)
    }
}
