import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// D-19 — 삽입 모드의 **화음**은 산문이 아니다 (REQ-014, REQ-010).
///
/// QA 가 `⌃C` 로 삽입 모드를 못 벗어나는 것을 재현했다(한글 입력 소스, 조합 여부 무관).
/// `isInsertModeExit` 는 키코드로 보므로 탈출로 **인식은 된다.** 그런데 `KeyNotation` 이
/// `charactersIgnoringModifiers` 로 이름을 붙여 `<C-ㅊ>` 를 보낸다 — **인식해 놓고 Neovim 이
/// 모르는 말로 번역해 보낸다.**
///
/// **범위는 `⌃C` 하나가 아니다.** 라틴이 아닌 모든 입력 소스(한·일·중·러·희랍)에서
/// `⌃A`~`⌃Z` 전부가 같은 이유로 죽는다. Neovim 표기는 화음에서 ASCII 만 이해한다.
///
/// ⚠ `⌃[` 가 살아 있던 것을 반증으로 쓰면 안 된다 — 두벌식은 *글자* 키만 자모로 바꾸고
/// `[`·`]`·`;` 는 그대로 둔다. **우연히 옳게 번역됐을 뿐**이고, 오늘 그 우연에 두 번 속았다.
@Suite("삽입 모드의 화음은 자판과 무관하다 (D-19, REQ-014)")
struct ChordKeyTranslationTests {

    /// 두벌식 자판의 `⌃A`~`⌃Z`. 왼쪽이 물리 키코드, 가운데가 한글 입력 소스가 내주는 자모.
    private static let koreanLetterRows: [(keyCode: UInt16, jamo: String, latin: String)] = [
        (0, "ㅁ", "a"), (11, "ㅠ", "b"), (8, "ㅊ", "c"), (2, "ㅇ", "d"),
        (14, "ㄷ", "e"), (3, "ㄹ", "f"), (5, "ㅎ", "g"), (4, "ㅗ", "h"),
        (34, "ㅑ", "i"), (38, "ㅓ", "j"), (40, "ㅏ", "k"), (37, "ㅣ", "l"),
        (46, "ㅡ", "m"), (45, "ㅜ", "n"), (31, "ㅐ", "o"), (35, "ㅔ", "p"),
        (12, "ㅂ", "q"), (15, "ㄱ", "r"), (1, "ㄴ", "s"), (17, "ㅅ", "t"),
        (32, "ㅕ", "u"), (9, "ㅍ", "v"), (13, "ㅈ", "w"), (7, "ㅌ", "x"),
        (16, "ㅛ", "y"), (6, "ㅋ", "z"),
    ]

    private let layout: (UInt16) -> String? = { keyCode in
        koreanLetterRows.first { $0.keyCode == keyCode }?.latin
    }

    private func chord(keyCode: UInt16, jamo: String, _ modifiers: KeyModifiers) -> KeyStroke {
        KeyStroke(
            keyCode: keyCode,
            characters: jamo,
            charactersIgnoringModifiers: jamo,
            modifiers: modifiers
        )
    }

    private func notation(_ stroke: KeyStroke, editorMode: EditorMode) -> String? {
        EditorKeyInput.notation(
            for: stroke,
            editorMode: editorMode,
            inputMode: .vim,
            latinCharacter: layout
        )
    }

    @Test("삽입 모드에서 ⌃A~⌃Z 전부가 라틴 이름으로 나간다")
    func everyControlChordSurvivesANonLatinLayout() {
        for row in Self.koreanLetterRows {
            let sent = notation(chord(keyCode: row.keyCode, jamo: row.jamo, [.control]), editorMode: .insert)
            #expect(sent == "<C-\(row.latin)>",
                    "⌃\(row.latin.uppercased()) 가 \(sent ?? "nil") 로 나갔다 — Neovim 은 자모 화음을 모른다")
        }
    }

    @Test("노멀 모드에서도 마찬가지다")
    func theSameHoldsInNormalMode() {
        let sent = notation(chord(keyCode: 8, jamo: "ㅊ", [.control]), editorMode: .normal)
        #expect(sent == "<C-c>")
    }

    @Test("🔑 수식어 없는 자모는 삽입 모드에서 그대로 둔다 — 아니면 한글을 못 친다")
    func plainJamoIsLeftAloneInInsertMode() {
        // 반대 방향의 방어선. 화음을 번역하려다 **모든** 자모를 번역하면 한글 입력이
        // 불가능해진다 — 그건 이 기능이 막으려던 것보다 나쁜 결함이다.
        let sent = notation(chord(keyCode: 15, jamo: "ㄱ", []), editorMode: .insert)
        #expect(sent == "ㄱ", "수식어 없는 자모까지 번역하면 한글을 아예 못 친다")
    }

    @Test("라틴 자판의 화음은 건드리지 않는다")
    func latinChordsAreUnchanged() {
        let ascii = KeyStroke(keyCode: 8, characters: "c", charactersIgnoringModifiers: "c", modifiers: [.control])
        #expect(notation(ascii, editorMode: .insert) == "<C-c>")
    }
}
