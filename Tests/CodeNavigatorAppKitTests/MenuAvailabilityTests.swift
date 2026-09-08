import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// REQ-010 AC-5 and design §3 W-9. The edit commands are disabled in Vim mode because
/// `u`, `y` and `p` already do that work there; routing the same edit through two paths
/// forks Neovim's undo history, which is the accident INV-3 exists to prevent.
@Suite("MenuAvailability — 메뉴 항목 활성 규칙 (REQ-010 AC-5, 02 §3 W-9)")
struct MenuAvailabilityTests {

    private func availability(
        inputMode: InputMode = .vim,
        session: EditorSessionState = .connected,
        hasProject: Bool = true
    ) -> MenuAvailability {
        MenuAvailability(inputMode: inputMode, sessionState: session, hasOpenProject: hasProject)
    }

    private let textEditingCommands: [MenuCommand] = [.undo, .redo, .cut, .copy, .paste, .selectAll]

    @Test("Vim 모드에서는 편집 메뉴의 텍스트 명령이 비활성이다")
    func textEditingIsDisabledInVimMode() {
        let menu = availability(inputMode: .vim)
        for command in textEditingCommands {
            #expect(!menu.isEnabled(command), "\(command)가 Vim 모드에서 활성이다 — undo 이력이 갈린다")
        }
    }

    @Test("표준 모드에서는 편집 메뉴의 텍스트 명령이 활성이다")
    func textEditingIsEnabledInStandardMode() {
        let menu = availability(inputMode: .standard)
        for command in textEditingCommands {
            #expect(menu.isEnabled(command), "\(command)가 표준 모드에서 비활성이다")
        }
    }

    @Test("⌘S는 두 모드 모두에서 활성이다 — 실제 쓰기는 :w에 위임된다")
    func saveIsAvailableInBothModes() {
        #expect(availability(inputMode: .vim).isEnabled(.save))
        #expect(availability(inputMode: .standard).isEnabled(.save))
    }

    @Test("편집 세션이 없으면 저장도 편집도 불가능하다")
    func nothingIsEditableWithoutASession() {
        // Enabling a command that cannot reach Neovim would be a silent no-op, and design
        // §2 F-9 is explicit that a dead session must not look like a working one.
        let menu = availability(inputMode: .standard, session: .disconnected(reason: "종료"))
        #expect(!menu.isEnabled(.save))
        for command in textEditingCommands {
            #expect(!menu.isEnabled(command))
        }
    }

    @Test("세션이 끊겨도 내비게이션은 계속 동작한다")
    func navigationSurvivesALostSession() {
        // Design §2 F-9: the index is independent of the edit session, and the card says
        // so. Disabling search here would make the app look wholly dead.
        let menu = availability(session: .disconnected(reason: "종료"))
        #expect(menu.isEnabled(.symbolSearch))
        #expect(menu.isEnabled(.textSearch))
        #expect(menu.isEnabled(.toggleFileTree))
        #expect(menu.isEnabled(.togglePanel))
    }

    @Test("커서에서 출발하는 명령은 세션을 요구한다")
    func cursorDrivenCommandsNeedASession() {
        let menu = availability(session: .disconnected(reason: "종료"))
        for command in [MenuCommand.goToDefinition, .showReferences, .navigateBack, .navigateForward] {
            #expect(!menu.isEnabled(command), "\(command)는 커서를 읽어야 하므로 세션 없이 동작할 수 없다")
        }
    }

    @Test("프로젝트가 없으면 검색·패널이 비활성이다")
    func searchIsDisabledWithoutAProject() {
        // Design §3 W-1 empty state: the toolbar's search and panel buttons are disabled.
        let menu = availability(hasProject: false)
        #expect(!menu.isEnabled(.symbolSearch))
        #expect(!menu.isEnabled(.textSearch))
        #expect(!menu.isEnabled(.togglePanel))
        #expect(!menu.isEnabled(.closeProject))
    }

    @Test("프로젝트 열기와 창 닫기는 언제나 가능하다")
    func openingAProjectIsAlwaysPossible() {
        let menu = availability(session: .notStarted, hasProject: false)
        #expect(menu.isEnabled(.openProject))
        #expect(menu.isEnabled(.closeWindow))
        #expect(menu.isEnabled(.toggleFullScreen))
    }

    @Test("세션 재기동은 세션이 살아 있지 않을 때만 제공된다")
    func restartIsOfferedOnlyWhenTheSessionIsNotRunning() {
        #expect(!availability(session: .connected).isEnabled(.restartEditSession))
        #expect(availability(session: .disconnected(reason: "종료")).isEnabled(.restartEditSession))
        #expect(availability(session: .notStarted).isEnabled(.restartEditSession))
    }

    @Test("입력 모드 전환은 세션이 있어야 의미가 있다")
    func togglingTheInputModeNeedsASession() {
        #expect(availability(session: .connected).isEnabled(.toggleInputMode))
        #expect(!availability(session: .disconnected(reason: "종료")).isEnabled(.toggleInputMode))
    }

    @Test("현재 입력 모드에 체크 표시가 붙는다")
    func theCurrentInputModeIsTicked() {
        #expect(availability(inputMode: .vim).isChecked(.selectVimMode))
        #expect(!availability(inputMode: .vim).isChecked(.selectStandardMode))
        #expect(availability(inputMode: .standard).isChecked(.selectStandardMode))
        #expect(!availability(inputMode: .standard).isChecked(.selectVimMode))
    }

    @Test("모든 명령이 규칙에 걸린다 — 빠뜨린 명령이 없다")
    func everyCommandHasARule() {
        // A command added to the menu but forgotten here would silently default to one
        // state or the other. Walking the full case list makes the omission impossible.
        let menu = availability()
        for command in MenuCommand.allCases {
            _ = menu.isEnabled(command)
        }
        // 24 → 25: `.toggleRenderView` 추가 (REQ-013 AC-3, 02b F-14).
        // 25 → 28: 외관 선택 3종 추가 (시스템 따름·밝게·어둡게).
        // 28 → 33: 디버그 5종 추가 (연결·끊기·브레이크포인트·계속·패널).
        // 33 → 36: 스텝 3종 추가 (한 줄·안으로·밖으로).
        // 36 → 38: 예외 중단 2종 추가 (잡히지 않는·잡히는).
        // 38 → 39: 브레이크포인트 조건 편집 추가.
        // 39 → 40: 식 평가 추가.
        // 40 → 41: 필드 지켜보기 추가.
        // 41 → 43: Watch 더하기 · 핫스왑 추가.
        // 43 → 48: 실행 5종 추가 (실행·디버그 실행·정지·터미널·설정).
        // **이 수는 트립와이어다** — 명령을 더하면 깨지는 것이 일이고, 깨진 자리에서
        // "이 명령의 활성 규칙을 정했나"를 묻게 하는 것이 목적이다. 숫자만 올리고 지나가면
        // 규칙 없는 명령이 새어 나간다. 내역도 같이 고친다 — 합만 맞고 내역이 낡으면
        // 다음 사람이 어디가 늘었는지 못 읽는다.
        #expect(MenuCommand.allCases.count == 48, "명령을 추가·삭제했으면 이 스위트의 규칙도 갱신하라 (파일 5 · 편집 10 · 이동 6 · 보기 7 · 실행 5 · 디버그 15)")
    }
}

/// 키보드를 **텍스트 필드가 들고 있을 때** 표준 편집이 살아 있어야 한다.
///
/// REQ-010 AC-5 는 Vim 모드에서 ⌘C·⌘V·⌘A 를 끄라고 한다 — 편집기에서는 그 일을 Vim 이
/// 하기 때문이다. 그런데 그 판단이 **편집기 모드만** 보고 이뤄져서, 검색창에 글자를 치고
/// 있어도 전체 선택·복사·붙여넣기가 전부 죽어 있었다. 사용자가 겪은 그대로다:
/// "검색에서 입력한 거 전체 선택 안되고, 복사 붙여넣기도 안돼."
@Suite("텍스트 필드가 키보드를 들면 표준 편집이 산다")
struct TextFieldEditingAvailabilityTests {

    private func availability(
        inputMode: InputMode, owner: KeyboardFocusOwner
    ) -> MenuAvailability {
        MenuAvailability(
            inputMode: inputMode, sessionState: .connected, hasOpenProject: true,
            keyboardOwner: owner
        )
    }

    private static let editingCommands: [MenuCommand] = [.copy, .paste, .cut, .selectAll, .undo, .redo]

    @Test("검색창이 키보드를 들면 Vim 모드여도 편집 명령이 켜진다")
    func editingIsOnWhileTypingInASearchField() {
        for owner in [KeyboardFocusOwner.symbolSearchField, .textSearchField] {
            let menu = availability(inputMode: .vim, owner: owner)
            for command in Self.editingCommands {
                #expect(menu.isEnabled(command), "\(owner) 에서 \(command) 가 꺼져 있다")
            }
        }
    }

    /// 편집기가 키보드를 들고 있으면 예전 규칙 그대로다 — Vim 이 그 일을 한다.
    @Test("편집기가 들고 있으면 Vim 모드에서 여전히 꺼진다")
    func editorKeepsTheOldRule() {
        let menu = availability(inputMode: .vim, owner: .editor)
        for command in Self.editingCommands {
            #expect(menu.isEnabled(command) == false, "\(command) 가 Vim 모드 편집기에서 켜졌다")
        }
    }

    @Test("표준 모드에서는 어디에 있든 켜진다")
    func standardModeIsAlwaysOn() {
        for owner in KeyboardFocusOwner.allCases {
            let menu = availability(inputMode: .standard, owner: owner)
            for command in Self.editingCommands {
                #expect(menu.isEnabled(command), "\(owner) 에서 \(command) 가 꺼져 있다")
            }
        }
    }

    /// 터미널도 글자를 받는 표면이다. 다만 붙여넣기는 셸이 처리해야 하므로 여기서는
    /// 편집기와 같은 취급을 한다 — 앱이 가로채면 셸에 안 들어간다.
    @Test("터미널은 편집기와 같은 취급이다")
    func terminalBehavesLikeTheEditor() {
        let menu = availability(inputMode: .vim, owner: .terminal)
        #expect(menu.isEnabled(.copy) == false)
    }
}

/// 켜 두기만 하고 엉뚱한 데로 보내면 더 나쁘다.
///
/// `copySelection()`·`paste()`·`selectAll()` 은 **항상 Neovim** 으로 갔다. 검색창에 커서를
/// 두고 ⌘C 를 누르면 편집기의 선택이 복사되고, 사용자는 자기가 친 글자가 아니라 엉뚱한
/// 코드를 붙여넣게 된다 — 아무 일도 안 일어나는 것보다 나쁘다.
@Suite("텍스트 필드의 편집 명령은 편집기로 가지 않는다")
@MainActor
struct TextFieldEditingRoutingTests {

    private func makeModel() -> (AppModel, FakeEditorSession, SearchModel) {
        let editor = FakeEditorSession()
        let project = FakeProjectSession()
        let model = AppModel(
            editorSession: editor,
            workspace: FakeWorkspace(sharedSession: project),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (model, editor, SearchModel(sessionProvider: { project }))
    }

    @Test("검색창이 키보드를 들고 있으면 편집기 세션을 건드리지 않는다")
    func doesNotReachTheEditorWhileTypingInAField() async {
        let (model, editor, search) = makeModel()
        model.focus.userFocused(.symbolSearchField)

        for command in [MenuCommand.copy, .paste, .cut, .selectAll] {
            await MenuCommandRouter.perform(command, model: model, search: search, environment: .headless)
        }
        let reached = editor.editorCommands.filter {
            ["copySelection", "cutSelection", "paste", "selectAll"].contains($0)
        }
        #expect(reached.isEmpty, "검색창에서 편집 명령이 편집기로 갔다: \(reached)")
    }

    @Test("편집기가 키보드를 들고 있으면 예전대로 편집기로 간다")
    func stillReachesTheEditorOtherwise() async {
        let (model, editor, search) = makeModel()
        model.focus.userFocused(.editor)

        await MenuCommandRouter.perform(.copy, model: model, search: search, environment: .headless)
        await MenuCommandRouter.perform(.selectAll, model: model, search: search, environment: .headless)
        #expect(editor.editorCommands.contains("copySelection"))
        #expect(editor.editorCommands.contains("selectAll"))
    }
}
