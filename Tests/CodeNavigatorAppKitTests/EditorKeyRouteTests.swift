import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Which path a key press takes into Neovim (REQ-014 2단계, D-13).
///
/// Two paths, chosen by mode, because the two moments want opposite things:
///
/// - **Insert mode** is where Korean gets typed. The press has to go through the input
///   context so the IME can combine jamo into syllables. Without it the buffer receives
///   `ㅎㅏㄴㄱㅡㄹ` where the user typed `한글` — QA measured 18 bytes on disk instead of 6.
/// - **Normal and visual** are commands. There the physical key is translated to its Latin
///   letter, because `ㅑ` is not `i` and Vim cannot read it.
@Suite("에디터 키 경로 — 모드가 입력 경로를 고른다 (REQ-014, D-13)")
struct EditorKeyRouteTests {

    private let layout: (UInt16) -> String? = { keyCode in
        switch keyCode {
        case 34: return "i"
        case 40: return "k"
        default: return nil
        }
    }

    private func stroke(
        keyCode: UInt16,
        characters: String,
        modifiers: KeyModifiers = []
    ) -> KeyStroke {
        KeyStroke(keyCode: keyCode, characters: characters, charactersIgnoringModifiers: characters, modifiers: modifiers)
    }

    private func route(
        _ stroke: KeyStroke,
        editorMode: EditorMode = .normal,
        inputMode: InputMode = .vim,
        hasMarkedText: Bool = false
    ) -> EditorKeyRoute {
        EditorKeyInput.route(
            for: stroke,
            editorMode: editorMode,
            inputMode: inputMode,
            hasMarkedText: hasMarkedText,
            latinCharacter: layout
        )
    }

    private let escape = KeyStroke(keyCode: 53, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", modifiers: [])

    // MARK: 경로 선택

    @Test("삽입 모드는 입력 컨텍스트로 간다 — 조합이 거기서 일어난다")
    func insertModeGoesThroughTheInputContext() {
        #expect(route(stroke(keyCode: 5, characters: "ㅎ"), editorMode: .insert) == .interpretForComposition)
    }

    @Test("표준 모드도 입력 컨텍스트로 간다 — 거기도 글을 쓰는 자리다")
    func standardModeAlsoComposes() {
        // Standard mode is ordinary Mac editing (REQ-010). Korean has to compose there for
        // the same reason it does in insert mode.
        for mode in [EditorMode.normal, .insert, .visual] {
            #expect(route(stroke(keyCode: 5, characters: "ㅎ"), editorMode: mode, inputMode: .standard) == .interpretForComposition)
        }
    }

    @Test("노멀·비주얼은 번역해서 바로 보낸다")
    func normalAndVisualTranslateAndSend() {
        #expect(route(stroke(keyCode: 34, characters: "ㅑ")) == .notation("i"))
        #expect(route(stroke(keyCode: 40, characters: "ㅏ"), editorMode: .visual) == .notation("k"))
    }

    // MARK: 🔴 조합 중 모드 이탈 — 리더가 조건으로 건 자리

    @Test("조합 중 Esc 는 조합된 것을 커밋한 뒤 나간다 (데이터 손실 방지)")
    func escapeWhileComposingCommitsFirst() {
        // Without this the user types `한`, presses Esc believing it is written, and the
        // syllable is silently discarded — a new data loss of exactly the kind this whole
        // change exists to remove.
        #expect(route(escape, editorMode: .insert, hasMarkedText: true) == .commitThenNotation("<Esc>"))
    }

    @Test("🔴 조합 중이 아니어도 탈출 키는 탈출한다 — 셋 다 (최고 심각도)")
    func exitKeysLeaveInsertModeWithoutAnyComposition() {
        // The worst defect this build produced, and it had nothing to do with Korean.
        // `hasMarkedText` sat *in front of* the exit check, so typing plain ASCII and
        // pressing Escape fell through to the input context, which swallowed it as
        // `doCommand cancelOperation:`. Nobody could leave insert mode — no save, no
        // command, only force quit. QA measured all three keys swallowed.
        //
        // An exit key is an exit key whether or not something is being composed. Every
        // test before this one supplied `hasMarkedText: true`, which is exactly why 14
        // green tests said nothing about the case every user hits.
        let controlBracket = stroke(keyCode: 33, characters: "[", modifiers: [.control])
        let controlC = stroke(keyCode: 8, characters: "c", modifiers: [.control])

        #expect(route(escape, editorMode: .insert, hasMarkedText: false) == .notation("<Esc>"))
        #expect(route(controlBracket, editorMode: .insert, hasMarkedText: false) == .notation("<C-[>"))
        #expect(route(controlC, editorMode: .insert, hasMarkedText: false) == .notation("<C-c>"))
    }

    @Test("조합 중이면 커밋하고 나간다 — 같은 세 키")
    func theSameThreeKeysCommitFirstWhenComposing() {
        let controlBracket = stroke(keyCode: 33, characters: "[", modifiers: [.control])
        let controlC = stroke(keyCode: 8, characters: "c", modifiers: [.control])

        #expect(route(escape, editorMode: .insert, hasMarkedText: true) == .commitThenNotation("<Esc>"))
        #expect(route(controlBracket, editorMode: .insert, hasMarkedText: true) == .commitThenNotation("<C-[>"))
        #expect(route(controlC, editorMode: .insert, hasMarkedText: true) == .commitThenNotation("<C-c>"))
    }

    @Test("탈출 키가 아닌 글자는 조합 여부와 무관하게 입력 컨텍스트로 간다")
    func ordinaryKeysAlwaysGoToTheInputContext() {
        // The counterweight: making exits unconditional must not make everything else
        // unconditional too, or Korean stops composing again.
        let letter = stroke(keyCode: 5, characters: "ㅎ")
        #expect(route(letter, editorMode: .insert, hasMarkedText: false) == .interpretForComposition)
        #expect(route(letter, editorMode: .insert, hasMarkedText: true) == .interpretForComposition)
    }

    @Test("⌃[ 와 ⌃C 도 같은 이탈 경로다")
    func theOtherWaysOutOfInsertCommitToo() {
        // Vim users leave insert with these as readily as with Esc. Handling only Esc would
        // lose the syllable through the door nobody thought to close.
        let controlBracket = stroke(keyCode: 33, characters: "[", modifiers: [.control])
        let controlC = stroke(keyCode: 8, characters: "c", modifiers: [.control])
        #expect(route(controlBracket, editorMode: .insert, hasMarkedText: true) == .commitThenNotation("<C-[>"))
        #expect(route(controlC, editorMode: .insert, hasMarkedText: true) == .commitThenNotation("<C-c>"))
    }

    @Test("한글 자판에서도 ⌃[ 와 ⌃C 가 이탈로 감지된다 (자판 무관)")
    func exitKeysAreDetectedOnANonLatinKeyboard() {
        // The defect QA's three-key matrix exposed. Detection read
        // `charactersIgnoringModifiers`, which a Korean input source turns into a jamo — so
        // `⌃[` and `⌃C` were never recognised as exits at all. Measured: `⌃[` → `ㅐ`,
        // `⌃C` → `ㅊ`, neither of which equals "[" or "c".
        //
        // `⌃[` then appeared to work *by accident*: detection failed, the press fell
        // through to the input method, which committed the syllable and passed the escape
        // character on. `⌃C` had no such luck and could not leave insert mode at all.
        //
        // The key code is the physical key and does not move with the layout, which is the
        // same axis `NamedKey` already uses for Escape.
        let bracketKorean = KeyStroke(keyCode: 33, characters: "\u{1B}", charactersIgnoringModifiers: "ㅐ", modifiers: [.control])
        let cKorean = KeyStroke(keyCode: 8, characters: "\u{03}", charactersIgnoringModifiers: "ㅊ", modifiers: [.control])

        #expect(EditorKeyInput.isInsertModeExit(bracketKorean), "한글 자판에서 ⌃[ 가 이탈로 안 잡힌다")
        #expect(EditorKeyInput.isInsertModeExit(cKorean), "한글 자판에서 ⌃C 가 이탈로 안 잡힌다 — 삽입 모드에서 못 나온다")
    }

    @Test("라틴 자판에서도 그대로 감지된다")
    func exitKeysStillWorkOnALatinKeyboard() {
        let bracketLatin = KeyStroke(keyCode: 33, characters: "\u{1B}", charactersIgnoringModifiers: "[", modifiers: [.control])
        let cLatin = KeyStroke(keyCode: 8, characters: "\u{03}", charactersIgnoringModifiers: "c", modifiers: [.control])
        #expect(EditorKeyInput.isInsertModeExit(bracketLatin))
        #expect(EditorKeyInput.isInsertModeExit(cLatin))
    }

    @Test("⌃ 없는 [ 와 c 는 이탈이 아니다 — 그냥 글자다")
    func plainBracketAndCAreNotExits() {
        // Without Control these are text. Treating them as exits would make it impossible
        // to type them.
        let bracket = KeyStroke(keyCode: 33, characters: "[", charactersIgnoringModifiers: "[", modifiers: [])
        let c = KeyStroke(keyCode: 8, characters: "c", charactersIgnoringModifiers: "c", modifiers: [])
        #expect(EditorKeyInput.isInsertModeExit(bracket) == false)
        #expect(EditorKeyInput.isInsertModeExit(c) == false)
    }

    @Test("표준 모드에서는 Esc 로 커밋하지 않는다 — 나갈 모드가 없다")
    func standardModeDoesNotCommitOnEscape() {
        // There is no insert mode to leave, so Esc belongs to the IME (it cancels the
        // composition, which is what the user asked for by pressing it).
        #expect(route(escape, editorMode: .insert, inputMode: .standard, hasMarkedText: true) == .interpretForComposition)
    }

    @Test("조합 중이라도 노멀 모드면 커밋 경로를 타지 않는다")
    func markedTextOutsideInsertIsNotThisRulesBusiness() {
        // Marked text cannot exist outside the composing path; if it somehow does, the
        // normal-mode rule still owns the key.
        #expect(route(stroke(keyCode: 34, characters: "ㅑ"), editorMode: .normal, hasMarkedText: true) == .notation("i"))
    }
}
