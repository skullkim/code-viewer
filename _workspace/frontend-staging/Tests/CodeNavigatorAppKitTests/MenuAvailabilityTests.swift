import Testing
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
        #expect(MenuCommand.allCases.count == 24, "명령을 추가·삭제했으면 이 스위트의 규칙도 갱신하라 (파일 5 · 편집 10 · 이동 6 · 보기 3)")
    }
}
