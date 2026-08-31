import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 비활성 탭의 더티 ● 도 갱신된다 (REQ-012 W-11).
///
/// QA 라이브: `:w` 로 저장했는데 **탭의 ● 이 안 꺼졌다.** 상태바는 깨끗하다고 했다.
/// 5초 뒤에도 그대로 — 지연이 아니다.
///
/// 원인은 경쟁이 아니라 **범위**였다. 재집계가 `tabs.activeTab` **하나만** 갱신해서,
/// 비활성 탭의 값은 그 탭이 마지막으로 활성이었을 때 그대로 얼어붙는다.
///
/// **그게 이 기능이 존재하는 이유를 정면으로 깬다** — 탭의 ● 은 *다른 탭에 있는 동안*
/// 그 프로젝트에 저장 안 한 변경이 있는지 알려 주려고 있는 것이다. 활성 탭은 상태바가
/// 이미 말해 준다.
@MainActor
@Suite("비활성 탭의 더티 표시도 살아 있다 (W-11)")
struct InactiveTabDirtyTests {

    private func status(_ path: String, isDirty: Bool) -> EditorStatus {
        EditorStatus(
            filePath: path, isDirty: isDirty,
            cursorLine: 1, cursorColumn: 1, mode: .normal, inputMode: .vim
        )
    }

    private func makeModel(_ editor: FakeEditorSession) -> AppModel {
        AppModel(
            editorSession: editor,
            workspace: FakeWorkspace(sharedSession: FakeProjectSession()),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
    }

    @Test("🔑 저장하면 비활성 탭의 ● 도 꺼진다")
    func savingClearsTheDotOnAnInactiveTab() async {
        let editor = FakeEditorSession()
        editor.dirtyFilePaths = ["main.swift"]

        let model = makeModel(editor)
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        model.handle(editorStatus: status("/tmp/alpha/main.swift", isDirty: true))
        await model.awaitDirtyRefresh()

        let alpha = model.tabs.activeTab
        #expect(alpha?.dirtyBufferCount == 1, "전제: alpha 가 더럽다")

        // 두 번째 프로젝트로 옮긴다 — alpha 는 이제 비활성이고 ● 을 달고 있다.
        await model.openProject(at: URL(fileURLWithPath: "/tmp/beta"))
        #expect(model.tabs.activeTab?.rootPath == "/tmp/beta", "전제: beta 가 활성이다")
        #expect(alpha?.dirtyBufferCount == 1, "전제: 비활성 alpha 가 아직 ● 을 단다")

        // 저장됐다. 활성 탭은 beta 지만 깨끗해진 것은 alpha 다.
        editor.dirtyFilePaths = []
        model.handle(savedFile: SavedFile(path: "/tmp/alpha/main.swift", lineCount: 2, byteSize: 14))
        await model.awaitDirtyRefresh()

        #expect(alpha?.dirtyBufferCount == 0,
                "비활성 탭의 ● 이 안 꺼진다 — 사용자는 저장이 안 된 줄 안다")
    }

    @Test("탭마다 자기 프로젝트의 더티만 센다")
    func eachTabCountsItsOwnProject() async {
        let editor = FakeEditorSession()
        editor.dirtyFilePaths = ["main.swift"]

        let model = makeModel(editor)
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        await model.openProject(at: URL(fileURLWithPath: "/tmp/beta"))
        model.handle(editorStatus: status("/tmp/beta/main.swift", isDirty: true))
        await model.awaitDirtyRefresh()

        // 페이크는 루트를 안 가리므로 둘 다 1이 된다 — 여기서 재는 것은 **둘 다
        // 갱신됐다**는 것이다. 루트별 필터는 엔진이 하고 그쪽에서 측정된다.
        #expect(model.tabs.tabs.allSatisfy { $0.dirtyBufferCount == 1 },
                "갱신이 활성 탭에만 닿으면 나머지는 0으로 남는다")
        #expect(model.tabs.tabs.count == 2)
    }
}
