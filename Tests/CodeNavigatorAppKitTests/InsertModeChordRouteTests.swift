import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// D-21 + D-19 후속 — **삽입 모드의 화음은 조합이 아니다** (REQ-004, REQ-014).
///
/// `route()` 를 통해서 잰다. 번역기(`EditorKeyInput.notation`)만 부르는 테스트는 26칸이
/// 전부 초록이었는데 **실제 경로가 그 번역기를 안 거쳤다** — 탈출 경로가 `KeyNotation` 을
/// 직접 불렀다. **"값이 맞다"와 "연결됐다"는 다른 질문이고, 앞의 것만 물으면 뒤의 것은
/// 영원히 안 드러난다.**
///
/// 두 결함이 한 자리다:
/// - **D-21**: 조합 문맥의 정의가 `standard || insert` 라 `⌃W`·`⌃U`·`⌃R` 이 전부 IME 로
///   가서 사라졌다. **자판과 무관 — 전 사용자.**
/// - **D-19 후속**: 탈출 경로가 원본 표기를 써서 한글 자판에서 `⌃C` 가 `<C-ㅊ>` 로 나갔다.
@Suite("삽입 모드의 화음은 조합이 아니다 (D-21, REQ-004)")
struct InsertModeChordRouteTests {

    /// 두벌식: `c` 키는 `ㅊ`, `w` 키는 `ㅈ`, `u` 키는 `ㅕ`, `r` 키는 `ㄱ`.
    private let layout: (UInt16) -> String? = { keyCode in
        switch keyCode {
        case 8: return "c"
        case 13: return "w"
        case 32: return "u"
        case 15: return "r"
        default: return nil
        }
    }

    private func stroke(_ keyCode: UInt16, _ characters: String, _ modifiers: KeyModifiers) -> KeyStroke {
        KeyStroke(keyCode: keyCode, characters: characters, charactersIgnoringModifiers: characters, modifiers: modifiers)
    }

    private func route(
        _ stroke: KeyStroke,
        editorMode: EditorMode = .insert,
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

    // ① 자판과 무관하게, 삽입 모드 화음이 nvim 에 도달한다

    @Test("ABC 에서 ⌃W·⌃U·⌃R 이 표기로 나간다 — IME 가 삼키지 않는다")
    func insertModeChordsReachNeovimOnALatinLayout() {
        // QA 가 ABC 로 실측한 것. 한글 특례가 아니라 **모든 사용자**가 겪는다.
        #expect(route(stroke(13, "w", [.control])) == .notation("<C-w>"), "⌃W 단어 지우기")
        #expect(route(stroke(32, "u", [.control])) == .notation("<C-u>"), "⌃U 줄 지우기")
        #expect(route(stroke(15, "r", [.control])) == .notation("<C-r>"), "⌃R 레지스터 붙여넣기")
    }

    // ② 🔑 핵심 — 26칸이 초록인데 경로가 죽어 있었다

    @Test("🔑 한글 자판에서 ⌃C 가 <C-c> 로 나간다 — 경로가 번역기를 거친다")
    func theEscapeChordIsTranslatedOnTheRealPath() {
        // 번역기 단독 테스트는 26칸 전부 초록이었다. 이 한 줄이 **연결**을 잰다.
        #expect(route(stroke(8, "ㅊ", [.control])) == .notation("<C-c>"))
    }

    @Test("한글 자판에서 삽입 모드 화음 전반이 번역된다")
    func everyInsertModeChordIsTranslated() {
        #expect(route(stroke(13, "ㅈ", [.control])) == .notation("<C-w>"))
        #expect(route(stroke(32, "ㅕ", [.control])) == .notation("<C-u>"))
        #expect(route(stroke(15, "ㄱ", [.control])) == .notation("<C-r>"))
    }

    // ③ 조합 중이면 음절을 먼저 커밋한다

    @Test("조합 중에 화음이 오면 음절을 먼저 커밋한다")
    func aChordDuringCompositionCommitsFirst() {
        // 버퍼에 아직 안 들어간 음절이 있다. 화음이 그것을 지우고 지나가면
        // 사용자가 친 글자가 사라진다.
        #expect(route(stroke(13, "ㅈ", [.control]), hasMarkedText: true) == .commitThenNotation("<C-w>"))
    }

    // ④ 회귀 방어 — 건드리면 안 되는 것들

    @Test("표준 모드의 화음은 시스템 편집이다 — 가로채지 않는다")
    func standardModeChordsAreLeftToTheSystem() {
        // ⌃A/⌃E 같은 emacs 바인딩은 macOS 텍스트 시스템의 것이다. vim 키맵이 아니다.
        #expect(route(stroke(8, "c", [.control]), inputMode: .standard) == .interpretForComposition)
    }

    @Test("수식어 없는 자모는 여전히 IME 로 간다 — 한글을 쳐야 한다")
    func plainJamoStillComposes() {
        #expect(route(stroke(15, "ㄱ", [])) == .interpretForComposition)
    }

    @Test("⌥ 화음은 가로채지 않는다 — 글자를 만드는 수식어다")
    func optionChordsAreNotIntercepted() {
        // ⌥e 는 é 를 시작한다. 화음으로 단정하면 의도한 문자 입력을 가로챈다.
        #expect(route(stroke(14, "´", [.option])) == .interpretForComposition)
    }

    @Test("🔑 Vim 모드의 ⌘ 조합은 표기로 안 나간다 — 라우팅이 메뉴 상태에 매달리면 안 된다")
    func commandChordsAreNotRoutedToNeovim() {
        // **비활성 `NSMenuItem` 은 자기 단축키를 소비하지 않는다.** ⌘ 를 화음에 넣으면
        // Vim 모드에서 비활성인 ⌘V 가 keyDown 까지 떨어져 `<D-v>` 로 나가고, 표준
        // 모드에서는 메뉴가 먹는다 — **같은 키가 메뉴 활성 상태에 따라 다른 곳으로 간다.**
        //
        // 지금 무해한 이유는 nvim 이 `<D-v>` 를 기본 매핑 안 하기 때문인데, 그건 우리가
        // 통제하는 조건이 아니다. ADR-0102 의 라우팅 규칙(`⌘면 앱`)을 지킨다.
        //
        // 이 테스트는 다음 사람이 "화음인데 왜 빠졌지" 하며 되살리는 것을 막는다.
        #expect(route(stroke(9, "v", [.command])) == .interpretForComposition,
                "⌘ 조합이 표기로 나가면 라우팅이 메뉴 활성 상태에 의존하게 된다")
        #expect(route(stroke(9, "ㅍ", [.command])) == .interpretForComposition,
                "한글 자판에서도 마찬가지다 — ⌘ 는 앱의 것이지 nvim 의 것이 아니다")
    }

    @Test("Esc 는 화음이 아니어도 여전히 탈출한다")
    func escapeStillLeavesInsertMode() {
        let escape = KeyStroke(keyCode: 53, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", modifiers: [])
        #expect(route(escape) == .notation("<Esc>"))
    }
}
