import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 에디터가 말하는 파일을 렌더 모델에 넘기는 자리 (REQ-013, D-렌더).
///
/// **에디터는 절대 경로로 말하고 엔진의 문은 상대 경로를 받는다.** 그 사이에 변환이 없으면
/// 렌더는 한 번도 성공하지 못한다 — 그런데 오류 문구가 *"잘못된 경로입니다"* 라서, 화면은
/// **경로가 이상한 파일**을 말하는 것처럼 보인다. 실제로는 모든 파일이 그렇게 된다.
@MainActor
@Suite("렌더 문서 동기화 — 절대 경로를 상대 경로 문에 넣지 않는다 (REQ-013)")
struct RenderDocumentSyncTests {

    private let root = "/Users/dev/repo"

    private func makeModel() -> (AppModel, FakeWorkspace) {
        let workspace = FakeWorkspace(sharedSession: FakeProjectSession())
        let model = AppModel(
            editorSession: FakeEditorSession(),
            workspace: workspace,
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) },
            // 합성 루트가 주입하는 것과 **같은 것**을 넣는다. 기본값은 `{ _ in false }` 라
            // 안 넣으면 아무것도 렌더 가능하지 않고, 이 스위트는 렌더가 꺼진 상태만 재게 된다.
            isRenderableDocument: RenderableDocument.isRenderable(relativePath:)
        )
        return (model, workspace)
    }

    /// 렌더 보기가 켜진 상태를 만든다.
    private func showingRender(_ model: AppModel, absolutePath: String) async {
        await model.openProject(at: URL(fileURLWithPath: root))
        model.handle(editorStatus: EditorStatus(
            filePath: absolutePath, isDirty: false, cursorLine: 1, cursorColumn: 1,
            mode: .normal, inputMode: .vim
        ))
        // 렌더 가능한 파일은 기본이 렌더 보기다(`mode(forPath:)`). 토글하면 오히려 꺼진다.
        model.syncRenderDocument()
    }

    @Test("렌더 가능 판정을 주입하지 않아도 진짜 판정이 쓰인다")
    func theDefaultPredicateIsTheRealOne() async {
        // 예전 기본값은 `{ _ in false }` 였다. 중립처럼 보이지만 **하나의 행동**이고,
        // 하필 모든 렌더 검사를 무의미하게 만드는 행동이다 — 주입을 잊은 테스트는
        // "렌더 꺼짐" 경로만 재면서 초록이 된다. 잊었을 때 **정상 동작**하는 쪽으로 뒤집었고,
        // 이 테스트가 그 방향을 고정한다.
        let model = AppModel(
            editorSession: FakeEditorSession(),
            workspace: FakeWorkspace(sharedSession: FakeProjectSession()),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
            // isRenderableDocument 를 **일부러 안 넣는다**
        )
        await model.openProject(at: URL(fileURLWithPath: root))
        model.handle(editorStatus: EditorStatus(
            filePath: "\(root)/README.md", isDirty: false, cursorLine: 1, cursorColumn: 1,
            mode: .normal, inputMode: .vim
        ))

        #expect(model.renderViewState.isRenderable, "기본값이 렌더를 꺼 버린다")
    }

    @Test("절대 경로가 루트 기준 상대 경로로 바뀌어 넘어간다")
    func anAbsolutePathIsConvertedBeforeItReachesTheEngine() async {
        // 엔진의 문은 상대 경로를 받는다(`renderSource(atRelativePath:in:)`). 절대 경로를
        // 그대로 넣으면 엔진이 거절하고, 그 거절이 **모든 파일에** 일어난다.
        let (model, _) = makeModel()

        await showingRender(model, absolutePath: "\(root)/docs/README.md")

        #expect(model.render.documentRelativePath == "docs/README.md")
    }

    @Test("루트 바로 아래 파일도 마찬가지다")
    func aFileAtTheRootIsConvertedToo() async {
        let (model, _) = makeModel()

        await showingRender(model, absolutePath: "\(root)/README.md")

        #expect(model.render.documentRelativePath == "README.md")
    }

    @Test("루트 밖 파일은 넘기지 않는다 — 그때의 '잘못된 경로'는 옳은 문구다")
    func aFileOutsideTheRootIsRefusedRatherThanPassedThrough() async {
        // `:e ~/notes.md` 로 루트 밖 파일을 열 수 있다. **렌더 가능한 확장자**여야 한다 —
        // 아니면 렌더 보기 자체가 안 켜져서 이 분기에 닿지도 않는다. 렌더 표면은 프로젝트 안만 그린다
        // (INV-6). **고치다가 여기를 열면 샌드박스가 열린다.**
        let (model, _) = makeModel()

        await showingRender(model, absolutePath: "/etc/notes.md")

        #expect(model.render.documentRelativePath == nil, "루트 밖 경로가 그대로 넘어갔다")
        // 조용히 비우면 사용자는 문서가 빈 줄 안다.
        if case .failed = model.render.phase {} else {
            Issue.record("루트 밖 파일인데 실패로 말하지 않는다: \(model.render.phase)")
        }
    }

    @Test("루트 밖과 루트 안이 다른 결과를 낸다")
    func insideAndOutsideTheRootDoNotLookAlike() async {
        // 지금은 **모든** 파일이 "잘못된 경로"라서 옳은 문구가 무의미해졌다. 두 경우가
        // 구별되는지를 직접 잰다 — 하나만 보면 둘 다 실패하는 상태를 통과시킨다.
        let (inside, _) = makeModel()
        await showingRender(inside, absolutePath: "\(root)/docs/README.md")

        let (outside, _) = makeModel()
        await showingRender(outside, absolutePath: "/etc/notes.md")

        #expect(inside.render.documentRelativePath != outside.render.documentRelativePath)
    }
}
