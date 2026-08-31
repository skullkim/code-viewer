import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 탭의 더티 `●` (REQ-012, 02b W-11).
///
/// **데이터는 있었고 아무도 채우지 않았다.** `ProjectTabState.setDirtyBufferCount` 는 정의만
/// 되고 **호출부가 0건**이었다 — `isDirty` 가 영원히 false 라 탭 바는 점을 그릴 기회가 없었다.
/// 뷰는 처음부터 옳게 그리고 있었다.
///
/// 왜 인증 전에 고치나: 사용자 문장이 *"탭 단위로 보고 싶어"* 였고, **미저장 여부는 탭 단위로
/// 알아야 하는 첫 번째 정보**다. 탭을 떠나면 그 프로젝트에 저장 안 한 변경이 있는지 알
/// 방법이 없다. W-13 이 닫을 때 시트로 손실은 막지만, **막는 것과 보이는 것은 다르다.**
@MainActor
@Suite("탭이 미저장 변경을 표시한다 (REQ-012, W-11)")
struct TabDirtyIndicatorTests {

    private func makeModel(_ editor: FakeEditorSession) -> AppModel {
        AppModel(
            editorSession: editor,
            workspace: FakeWorkspace(sharedSession: FakeProjectSession()),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
    }

    private func status(isDirty: Bool) -> EditorStatus {
        EditorStatus(
            filePath: "/tmp/alpha/src/main.swift",
            isDirty: isDirty,
            cursorLine: 1,
            cursorColumn: 1,
            mode: .normal,
            inputMode: .vim
        )
    }

    @Test("버퍼가 더러워지면 활성 탭이 그것을 안다")
    func theActiveTabLearnsAboutUnsavedWork() async {
        let editor = FakeEditorSession()
        editor.dirtyFilePaths = ["src/main.swift"]

        let model = makeModel(editor)
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        #expect(model.tabs.activeTab?.dirtyBufferCount == 0, "전제: 아직 깨끗하다")

        model.handle(editorStatus: status(isDirty: true))
        await model.awaitDirtyRefresh()

        #expect(model.tabs.activeTab?.dirtyBufferCount == 1,
                "탭이 미저장 변경을 모르면 ● 을 그릴 수 없다")
        #expect(model.tabs.activeTab?.descriptor.isDirty == true)
    }

    @Test("전부 저장하면 탭에서 점이 사라진다")
    func savingClearsTheDot() async {
        let editor = FakeEditorSession()
        editor.dirtyFilePaths = ["src/main.swift"]

        let model = makeModel(editor)
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        model.handle(editorStatus: status(isDirty: true))
        await model.awaitDirtyRefresh()
        #expect(model.tabs.activeTab?.dirtyBufferCount == 1, "전제: 더티 상태를 만들었다")

        // 저장됐다. 점이 남아 있으면 사용자는 저장이 안 된 줄 안다 — 반대 방향의
        // 거짓말도 똑같이 나쁘다.
        editor.dirtyFilePaths = []
        model.handle(editorStatus: status(isDirty: false))
        await model.awaitDirtyRefresh()

        #expect(model.tabs.activeTab?.dirtyBufferCount == 0)
        #expect(model.tabs.activeTab?.descriptor.isDirty == false)
    }

    @Test("탭 바와 상태바가 같은 순간에 같은 답을 한다")
    func theTabBarAndTheStatusBarAgree() async {
        // 두 곳이 각자 판단하면 한쪽만 점을 그린다 — QA 가 본 것이 정확히 그 모양이었다
        // (상태바는 ● 인데 탭 바는 아니었다).
        let editor = FakeEditorSession()
        editor.dirtyFilePaths = ["src/main.swift"]

        let model = makeModel(editor)
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        model.handle(editorStatus: status(isDirty: true))
        await model.awaitDirtyRefresh()

        let statusBarSaysDirty = model.editorStatus?.isDirty == true
        let tabSaysDirty = model.tabs.activeTab?.descriptor.isDirty == true
        #expect(statusBarSaysDirty == tabSaysDirty,
                "상태바 \(statusBarSaysDirty) · 탭 \(tabSaysDirty) — 한 화면이 두 답을 낸다")
    }
}
