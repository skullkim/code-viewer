import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Recovering Vim's command keys from a non-Latin keyboard (REQ-014, B안).
///
/// With a Korean input source, `characters` is a jamo: pressing the `i` key yields `ㅑ`, so
/// Neovim never enters insert mode and normal mode is unusable. Measured with a keyDown
/// probe, and again in a standalone spike:
///
///     keyCode=34  characters=ㅑ  UCKeyTranslate(ASCII layout)=i
///
/// The fix translates the *physical key* rather than switching the system input source.
/// That matters beyond convenience: switching a system-wide setting can fail to be undone
/// (a SIGKILL leaves the user in English, measured), while translating changes no global
/// state at all — so there is nothing to restore and nothing to leave behind.
@Suite("라틴 키 복원 — 한글 자판에서 Vim 명령키를 되찾는다 (REQ-014)")
struct LatinKeyTranslationTests {

    /// Stands in for the ASCII-capable layout, so these rules are testable without touching
    /// the keyboard of the machine running the tests.
    private let layout: (UInt16) -> String? = { keyCode in
        switch keyCode {
        case 34: return "i"
        case 40: return "k"
        case 4: return "h"
        case 5: return "g"
        case 41: return ";"
        default: return nil
        }
    }

    private func stroke(
        keyCode: UInt16,
        characters: String,
        modifiers: KeyModifiers = []
    ) -> KeyStroke {
        KeyStroke(
            keyCode: keyCode,
            characters: characters,
            charactersIgnoringModifiers: characters,
            modifiers: modifiers
        )
    }

    private func notation(
        _ stroke: KeyStroke,
        editorMode: EditorMode = .normal,
        inputMode: InputMode = .vim
    ) -> String? {
        EditorKeyInput.notation(
            for: stroke,
            editorMode: editorMode,
            inputMode: inputMode,
            latinCharacter: layout
        )
    }

    // MARK: 노멀 모드 — 번역한다

    @Test("노멀 모드에서 자모가 원래 명령키로 번역된다")
    func normalModeRecoversTheCommandKey() {
        #expect(notation(stroke(keyCode: 34, characters: "ㅑ")) == "i")
        #expect(notation(stroke(keyCode: 40, characters: "ㅏ")) == "k")
        #expect(notation(stroke(keyCode: 4, characters: "ㅗ")) == "h")
    }

    @Test("이미 라틴 문자면 번역이 아무것도 바꾸지 않는다")
    func latinInputIsUnchanged() {
        // The control case from the spike: under ABC the translation returns the same
        // letter, so this path must be a no-op rather than a second source of truth.
        #expect(notation(stroke(keyCode: 34, characters: "i")) == "i")
        #expect(notation(stroke(keyCode: 40, characters: "k")) == "k")
    }

    @Test("이미 라틴이면 물리 키가 달라도 받은 글자를 그대로 쓴다")
    func aLatinCharacterIsTrustedOverThePhysicalKey() {
        // The intervention is narrow on purpose. Dvorak and other Latin layouts already
        // deliver the character the user expects; translating them from the key code would
        // silently override the layout they chose. Only non-ASCII input is a problem, so
        // only non-ASCII input is touched.
        #expect(notation(stroke(keyCode: 40, characters: "t")) == "t")
    }

    @Test("⌃ 코드도 번역된다 — 한글 자판에서 ⌃ㅗ 가 아니라 <C-h> 여야 한다")
    func controlChordsAreTranslatedToo() {
        // Control chords are the ones REQ-011 AC-2 exists to protect, and they arrive with
        // jamo just like plain keys do. Translating only unmodified presses would leave
        // every ^h, ^o, ^r broken on a Korean keyboard.
        #expect(notation(stroke(keyCode: 4, characters: "ㅗ", modifiers: [.control])) == "<C-h>")
    }

    @Test("번역할 수 없는 키는 원래 동작 그대로 둔다")
    func anUntranslatableKeyFallsBack() {
        // Function keys, arrows and anything the layout has no answer for. Dropping them
        // would be worse than passing them through unchanged.
        #expect(notation(stroke(keyCode: 200, characters: "ø")) == "ø")
    }

    // MARK: 삽입 모드 — 번역하지 않는다

    @Test("삽입 모드에서는 번역하지 않는다 — 한글을 치는 자리다")
    func insertModeIsLeftAlone() {
        // Translating here would make it impossible to type Korean at all, which is the
        // opposite of what this feature is for.
        #expect(notation(stroke(keyCode: 34, characters: "ㅑ"), editorMode: .insert) == "ㅑ")
        #expect(notation(stroke(keyCode: 40, characters: "ㅏ"), editorMode: .insert) == "ㅏ")
    }

    @Test("표준 모드에서는 어느 모드든 번역하지 않는다 (REQ-010)")
    func standardModeNeverTranslates() {
        // In standard mode every key is typing; there are no command keys to protect.
        for mode in [EditorMode.normal, .insert, .visual] {
            #expect(notation(stroke(keyCode: 34, characters: "ㅑ"), editorMode: mode, inputMode: .standard) == "ㅑ")
        }
    }

    @Test("비주얼·명령행 모드는 번역한다 — 거기도 명령키가 산다")
    func visualAndCommandLineAreTranslated() {
        // `:` opens the command line and its contents are commands, not prose. Leaving
        // those untranslated would break `:w` on a Korean keyboard.
        #expect(notation(stroke(keyCode: 40, characters: "ㅏ"), editorMode: .visual) == "k")
        #expect(notation(stroke(keyCode: 4, characters: "ㅗ"), editorMode: .commandLine) == "h")
    }

    @Test("⌘ 조합은 앱이 가져가므로 여기 오지 않는다")
    func commandCombinationsAreTheApplicationsAndNotSentOn() {
        // ADR-0102: the menu claims Command. This is asserted so that a future change which
        // starts forwarding them has to face the question deliberately.
        #expect(KeyNotation.isApplicationShortcut(stroke(keyCode: 34, characters: "ㅑ", modifiers: [.command])))
    }
}
