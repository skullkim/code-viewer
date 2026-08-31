import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Reopening where the user left off (REQ-012 AC-4·AC-6).
///
/// The user chose to keep every open project in memory, so quitting and relaunching has to
/// bring the same set back — and land on the tab they were actually looking at, not
/// whichever one happened to be restored last.
@MainActor
@Suite("탭 복원 — 열려 있던 탭과 활성 탭이 돌아온다 (REQ-012 AC-4·AC-6)")
struct TabRestoreTests {

    private func makeModel(storage: KeyValueStore) -> (AppModel, FakeWorkspace) {
        let workspace = FakeWorkspace()
        let model = AppModel(
            editorSession: FakeEditorSession(),
            workspace: workspace,
            storage: storage,
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (model, workspace)
    }

    @Test("열려 있던 탭들이 순서대로 돌아온다 (AC-4)")
    func openTabsComeBackInOrder() async {
        let storage = InMemoryKeyValueStore()
        let (first, _) = makeModel(storage: storage)
        await first.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        await first.openProject(at: URL(fileURLWithPath: "/tmp/beta"))

        let (second, _) = makeModel(storage: storage)
        await second.restoreTabs()

        #expect(second.tabs.tabs.map(\.name) == ["alpha", "beta"])
    }

    @Test("종료할 때 보고 있던 탭이 활성으로 돌아온다 (AC-4)")
    func theTabTheUserWasLookingAtComesBackActive() async {
        // Without this the last-restored project wins, which is wherever the loop happened
        // to end — not where the user was.
        let storage = InMemoryKeyValueStore()
        let (first, _) = makeModel(storage: storage)
        await first.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        await first.openProject(at: URL(fileURLWithPath: "/tmp/beta"))
        await first.activateTab(first.tabs.tabs[0].id)

        let (second, _) = makeModel(storage: storage)
        await second.restoreTabs()

        #expect(second.tabs.activeTab?.name == "alpha", "사용자가 있던 탭이 아니라 마지막에 복원된 탭이 떴다")
    }

    @Test("닫은 탭은 돌아오지 않는다")
    func aClosedTabDoesNotComeBack() async {
        let storage = InMemoryKeyValueStore()
        let (first, _) = makeModel(storage: storage)
        await first.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        await first.openProject(at: URL(fileURLWithPath: "/tmp/beta"))
        await first.closeTab(first.tabs.activeTab!.id)

        let (second, _) = makeModel(storage: storage)
        await second.restoreTabs()

        #expect(second.tabs.tabs.map(\.name) == ["alpha"])
    }

    @Test("첫 실행에는 복원할 것이 없다")
    func aFirstRunHasNothingToRestore() async {
        let (model, workspace) = makeModel(storage: InMemoryKeyValueStore())

        await model.restoreTabs()

        #expect(model.tabs.tabs.isEmpty)
        // Asserting the call never happened, not merely that nothing came back: an engine
        // asked to restore an empty list may still spin up a session for a window that is
        // about to show the welcome screen.
        #expect(workspace.restoreCallCount == 0, "복원할 게 없는데 엔진을 불렀다")
    }

    @Test("사라진 프로젝트는 조용히 버리지 않고 알린다 (AC-6)")
    func aProjectThatIsGoneIsReportedRatherThanDropped() async {
        // Silently dropping it is indistinguishable from the application forgetting, and
        // the user cannot tell whether their project moved or the app lost it.
        let storage = InMemoryKeyValueStore()
        let (first, _) = makeModel(storage: storage)
        await first.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))

        let (second, workspace) = makeModel(storage: storage)
        workspace.missingRoots = ["/tmp/alpha"]
        await second.restoreTabs()

        #expect(second.tabs.tabs.isEmpty)
        #expect(second.missingTabs.map(\.rootPath.path) == ["/tmp/alpha"])
    }

    @Test("활성이던 탭이 사라졌으면 살아남은 첫 탭이 활성이 된다")
    func whenTheActiveTabIsGoneASurvivorTakesOver() async {
        // Otherwise the window has a tab bar with nothing under it: the active identifier
        // points at a project that did not come back.
        //
        // Ported from the app-side restore planner being retired — its implementation was a
        // duplicate of the engine's, but this case was not covered on this side.
        let storage = InMemoryKeyValueStore()
        let (first, _) = makeModel(storage: storage)
        await first.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        await first.openProject(at: URL(fileURLWithPath: "/tmp/beta"))
        await first.activateTab(first.tabs.tabs[1].id)

        let (second, workspace) = makeModel(storage: storage)
        workspace.missingRoots = ["/tmp/beta"]
        await second.restoreTabs()

        #expect(second.tabs.activeTab?.name == "alpha", "활성 탭이 사라졌는데 아무 데도 안 갔다")
        #expect(second.missingTabs.count == 1)
    }

    @Test("전부 실패한 것과 첫 실행은 구별된다")
    func aTotalFailureIsNotTheSameAsAFirstRun() async {
        // Both end on the welcome screen, which makes them easy to collapse — and collapsing
        // them loses the sheet, which is all of AC-6.
        let firstRunStorage = InMemoryKeyValueStore()
        let (firstRun, _) = makeModel(storage: firstRunStorage)
        await firstRun.restoreTabs()

        let storage = InMemoryKeyValueStore()
        let (before, _) = makeModel(storage: storage)
        await before.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        let (after, workspace) = makeModel(storage: storage)
        workspace.missingRoots = ["/tmp/alpha"]
        await after.restoreTabs()

        #expect(firstRun.tabs.tabs.isEmpty && after.tabs.tabs.isEmpty, "둘 다 웰컴 화면이다")
        #expect(firstRun.missingTabs.isEmpty, "첫 실행에는 알릴 것이 없다")
        #expect(after.missingTabs.isEmpty == false, "전부 실패했는데 아무 말도 안 한다")
    }

    @Test("복원된 것과 빠진 것의 합은 저장된 수와 같다")
    func nothingVanishesBetweenSavedAndReported() async {
        // The invariant that makes "silently dropped" impossible: every saved tab comes back
        // either as a tab or as a line in the sheet.
        let storage = InMemoryKeyValueStore()
        let (first, _) = makeModel(storage: storage)
        for name in ["alpha", "beta", "gamma"] {
            await first.openProject(at: URL(fileURLWithPath: "/tmp/\(name)"))
        }

        let (second, workspace) = makeModel(storage: storage)
        workspace.missingRoots = ["/tmp/beta"]
        await second.restoreTabs()

        #expect(second.tabs.tabs.count + second.missingTabs.count == 3)
    }

    @Test("복원 실패 사유가 보존된다 — 옮겨진 것과 권한 없는 것은 다르다")
    func theReasonForEachMissingTabSurvives() async {
        let storage = InMemoryKeyValueStore()
        let (first, _) = makeModel(storage: storage)
        await first.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))

        let (second, workspace) = makeModel(storage: storage)
        workspace.missingRoots = ["/tmp/alpha"]
        workspace.missingReason = .noPermission
        await second.restoreTabs()

        #expect(second.missingTabs.first?.reason == .noPermission, "사용자가 할 수 있는 일이 사유마다 다르다")
    }
}
