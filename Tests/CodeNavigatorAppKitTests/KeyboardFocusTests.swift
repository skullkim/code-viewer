import Testing
@testable import CodeNavigatorAppKit

/// Who owns the keyboard, decided in one place (D-6 잔여 · D-7 · REQ-008 · REQ-010 AC-1).
///
/// Before this existed, each view answered the question for itself and they disagreed: the
/// symbol-search modal claimed focus on appear, the search panel's field claimed nothing at
/// all, and the editor claimed the keyboard only when nobody else held it. That last rule
/// looked safe and was the bug — once a modal's field editor had taken the keyboard, the
/// condition "nobody holds it" was never true again, so closing the modal left the user
/// with no way back into the editor. Measured live: after ⌘P, typing never reached Neovim
/// again, and clicking the editor did not recover it.
///
/// One owner, one transition table, and every view follows it.
@MainActor
@Suite("키보드 소유권 — 누가 언제 키보드를 갖는가 (REQ-010 AC-1, REQ-008)")
struct KeyboardFocusTests {

    @Test("기본 소유자는 에디터다")
    func theEditorOwnsTheKeyboardByDefault() {
        // Typing is what this application is for; anything else has to ask.
        #expect(KeyboardFocusCoordinator().owner == .editor)
    }

    @Test("심볼 검색 모달이 열리면 모달이 가져간다")
    func openingTheSymbolSearchModalTakesTheKeyboard() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.surfaceDidOpen(.symbolSearchField)
        #expect(coordinator.owner == .symbolSearchField)
    }

    @Test("모달을 닫으면 열기 전 주인에게 돌아간다 — 에디터에서 열었으면 에디터로")
    func closingTheModalReturnsTheKeyboardToWhoeverHadIt() {
        // This is the defect. ⌘P → 심볼 → 점프 is the core flow of this application, and
        // before the fix, using it once made typing impossible for the rest of the session.
        let coordinator = KeyboardFocusCoordinator()
        coordinator.surfaceDidOpen(.symbolSearchField)
        coordinator.surfaceDidClose(.symbolSearchField)
        #expect(coordinator.owner == .editor)
    }

    @Test("검색 패널에서 모달을 열었다 닫으면 검색 패널로 돌아간다")
    func closingTheModalReturnsToTheSearchPanelWhenItHadTheKeyboard() {
        // "Back to the editor" is not the rule — "back to where it came from" is. Typing a
        // query, jumping to a symbol, then coming back should leave the caret in the query.
        let coordinator = KeyboardFocusCoordinator()
        coordinator.userFocused(.textSearchField)
        coordinator.surfaceDidOpen(.symbolSearchField)
        coordinator.surfaceDidClose(.symbolSearchField)
        #expect(coordinator.owner == .textSearchField)
    }

    @Test("모달이 겹쳐 열려도 주인은 하나이고 복귀 지점은 유지된다")
    func nestedOpensDoNotLoseTheReturnPoint() {
        // SwiftUI can send the same appearance twice. Overwriting the saved owner with
        // "symbolSearchField" would make closing return the keyboard to a modal that is
        // gone — which is the original bug wearing a different hat.
        let coordinator = KeyboardFocusCoordinator()
        coordinator.userFocused(.textSearchField)
        coordinator.surfaceDidOpen(.symbolSearchField)
        coordinator.surfaceDidOpen(.symbolSearchField)
        coordinator.surfaceDidClose(.symbolSearchField)
        #expect(coordinator.owner == .textSearchField)
    }

    @Test("사용자가 클릭한 곳이 키보드를 갖는다")
    func clickingSomewhereGivesItTheKeyboard() {
        // The leader's requirement, in one line: 사용자가 클릭한 곳이 입력을 받는다.
        let coordinator = KeyboardFocusCoordinator()
        coordinator.userFocused(.textSearchField)
        #expect(coordinator.owner == .textSearchField)
        coordinator.userFocused(.editor)
        #expect(coordinator.owner == .editor)
        coordinator.userFocused(.fileTree)
        #expect(coordinator.owner == .fileTree)
    }

    @Test("어떤 표면이든 열리면 그 표면이 주인이 된다 — 전수 (D-11)")
    func everySurfaceCanTakeTheKeyboard() {
        // The defect this replaces: the modal had an open path and the search panel had
        // none, so the panel's field could never be told it had the keyboard. The unit
        // tests were all green — the coordinator answered correctly when asked, and nobody
        // asked. Walking every case is what makes a half-wired surface impossible.
        let surfaces = KeyboardFocusOwner.allCases
        #expect(!surfaces.isEmpty, "케이스가 비면 이 루프는 아무것도 검사하지 않는다")

        for surface in surfaces {
            let coordinator = KeyboardFocusCoordinator()
            coordinator.surfaceDidOpen(surface)
            #expect(coordinator.owner == surface, "\(surface) 이 열려도 주인이 되지 못한다")
        }
    }

    @Test("어떤 표면이든 닫히면 키보드를 돌려준다 — 전수")
    func everySurfaceGivesTheKeyboardBack() {
        let surfaces = KeyboardFocusOwner.allCases.filter { $0 != .editor }
        #expect(!surfaces.isEmpty)

        for surface in surfaces {
            let coordinator = KeyboardFocusCoordinator()
            coordinator.surfaceDidOpen(surface)
            coordinator.surfaceDidClose(surface)
            #expect(coordinator.owner == .editor, "\(surface) 이 닫혔는데 키보드를 안 돌려준다")
        }
    }

    @Test("검색 패널이 열리면 패널이 키보드를 갖는다 (REQ-008)")
    func openingTheSearchPanelGivesItTheKeyboard() {
        // The single assertion that was missing. Without it the panel's `hasKeyboard` stays
        // false for ever and the field turns its own focus back off.
        let coordinator = KeyboardFocusCoordinator()
        coordinator.surfaceDidOpen(.textSearchField)
        #expect(coordinator.owner == .textSearchField)
    }

    @Test("검색 패널이 닫히면 키보드가 에디터로 돌아온다")
    func closingTheSearchPanelReturnsTheKeyboardToTheEditor() {
        // A field that no longer exists must not keep the keyboard — that is exactly how
        // the editor became unreachable.
        let coordinator = KeyboardFocusCoordinator()
        coordinator.userFocused(.textSearchField)
        coordinator.surfaceDidClose(.textSearchField)
        #expect(coordinator.owner == .editor)
    }

    @Test("검색 패널이 닫혀도 그 패널이 주인이 아니었으면 아무것도 안 바뀐다")
    func closingAPanelThatDidNotHaveTheKeyboardChangesNothing() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.userFocused(.fileTree)
        coordinator.surfaceDidClose(.textSearchField)
        #expect(coordinator.owner == .fileTree)
    }

    @Test("모달이 주인인 동안 패널이 닫혀도 복귀 지점만 바뀐다")
    func aPanelClosingWhileTheModalIsUpOnlyMovesTheReturnPoint() {
        // The panel can be dismissed underneath the modal. Returning to it afterwards would
        // hand the keyboard to a field that is gone.
        let coordinator = KeyboardFocusCoordinator()
        coordinator.userFocused(.textSearchField)
        coordinator.surfaceDidOpen(.symbolSearchField)
        coordinator.surfaceDidClose(.textSearchField)
        coordinator.surfaceDidClose(.symbolSearchField)
        #expect(coordinator.owner == .editor)
    }
}
