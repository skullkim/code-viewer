import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// What happens when the cursor is not on a symbol (REQ-015 AC-5).
///
/// AC-5 asks for something narrower than "do not crash": **say why**. Silence and an empty
/// result look identical to a user who just pressed `gr` on a blank line, and the difference
/// between them is the whole requirement.
///
/// `gd` was already covered by `DefinitionRoutingTests` through `DefinitionRouting`. `gr` was
/// not: its guard lives in `MenuCommandRouter` rather than in a pure routing type, so nothing
/// walked it. Since `gd`/`gr` now enter through that same router (ADR-0113), this is the test
/// that makes AC-5 true for both keys instead of one.
@MainActor
@Suite("커서 아래에 심볼이 없을 때 (REQ-015 AC-5)")
struct NoSymbolUnderCursorTests {

    private func makeModel() -> (AppModel, SearchModel, FakeEditorSession, FakeProjectSession) {
        let project = FakeProjectSession()
        let editor = FakeEditorSession()
        let model = AppModel(
            editorSession: editor,
            workspace: FakeWorkspace(sharedSession: project),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (model, SearchModel(sessionProvider: { project }), editor, project)
    }

    @Test("gr 은 조용히 넘어가지 않고 이유를 말한다")
    func findingReferencesWithoutASymbolExplainsItself() async {
        let (model, search, editor, _) = makeModel()
        editor.wordUnderCursorValue = nil

        await MenuCommandRouter.perform(
            EditorNavigationRequest.findReferences.menuCommand,
            model: model,
            search: search
        )

        #expect(model.statusMessage?.kind == .error, "아무 말도 없으면 사용자는 앱이 멈춘 줄 안다")
        #expect(model.statusMessage?.text.contains("심볼") == true, "\(model.statusMessage?.text ?? "메시지 없음")")
    }

    @Test("심볼이 없으면 빈 이름으로 참조를 찾지 않는다")
    func noSymbolMeansNoSearch() async {
        // 이유를 말하면서 검색도 같이 돌리면, 패널이 "결과 0건"으로 바뀌어 메시지를 덮는다.
        // 말하는 것과 안 하는 것 **둘 다** AC-5 다.
        //
        // ⚠ 처음엔 `selectedTab != .references` 로 썼는데 그건 검사가 아니었다 —
        // `selectedTab` 의 초기값이 이미 `.references` 라 호출 전에도 참이다. 실제로 물어야 할
        // 것은 **엔진에 질의가 갔는가**이고, 그건 세션이 안다.
        let (model, search, editor, project) = makeModel()
        editor.wordUnderCursorValue = nil
        #expect(project.referenceQueries.isEmpty, "시작 전에 이미 질의가 있으면 아래가 무의미하다")

        await MenuCommandRouter.perform(
            EditorNavigationRequest.findReferences.menuCommand,
            model: model,
            search: search
        )

        #expect(project.referenceQueries.isEmpty, "찾을 이름이 없는데 참조 검색이 돌았다: \(project.referenceQueries)")
    }

    @Test("심볼이 있으면 그 이름으로 실제로 찾는다")
    func aSymbolIsActuallySearchedFor() async {
        // 위 테스트는 "아무것도 안 한다"를 재는데, 아무것도 안 하는 구현도 그걸 통과한다.
        // 반대 방향을 함께 고정해야 `gr` 이 살아 있다는 뜻이 된다.
        let (model, search, editor, project) = makeModel()
        editor.wordUnderCursorValue = "UserService"

        await MenuCommandRouter.perform(
            EditorNavigationRequest.findReferences.menuCommand,
            model: model,
            search: search
        )

        #expect(project.referenceQueries == ["UserService"], "실제 질의: \(project.referenceQueries)")
    }

    @Test("gd 도 같은 이유를 말한다 — 두 키의 말이 갈리지 않는다")
    func goingToDefinitionWithoutASymbolSaysTheSameThing() async {
        // 같은 상황에 두 문구가 생기면 사용자는 둘을 다른 사건으로 읽는다.
        let (model, search, editor, _) = makeModel()
        editor.wordUnderCursorValue = nil

        await MenuCommandRouter.perform(
            EditorNavigationRequest.goToDefinition.menuCommand,
            model: model,
            search: search
        )
        let definitionMessage = model.statusMessage?.text

        await MenuCommandRouter.perform(
            EditorNavigationRequest.findReferences.menuCommand,
            model: model,
            search: search
        )
        let referenceMessage = model.statusMessage?.text

        #expect(definitionMessage != nil, "gd 가 아무 말도 안 했다")
        #expect(definitionMessage == referenceMessage, "gd 와 gr 이 같은 상황에 다른 말을 한다")
    }
}
