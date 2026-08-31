import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 탭 목록의 단일 소스 (REQ-012).
///
/// 목록이 두 벌 있다 — 엔진의 `tabs()` 와 앱의 `ProjectTabSet`. **앱은 `tabs()` 를 한 번도
/// 부르지 않는다.** 두 목록을 맞춰 주는 코드도 없다. 그래서 물어야 할 것은 "지금 같은가"가
/// 아니라 **"갈라질 수 있는가"** 다.
///
/// 갈라지면 결과가 조용하다: 엔진이 든 탭은 세션을 쥐고 배경에서 인덱싱하는데, 화면에
/// 없으니 **사용자는 그것을 보지도 닫지도 못한다.**
@MainActor
@Suite("탭 목록이 갈라지지 않는다 (REQ-012 — 단일 소스)")
struct TabListSingleSourceTests {

    private func makeModel(_ workspace: FakeWorkspace) -> AppModel {
        AppModel(
            editorSession: FakeEditorSession(),
            workspace: workspace,
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
    }

    @Test("복원한 탭이 앱 목록에서 조용히 사라지지 않는다")
    func aRestoredTabIsNeverSilentlyDropped() async {
        let workspace = FakeWorkspace()
        // 엔진은 둘 다 복원한다. 그런데 하나는 세션 조회가 nil 을 준다.
        workspace.sessionlessRoots = ["/tmp/beta"]

        let model = makeModel(workspace)
        model.shell.setOpenTabs(rootPaths: ["/tmp/alpha", "/tmp/beta"], activeRootPath: "/tmp/alpha")
        await model.restoreTabs()

        let engineTabs = await workspace.tabs()
        let appTabs = model.tabs.tabs.count
        let reportedMissing = model.missingTabs.count

        // 두 가지를 따로 단언한다 — 한 식으로 묶었더니 **고친 뒤에도 빨간불**이었다.
        // 나쁜 탭을 엔진에서 닫았으니 엔진 수가 줄어드는 게 맞는데, 내 첫 식은 그걸
        // 결함으로 읽었다. 재려던 성질이 둘이었는데 하나로 적은 것이다.

        // ① 두 목록이 같다 — 화면에 없는데 엔진이 든 탭이 없다.
        #expect(appTabs == engineTabs.count,
                "앱 \(appTabs)개 · 엔진 \(engineTabs.count)개 — 화면에 없는 탭이 세션을 쥐고 있다")

        // ② 요청한 것은 전부 열렸거나 **못 열었다고 말해졌다.** 조용히 빠진 것이 없다.
        #expect(appTabs + reportedMissing == 2,
                "요청 2개 · 열림 \(appTabs)개 · 못 열었다고 보고 \(reportedMissing)개 — 합이 2가 아니면 조용히 사라진 탭이 있다")
    }

    @Test("프로젝트 열기가 실패로 끝나면 엔진에도 탭이 남지 않는다")
    func aFailedOpenLeavesNoOrphanInTheEngine() async {
        let workspace = FakeWorkspace()
        workspace.sessionlessRoots = ["/tmp/gamma"]

        let model = makeModel(workspace)
        await model.openProject(at: URL(fileURLWithPath: "/tmp/gamma"))

        let engineTabs = await workspace.tabs()

        // 앱은 오류를 띄우고 탭을 안 만든다. 엔진이 그 탭을 들고 있으면 **화면에 없는 탭이
        // 세션을 쥔 채 남는다** — 사용자가 닫을 방법이 없다.
        #expect(model.tabs.tabs.isEmpty, "이 테스트의 전제: 앱은 탭을 만들지 않았다")
        #expect(engineTabs.isEmpty,
                "앱은 실패로 끝났는데 엔진에 탭 \(engineTabs.count)개가 남았다 — 화면에 없는 탭이 세션을 쥐고 있다")
    }
}
