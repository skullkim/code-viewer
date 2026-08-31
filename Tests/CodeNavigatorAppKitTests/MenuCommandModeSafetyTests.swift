import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Menu commands must mean the same thing in both input modes.
///
/// They did not. `MenuCommandRouter` sent raw normal-mode keys, which is correct in Vim
/// mode and wrong in standard mode, where Neovim is held in insert so the user can type
/// `i`, `:` and `hjkl` as letters (REQ-010 AC-5). backend-senior measured the result
/// against a real Neovim: ⌘Z typed the letter `u` into the buffer, ⌘[ swallowed the next
/// keystroke, and **⌘S did not save** — the worst kind, because it looks like a save.
///
/// The existing menu tests all passed through this. They checked that a command *runs*,
/// never that it produces the same result in both modes. These do.
@MainActor
@Suite("MenuCommand 모드 안전성 (REQ-010 AC-2, REQ-005 AC-4)")
struct MenuCommandModeSafetyTests {

    private func makeModel() -> (AppModel, SearchModel, FakeEditorSession) {
        let project = FakeProjectSession()
        let editor = FakeEditorSession()
        let model = AppModel(
            editorSession: editor,
            workspace: FakeWorkspace(sharedSession: project),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (model, SearchModel(sessionProvider: { project }), editor)
    }

    /// Commands that still reach the editor as a raw key string, and would therefore mean
    /// something different in standard mode.
    ///
    /// This was eight. It is now empty, and it stays here as the assertion that keeps it
    /// empty: anything added back shows up as a named difference rather than as a bug a
    /// user finds by losing work.
    private let knownModeUnsafeCommands: Set<MenuCommand> = []

    @Test("뒤로 가기는 모드 무관 경로를 쓴다")
    func navigatingBackUsesTheModeAgnosticPath() async {
        // `<C-o>` in insert mode waits for one normal command and eats the user's next
        // keystroke — the cursor does not move and a letter silently disappears. The
        // engine's `jumpBack` wraps it in `normal!`, which behaves the same in both modes.
        let (model, search, editor) = makeModel()
        await MenuCommandRouter.perform(.navigateBack, model: model, search: search)

        #expect(editor.jumpBackCount == 1)
        #expect(editor.sentKeys.isEmpty, "raw 키를 보냈다 — 표준 모드에서 다음 타자를 먹는다")
    }

    @Test("아직 모드에 의존하는 명령이 무엇인지 명시된다")
    func theRemainingModeUnsafeCommandsAreNamed() async {
        // Every command that reaches the editor as a raw key string is mode-dependent by
        // construction. Measuring which ones still do keeps the gap countable.
        var unsafe: Set<MenuCommand> = []
        for command in MenuCommand.allCases {
            let (model, search, editor) = makeModel()
            // No folder panel: a modal here would block the run for ever.
            await MenuCommandRouter.perform(command, model: model, search: search, chooseFolder: { nil })
            if !editor.sentKeys.isEmpty {
                unsafe.insert(command)
            }
        }

        #expect(
            unsafe == knownModeUnsafeCommands,
            """
            모드 의존 명령 목록이 바뀌었다.
              새로 생김: \(unsafe.subtracting(knownModeUnsafeCommands))
              해소됨: \(knownModeUnsafeCommands.subtracting(unsafe)) ← 해소됐으면 이 테스트의 목록에서 지워라
            """
        )
    }

    @Test("편집 명령이 전부 엔진 메서드로 나간다 — 키 문자열이 아니라")
    func everyEditingCommandGoesThroughTheEngine() async {
        // Named individually because each was a measured defect: ⌘Z typed `u` into the
        // buffer, ⌘S reported success and wrote nothing. Asserting the engine method was
        // called is what separates "the command ran" from "the command did its job".
        let expected: [(MenuCommand, String)] = [
            (.save, "save"), (.undo, "undo"), (.redo, "redo"),
            (.cut, "cutSelection"), (.copy, "copySelection"), (.paste, "paste"),
            (.selectAll, "selectAll"),
            (.navigateBack, "jumpBack"), (.navigateForward, "jumpForward"),
        ]

        for (command, method) in expected {
            let (model, search, editor) = makeModel()
            await MenuCommandRouter.perform(command, model: model, search: search, chooseFolder: { nil })
            #expect(editor.editorCommands == [method], "\(command)가 \(method)를 부르지 않았다")
            #expect(editor.sentKeys.isEmpty, "\(command)가 raw 키를 보냈다 — 표준 모드에서 버퍼를 오염시킨다")
        }
    }
}
