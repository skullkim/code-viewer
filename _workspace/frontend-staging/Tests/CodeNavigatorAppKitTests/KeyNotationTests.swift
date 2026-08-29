import Testing
@testable import CodeNavigatorAppKit

/// The application's whole share of key handling is turning a key press into Neovim key
/// notation and deciding whether the application claims it instead (design §3 W-9,
/// REQ-011 AC-2). How the notation is then interpreted belongs to the edit session.
@Suite("KeyNotation — 키 입력을 Neovim 표기법으로 (REQ-010 AC-5, REQ-011 AC-2)")
struct KeyNotationTests {

    // MARK: Plain typing

    @Test("일반 문자는 그대로 전달된다")
    func plainCharactersPassThrough() {
        #expect(KeyNotation.notation(for: .character("i")) == "i")
        #expect(KeyNotation.notation(for: .character("h")) == "h")
        #expect(KeyNotation.notation(for: .character("j")) == "j")
    }

    @Test("표준 모드에서 Vim 전용 키도 일반 문자로 전달된다")
    func vimKeysAreOrdinaryCharacters() {
        // REQ-010 AC-5: the app must not special-case hjkl or i. Whether they move the
        // cursor or type letters is the edit session's decision, not the notation's.
        for character in ["h", "j", "k", "l", "i", "a", "o", "v"] {
            #expect(KeyNotation.notation(for: .character(character)) == character)
        }
    }

    @Test("⇧ 조합 인쇄 문자는 시프트된 글자로 전달된다")
    func shiftedPrintableCharactersUseTheShiftedGlyph() {
        // The regression that matters: Shift-semicolon is a colon, and without it there is
        // no way to reach Vim's command line at all.
        #expect(KeyNotation.notation(for: .shifted(":", unshifted: ";")) == ":")
        #expect(KeyNotation.notation(for: .shifted("A", unshifted: "a")) == "A")
        #expect(KeyNotation.notation(for: .shifted("?", unshifted: "/")) == "?")
        #expect(KeyNotation.notation(for: .shifted("$", unshifted: "4")) == "$")
    }

    @Test("여는 꺾쇠는 표기법으로 오해되지 않게 이스케이프된다")
    func lessThanIsEscaped() {
        #expect(KeyNotation.notation(for: .character("<")) == "<lt>")
    }

    // MARK: Control chords Vim depends on

    @Test("⌃ 단독 조합은 Neovim 표기법으로 전달된다")
    func controlChordsAreForwarded() {
        #expect(KeyNotation.notation(for: .control("o")) == "<C-o>")
        #expect(KeyNotation.notation(for: .control("r")) == "<C-r>")
        #expect(KeyNotation.notation(for: .control("v")) == "<C-v>")
        #expect(KeyNotation.notation(for: .control("w")) == "<C-w>")
    }

    @Test("⌥ 조합은 M- 접두사를 갖는다")
    func optionChordsUseTheMetaPrefix() {
        #expect(KeyNotation.notation(for: .option("f")) == "<M-f>")
    }

    // MARK: Named keys

    @Test("이름 있는 키는 Neovim 이름으로 매핑된다")
    func namedKeysUseNeovimNames() {
        #expect(KeyNotation.notation(for: .named(.returnKey)) == "<CR>")
        #expect(KeyNotation.notation(for: .named(.tab)) == "<Tab>")
        #expect(KeyNotation.notation(for: .named(.backspace)) == "<BS>")
        #expect(KeyNotation.notation(for: .named(.forwardDelete)) == "<Del>")
        #expect(KeyNotation.notation(for: .named(.escape)) == "<Esc>")
        #expect(KeyNotation.notation(for: .named(.space)) == "<Space>")
        #expect(KeyNotation.notation(for: .named(.home)) == "<Home>")
        #expect(KeyNotation.notation(for: .named(.end)) == "<End>")
        #expect(KeyNotation.notation(for: .named(.pageUp)) == "<PageUp>")
        #expect(KeyNotation.notation(for: .named(.pageDown)) == "<PageDown>")
    }

    @Test("화살표 키는 표준 모드 이동의 기반이다")
    func arrowKeysAreForwarded() {
        #expect(KeyNotation.notation(for: .named(.left)) == "<Left>")
        #expect(KeyNotation.notation(for: .named(.right)) == "<Right>")
        #expect(KeyNotation.notation(for: .named(.up)) == "<Up>")
        #expect(KeyNotation.notation(for: .named(.down)) == "<Down>")
    }

    @Test("⇧+이동은 선택을 만들 수 있도록 S- 접두사를 유지한다")
    func shiftedNamedKeysKeepTheShiftPrefix() {
        // REQ-010 AC-2 asks for shift-move selection in standard mode; the notation has to
        // carry the shift for the session to act on it.
        #expect(KeyNotation.notation(for: .named(.down, modifiers: .shift)) == "<S-Down>")
        #expect(KeyNotation.notation(for: .named(.left, modifiers: .shift)) == "<S-Left>")
        #expect(KeyNotation.notation(for: .named(.end, modifiers: [.shift, .command])) == "<D-S-End>")
    }

    @Test("문자가 없는 키 이벤트는 표기법을 만들지 않는다")
    func eventsWithoutCharactersProduceNothing() {
        #expect(KeyNotation.notation(for: KeyStroke(keyCode: 0x3B, characters: nil, charactersIgnoringModifiers: nil, modifiers: .control)) == nil)
        #expect(KeyNotation.notation(for: .character("")) == nil)
    }

    // MARK: Which side claims the key

    @Test("앱은 ⌘ 포함 조합만 가로챈다")
    func theApplicationClaimsOnlyCommandCombinations() {
        #expect(KeyNotation.isApplicationShortcut(.command("o")))
        #expect(KeyNotation.isApplicationShortcut(.command("p")))
        #expect(KeyNotation.isApplicationShortcut(KeyStroke(keyCode: 0x03, characters: "F", charactersIgnoringModifiers: "f", modifiers: [.command, .shift])))
        #expect(KeyNotation.isApplicationShortcut(KeyStroke(keyCode: 0x09, characters: "v", charactersIgnoringModifiers: "v", modifiers: [.command, .control])))
    }

    @Test("⌃ 단독과 일반 키는 앱이 가로채지 않는다 — Vim 조작이 막히면 안 된다")
    func controlChordsAndPlainKeysReachNeovim() {
        // This is REQ-011 AC-2 in one assertion: every key Vim needs falls through.
        for stroke in [KeyStroke.control("o"), .control("r"), .control("v"), .control("w"),
                       .character("i"), .character("h"), .shifted(":", unshifted: ";"),
                       .named(.escape), .named(.left), .option("f")] {
            #expect(!KeyNotation.isApplicationShortcut(stroke), "\(stroke)가 앱 단축키로 잡혔다")
        }
    }
}
