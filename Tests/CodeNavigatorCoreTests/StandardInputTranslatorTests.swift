import Testing

@testable import CodeNavigatorCore

/// covers: REQ-010 AC-2 (표준 모드는 맥 관례대로 동작한다),
///         REQ-010 AC-5 (표준 모드에서 Vim 전용 키는 일반 문자로 입력된다)
@Suite("StandardInputTranslator")
struct StandardInputTranslatorTests {

    private func makeEvent(
        characters: String = "",
        keyCode: KeyCodeName,
        modifiers: KeyModifiers = []
    ) -> StandardKeyEvent {
        StandardKeyEvent(characters: characters, keyCode: keyCode, modifiers: modifiers)
    }

    private func translate(
        characters: String = "",
        keyCode: KeyCodeName,
        modifiers: KeyModifiers = []
    ) -> String? {
        StandardInputTranslator.translate(
            makeEvent(characters: characters, keyCode: keyCode, modifiers: modifiers)
        )
    }

    // 이동 — 화살표와 선택.

    @Test("화살표는 Neovim 방향키 표기가 된다")
    func arrowKeysBecomeDirectionKeys() {
        #expect(translate(keyCode: .upArrow) == "<Up>")
        #expect(translate(keyCode: .downArrow) == "<Down>")
        #expect(translate(keyCode: .leftArrow) == "<Left>")
        #expect(translate(keyCode: .rightArrow) == "<Right>")
    }

    @Test("⇧+화살표는 선택 이동이 된다")
    func shiftArrowKeysSelect() {
        #expect(translate(keyCode: .upArrow, modifiers: .shift) == "<S-Up>")
        #expect(translate(keyCode: .downArrow, modifiers: .shift) == "<S-Down>")
        #expect(translate(keyCode: .leftArrow, modifiers: .shift) == "<S-Left>")
        #expect(translate(keyCode: .rightArrow, modifiers: .shift) == "<S-Right>")
    }

    @Test("Home·End 키가 줄 처음·끝으로 간다")
    func homeAndEndKeysMoveWithinLine() {
        #expect(translate(keyCode: .home) == "<Home>")
        #expect(translate(keyCode: .end) == "<End>")
    }

    @Test("⌘+좌우는 줄 처음·끝으로, ⌘+상하는 문서 처음·끝으로 간다")
    func commandArrowKeysMoveToLineAndDocumentEnds() {
        #expect(translate(keyCode: .leftArrow, modifiers: .command) == "<Home>")
        #expect(translate(keyCode: .rightArrow, modifiers: .command) == "<End>")
        #expect(translate(keyCode: .upArrow, modifiers: .command) == "gg")
        #expect(translate(keyCode: .downArrow, modifiers: .command) == "G")
    }

    @Test("⌥+좌우는 단어 단위로 이동한다")
    func optionArrowKeysMoveByWord() {
        #expect(translate(keyCode: .leftArrow, modifiers: .option) == "<C-Left>")
        #expect(translate(keyCode: .rightArrow, modifiers: .option) == "<C-Right>")
    }

    // 편집 — 클립보드·되돌리기·저장·전체선택.

    @Test("⌘C·⌘X·⌘V는 시스템 클립보드 레지스터를 쓴다")
    func clipboardShortcutsUseSystemRegister() {
        #expect(translate(characters: "c", keyCode: .character, modifiers: .command) == "\"+y")
        #expect(translate(characters: "x", keyCode: .character, modifiers: .command) == "\"+d")
        #expect(translate(characters: "v", keyCode: .character, modifiers: .command) == "\"+p")
    }

    @Test("⌘Z는 되돌리기, ⌘⇧Z는 다시 실행이다")
    func undoAndRedoShortcuts() {
        #expect(translate(characters: "z", keyCode: .character, modifiers: .command) == "u")
        #expect(translate(characters: "z", keyCode: .character, modifiers: [.command, .shift]) == "<C-r>")
    }

    @Test("⌘S는 저장, ⌘A는 전체 선택이다")
    func saveAndSelectAllShortcuts() {
        #expect(translate(characters: "s", keyCode: .character, modifiers: .command) == ":w<CR>")
        #expect(translate(characters: "a", keyCode: .character, modifiers: .command) == "ggVG")
    }

    @Test("삭제 키가 앞뒤 삭제로 나뉜다")
    func deleteKeysMapToBackwardAndForward() {
        #expect(translate(keyCode: .deleteBackward) == "<BS>")
        #expect(translate(keyCode: .deleteForward) == "<Del>")
    }

    @Test("Enter·Tab·Esc가 각각의 키 표기가 된다")
    func enterTabEscapeBecomeKeyNotation() {
        #expect(translate(keyCode: .enter) == "<CR>")
        #expect(translate(keyCode: .tab) == "<Tab>")
        #expect(translate(keyCode: .escape) == "<Esc>")
    }

    // 문자 입력 — 표준 모드에는 모드 개념이 없다 (AC-5).

    @Test("Vim 명령 문자도 그냥 문자로 입력된다")
    func vimCommandCharactersStayLiteral() {
        #expect(translate(characters: "i", keyCode: .character) == "i")
        #expect(translate(characters: ":", keyCode: .character) == ":")
        #expect(translate(characters: "h", keyCode: .character) == "h")
        #expect(translate(characters: "j", keyCode: .character) == "j")
        #expect(translate(characters: "k", keyCode: .character) == "k")
        #expect(translate(characters: "l", keyCode: .character) == "l")
    }

    @Test("⇧로 입력한 대문자와 한글이 그대로 전달된다")
    func shiftedAndNonAsciiCharactersPassThrough() {
        #expect(translate(characters: "A", keyCode: .character, modifiers: .shift) == "A")
        #expect(translate(characters: "값", keyCode: .character) == "값")
    }

    @Test("여는 꺾쇠는 키 표기와 충돌하지 않게 이스케이프된다")
    func lessThanCharacterIsEscaped() {
        #expect(translate(characters: "<", keyCode: .character) == "<lt>")
        #expect(translate(characters: "a<b", keyCode: .character) == "a<lt>b")
    }

    // 알 수 없는 조합은 앱이 처리한다.

    @Test("매핑에 없는 조합은 nil이다")
    func unmappedCombinationsReturnNil() {
        #expect(translate(characters: "k", keyCode: .character, modifiers: .command) == nil)
        #expect(translate(characters: "a", keyCode: .character, modifiers: .control) == nil)
        #expect(translate(characters: "j", keyCode: .character, modifiers: .option) == nil)
        #expect(translate(keyCode: .enter, modifiers: .command) == nil)
        #expect(translate(keyCode: .upArrow, modifiers: .control) == nil)
        #expect(translate(characters: "", keyCode: .character) == nil)
    }
}
