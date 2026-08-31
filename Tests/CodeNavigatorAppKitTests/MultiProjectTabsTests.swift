import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Several projects open at once (REQ-012 AC-1·AC-2·AC-5, INV-5).
///
/// This is the requirement the user asked for in their own words — 여러 프로젝트 동시에
/// 키고, 탭 단위로 보고 싶어 — and until the engine grew per-project sessions the shell
/// could hold two entries while the engine held one index, so opening a second project
/// replaced the first. These tests exist to make that impossible to reintroduce.
@MainActor
@Suite("다중 프로젝트 탭 — 동시에 열고 즉시 전환한다 (REQ-012)")
struct MultiProjectTabsTests {

    private func makeModel() -> (AppModel, FakeWorkspace) {
        let workspace = FakeWorkspace()
        let model = AppModel(
            editorSession: FakeEditorSession(),
            workspace: workspace,
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (model, workspace)
    }

    @Test("두 프로젝트를 동시에 열면 탭이 둘이다 (AC-1)")
    func twoProjectsAreOpenAtOnce() async {
        let (model, _) = makeModel()

        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        await model.openProject(at: URL(fileURLWithPath: "/tmp/beta"))

        #expect(model.tabs.tabs.count == 2, "두 번째가 첫 번째를 대체하면 사용자가 요청한 기능이 아니다")
        #expect(model.tabs.tabs.map(\.name) == ["alpha", "beta"])
        #expect(model.tabs.activeTab?.name == "beta")
    }

    @Test("각 탭이 자기 세션을 갖는다 — INV-5 가 구조로 선다")
    func eachTabHoldsItsOwnSession() async {
        // Isolation stops being a rule someone has to follow: a tab literally cannot reach
        // another's index, because it does not have a reference to it.
        let (model, _) = makeModel()
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        await model.openProject(at: URL(fileURLWithPath: "/tmp/beta"))

        let sessions = model.tabs.tabs.map { ObjectIdentifier($0.fileTree) }
        #expect(Set(sessions).count == 2, "탭이 트리를 공유하면 한쪽에서 펼친 폴더가 다른 쪽에도 펼쳐진다")
    }

    @Test("전환은 엔진에게도 알린다 — 활성 탭의 주인은 하나다")
    func switchingTellsTheEngine() async {
        // The engine owns which project is active and the bar displays that. Changing only
        // the app's copy would give the same fact two owners, and the day they disagree the
        // screen shows one project while every query answers about another.
        //
        // Found by removing the engine call and watching this suite stay green.
        let (model, workspace) = makeModel()
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        let alpha = model.tabs.tabs[0]
        await model.openProject(at: URL(fileURLWithPath: "/tmp/beta"))

        await model.activateTab(alpha.id)

        #expect(workspace.activatedTabs.contains(alpha.id), "앱만 전환하고 엔진은 모른다")
        let engineActive = await workspace.activeTab()
        #expect(engineActive?.id == alpha.id)
    }

    @Test("탭을 전환해도 다른 탭의 인덱스가 살아 있다 (AC-2 즉시 전환)")
    func switchingKeepsTheOtherIndexAlive() async {
        // The whole reason the user chose "keep everything in memory": switching must not
        // wait for a re-index.
        let (model, _) = makeModel()
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        let alpha = model.tabs.tabs[0]
        await model.openProject(at: URL(fileURLWithPath: "/tmp/beta"))
        // Set after the second open, so this is not racing the tab's own subscription —
        // the point is that the value survives a switch, not who wrote it.
        alpha.setIndexState(.ready)

        await model.activateTab(alpha.id)

        #expect(model.tabs.activeTab === alpha)
        #expect(alpha.indexState == .ready, "전환하며 인덱스를 버리면 AC-2 가 깨진다")
        #expect(model.tabs.tabs.count == 2)
    }

    @Test("이미 열린 프로젝트를 다시 열면 그 탭이 활성화된다 (AC-5)")
    func reopeningActivatesTheExistingTab() async {
        let (model, workspace) = makeModel()
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        await model.openProject(at: URL(fileURLWithPath: "/tmp/beta"))

        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))

        #expect(model.tabs.tabs.count == 2, "같은 프로젝트로 탭이 하나 더 생겼다")
        #expect(model.tabs.activeTab?.name == "alpha")
        #expect(workspace.openCallCount == 3, "판정은 엔진이 한다 — 앱이 미리 거르면 정규화가 두 벌이 된다")
    }

    @Test("탭을 닫으면 엔진에서도 닫힌다 (AC-3)")
    func closingATabReleasesItInTheEngine() async {
        let (model, workspace) = makeModel()
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        await model.openProject(at: URL(fileURLWithPath: "/tmp/beta"))
        let beta = model.tabs.activeTab!

        await model.closeTab(beta.id)

        #expect(model.tabs.tabs.count == 1)
        #expect(workspace.closedTabs == [beta.id], "앱에서만 지우면 엔진의 인덱스가 남는다")
        #expect(model.tabs.activeTab?.name == "alpha")
    }

    @Test("마지막 탭을 닫으면 웰컴으로 돌아간다 (§12 판정 3)")
    func closingTheLastTabReturnsToWelcome() async {
        let (model, _) = makeModel()
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))

        await model.closeTab(model.tabs.activeTabID!)

        #expect(model.tabs.tabs.isEmpty)
        #expect(model.projectRootPath == nil)
    }

    @Test("열기에 실패하면 탭이 생기지 않는다 (REQ-001 AC-3)")
    func aFailedOpenAddsNoTab() async {
        let (model, workspace) = makeModel()
        workspace.openError = NavigatorError.projectNotFound(path: "/tmp/missing")

        await model.openProject(at: URL(fileURLWithPath: "/tmp/missing"))

        #expect(model.tabs.tabs.isEmpty)
        #expect(model.projectOpenError != nil)
    }
}
