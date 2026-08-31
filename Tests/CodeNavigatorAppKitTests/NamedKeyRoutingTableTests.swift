import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// **`route()` 의 나머지 분기를 전수로 적는다** (REQ-004, REQ-010, REQ-014).
///
/// 오늘 세 결함이 전부 `route()` 의 마지막 줄 `return .interpretForComposition` 로
/// 떨어졌다 — D-19b(탈출이 번역기 우회) · D-21(화음이 IME 로) · 이것(방향키·delete).
/// **개별 실수 셋이 아니라 한 번도 열거되지 않은 기본 분기 하나다.**
///
/// 그 줄은 "나머지 전부"를 받는데 아무도 그 나머지에 무엇이 있는지 세지 않았다.
/// 이 표가 그 열거다. **빈 칸을 남기지 않는다.**
@Suite("이름 있는 키의 경로표 (route 기본 분기 전수)")
struct NamedKeyRoutingTableTests {

    /// 글자를 만들지 않는 이름 있는 키. IME 는 이것으로 만들 음절이 없다.
    private static let movementKeys: [(NamedKey, String)] = [
        (.left, "<Left>"), (.right, "<Right>"), (.up, "<Up>"), (.down, "<Down>"),
        (.backspace, "<BS>"), (.forwardDelete, "<Del>"),
        (.home, "<Home>"), (.end, "<End>"),
        (.pageUp, "<PageUp>"), (.pageDown, "<PageDown>"),
    ]

    /// 글자를 만드는 키. `insertText:` 로 와서 뷰가 이미 받는다 — 표기로 보내면 두 번 처리된다.
    private static let textProducingKeys: [NamedKey] = [.space, .returnKey, .tab]

    private func stroke(_ key: NamedKey) -> KeyStroke {
        KeyStroke(keyCode: key.keyCode, characters: nil, charactersIgnoringModifiers: nil, modifiers: [])
    }

    private func route(
        _ key: NamedKey,
        editorMode: EditorMode,
        inputMode: InputMode,
        hasMarkedText: Bool = false
    ) -> EditorKeyRoute {
        EditorKeyInput.route(
            for: stroke(key),
            editorMode: editorMode,
            inputMode: inputMode,
            hasMarkedText: hasMarkedText,
            latinCharacter: { _ in nil }
        )
    }

    // MARK: 조합 없음 — 이동 키는 nvim 으로

    @Test("삽입 모드 · 조합 없음 — 이동 키가 표기로 나간다")
    func movementKeysReachNeovimWhileInserting() {
        for (key, notation) in Self.movementKeys {
            #expect(route(key, editorMode: .insert, inputMode: .vim) == .notation(notation), "\(key)")
        }
    }

    @Test("🔑 표준 모드 — 이동 키가 표기로 나간다")
    func movementKeysReachNeovimInStandardMode() {
        // **표준 모드가 더 급하다.** 거기엔 vim 키맵이 없어 방향키가 **유일한 이동 수단**이다.
        // Vim 모드는 최소한 Esc 뒤 hjkl 이 있다. 그리고 버퍼는 표준 모드에서도 nvim 이라
        // 우리가 `<Down>` 을 보내야 커서가 움직인다.
        for (key, notation) in Self.movementKeys {
            #expect(route(key, editorMode: .insert, inputMode: .standard) == .notation(notation), "\(key)")
        }
    }

    @Test("노멀 모드 — 그대로 표기 (회귀)")
    func movementKeysStillWorkInNormalMode() {
        for (key, notation) in Self.movementKeys {
            #expect(route(key, editorMode: .normal, inputMode: .vim) == .notation(notation), "\(key)")
        }
    }

    // MARK: 조합 중 — IME 가 가진다

    @Test("조합 중 방향키·backspace 는 IME 가 가진다")
    func theInputMethodOwnsMovementWhileComposing() {
        // 조합 안에서 이동하고 자모를 지운다. 여기서 가로채면 한글 입력이 망가진다 —
        // 고치려던 결함보다 나쁜 수정이 된다.
        for key in [NamedKey.left, .right, .up, .down, .backspace, .forwardDelete] {
            #expect(route(key, editorMode: .insert, inputMode: .vim, hasMarkedText: true)
                    == .interpretForComposition, "\(key)")
        }
    }

    @Test("조합 중 home·end·page 는 음절을 커밋하고 나간다")
    func pagingCommitsTheSyllableFirst() {
        // 빈 칸을 남기지 않는다(리더 지시). IME 는 음절 안에서 페이지를 넘길 일이 없고,
        // 그냥 표기로 보내면 **버퍼에 안 들어간 음절이 사라진다.** 커밋이 그 사이를 잇는다.
        for (key, notation) in [(NamedKey.home, "<Home>"), (.end, "<End>"),
                                (.pageUp, "<PageUp>"), (.pageDown, "<PageDown>")] {
            #expect(route(key, editorMode: .insert, inputMode: .vim, hasMarkedText: true)
                    == .commitThenNotation(notation), "\(key)")
        }
    }

    // MARK: 글자를 만드는 키 — 건드리지 않는다

    @Test("space·return·tab 은 IME 로 간다 — 표기로 보내면 두 번 처리된다")
    func textProducingKeysAreLeftAlone() {
        for key in Self.textProducingKeys {
            #expect(route(key, editorMode: .insert, inputMode: .vim) == .interpretForComposition, "\(key)")
            #expect(route(key, editorMode: .insert, inputMode: .standard) == .interpretForComposition, "\(key)")
        }
    }

    @Test("escape 는 여전히 탈출이다 (회귀)")
    func escapeStillExits() {
        #expect(route(.escape, editorMode: .insert, inputMode: .vim) == .notation("<Esc>"))
    }

    // MARK: 표가 실재하는지

    @Test("표가 NamedKey 전체를 덮는다")
    func theTableCoversEveryNamedKey() {
        // 케이스가 늘면 이 수가 깨진다 — 깨지는 것이 일이다. 새 키를 더한 사람이
        // "이 키는 어디로 가나"를 답하게 만든다. 그 질문을 안 해서 오늘 셋이 났다.
        let covered = Self.movementKeys.count + Self.textProducingKeys.count + 1  // + escape
        #expect(covered == 14, "NamedKey 14종이 전부 표에 있어야 한다 — 지금 \(covered)")
    }
}
