import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Opening a project produces a tab (REQ-012 AC-1, ADR-0107).
///
/// The tab bar is the only place the open project's name appears now that the toolbar's
/// project popup is gone (02b C-1, §12 ruling 1), so a project that is open without a tab
/// is a project the user cannot see they have.
///
/// **What these tests deliberately do not claim**: that two projects can be open at once.
/// The engine still exposes a single `ProjectSession` with no `ProjectOpenOutcome`, so
/// AC-2's instant switching and INV-5's isolation cannot hold yet. Asserting them here
/// would record a requirement as met because the shell can hold two entries, which is the
/// "존재≠동작" shape this build has met seven times.
@MainActor
@Suite("AppModel 탭 — 프로젝트를 열면 탭이 생긴다 (REQ-012 AC-1)")
struct AppModelTabTests {

    private func makeModel() -> (AppModel, RecordingWorkspace) {
        let workspace = RecordingWorkspace()
        let model = AppModel(
            projectSession: FakeProjectSession(),
            editorSession: FakeEditorSession(),
            workspace: workspace,
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (model, workspace)
    }

    @Test("프로젝트를 열면 탭이 하나 생기고 활성이 된다")
    func openingAProjectCreatesAnActiveTab() async {
        let (model, _) = makeModel()

        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))

        #expect(model.tabs.tabs.count == 1)
        #expect(model.tabs.activeTab?.name == "alpha")
        #expect(model.tabs.activeTab?.rootPath == "/tmp/alpha")
    }

    @Test("여는 데 실패하면 탭이 생기지 않는다 (REQ-001 AC-3)")
    func aFailedOpenLeavesNoTab() async {
        // The failure path already promises nothing about the open project changes. A tab
        // for a project that did not open would be a row pointing at nothing.
        let (model, workspace) = makeModel()
        workspace.openError = NavigatorError.projectNotFound(path: "/tmp/missing")

        await model.openProject(at: URL(fileURLWithPath: "/tmp/missing"))

        #expect(model.tabs.tabs.isEmpty)
        #expect(model.tabs.activeTab == nil)
    }

    @Test("같은 프로젝트를 다시 열어도 탭이 하나다 (REQ-012 AC-5)")
    func reopeningTheSameProjectDoesNotAddATab() async {
        let (model, _) = makeModel()

        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))

        #expect(model.tabs.tabs.count == 1)
    }

    @Test("탭을 닫으면 웰컴으로 돌아간다 (REQ-012 AC-3, §12 판정 3)")
    func closingTheOnlyTabReturnsToTheWelcomeScreen() async {
        let (model, _) = makeModel()
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))

        await model.closeProject()

        #expect(model.tabs.tabs.isEmpty)
        #expect(model.projectRootPath == nil, "탭은 닫혔는데 프로젝트가 열린 채로 남았다")
    }

    @Test("탭이 하나여도 탭 바가 보인다 (§12 판정 1)")
    func theBarIsVisibleWithASingleTab() async {
        // The toolbar's project popup was removed (02b C-1), so hiding the bar at one tab
        // would leave the open project's name nowhere on screen. Convention says hide it;
        // this design says the information matters more.
        let (model, _) = makeModel()
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))

        let bar = ProjectTabBarPresentation.make(
            tabs: model.tabs.descriptors(),
            activeTabID: model.tabs.activeTabID,
            barWidth: 1280
        )
        #expect(bar.isVisible)
        #expect(bar.items.count == 1)
        #expect(bar.items.first?.isActive == true)
    }

    @Test("프로젝트가 없으면 탭 바가 없다")
    func thereIsNoBarWithoutAProject() {
        let (model, _) = makeModel()
        let bar = ProjectTabBarPresentation.make(
            tabs: model.tabs.descriptors(),
            activeTabID: nil,
            barWidth: 1280
        )
        #expect(bar.isVisible == false)
    }

    @Test("탭 서술자가 인덱스 상태를 실제로 반영한다")
    func theTabDescriptorCarriesTheLiveIndexState() async {
        // The bar draws its spinner from this. Building it from anything but the model's
        // own state is how a bar ends up showing a spinner that never stops.
        let (model, _) = makeModel()
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))

        model.handle(indexState: .indexing(IndexProgress(completed: 2, total: 9)))
        #expect(model.tabs.descriptors().first?.indexState != .ready)

        model.handle(indexState: .ready)
        #expect(model.tabs.descriptors().first?.indexState == .ready)
    }
}
