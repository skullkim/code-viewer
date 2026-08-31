import CodeNavigatorContract

/// Decides what string a key press sends to Neovim (REQ-014).
///
/// With a Korean input source the event's `characters` is a jamo — pressing the `i` key
/// yields `ㅑ`, so Neovim never enters insert mode and normal mode is unusable. Measured
/// with a keyDown probe in the running application, and again in a standalone spike:
///
///     keyCode=34  characters=ㅑ  UCKeyTranslate(ASCII-capable layout)=i
///
/// The application recovers the command key by translating the **physical key**, and does
/// not touch the system input source. The difference is not convenience: switching a
/// system-wide setting can fail to be undone — a SIGKILL leaves the user typing English
/// after the application is gone, measured by backend-junior — while translating changes no
/// global state, so there is nothing to restore and nothing to leave behind.
public enum EditorKeyInput {

    /// The notation for a press, translated when the moment calls for commands.
    ///
    /// `latinCharacter` is injected so the rule is testable without touching the keyboard
    /// of the machine running the tests.
    public static func notation(
        for stroke: KeyStroke,
        editorMode: EditorMode,
        inputMode: InputMode,
        latinCharacter: (UInt16) -> String?
    ) -> String? {
        guard shouldTranslate(stroke, editorMode: editorMode, inputMode: inputMode) else {
            return KeyNotation.notation(for: stroke)
        }
        // Only when the press produced something Neovim cannot read as a command. A Latin
        // character is already the command key, so translating it would be a second source
        // of truth for keys that never had a problem — and would quietly override layouts
        // like Dvorak, where the character the user expects is the one they already got.
        guard needsTranslation(stroke) else {
            return KeyNotation.notation(for: stroke)
        }
        guard let latin = latinCharacter(stroke.keyCode), !latin.isEmpty else {
            // Function keys, arrows, and anything the layout cannot name. Passing the press
            // through unchanged is better than dropping it.
            return KeyNotation.notation(for: stroke)
        }
        return KeyNotation.notation(for: stroke.replacingCharacters(with: latin))
    }

    /// Whether this moment is about commands rather than prose.
    ///
    /// Insert mode is where Korean gets typed, so it is left alone — translating there
    /// would make Korean impossible to enter, which is the opposite of the point. Standard
    /// mode is typing everywhere and has no command keys to protect (REQ-010).
    ///
    /// Visual and command-line modes *are* translated: `:w` is a command even though the
    /// user is typing it.
    static func shouldTranslate(_ stroke: KeyStroke, editorMode: EditorMode, inputMode: InputMode) -> Bool {
        guard inputMode == .vim else { return false }

        // **화음은 산문이 아니다.** 삽입 모드를 통째로 비켜 두면 한글 입력은 지켜지지만
        // `⌃C`·`⌃W`·`⌃R` 처럼 삽입 모드 *안에서* 쓰는 명령이 전부 자모 이름으로 나간다
        // (D-19). Neovim 은 화음에서 ASCII 만 이해하므로 그건 없는 키를 보내는 것이다.
        //
        // ⌥ 는 뺀다 — macOS 에서 ⌥ 는 *글자를 만드는* 수식어라(⌥e 는 é 를 시작한다)
        // 화음으로 단정하면 의도한 문자 입력을 가로챈다. ⌃·⌘ 은 글자를 만들지 않는다.
        if stroke.modifiers.contains(.control) || stroke.modifiers.contains(.command) {
            return true
        }

        return editorMode != .insert
    }

    /// Whether the press arrived as something other than a plain ASCII character.
    ///
    /// Jamo, Cyrillic, kana — anything Neovim will not recognise as a command. Keeping the
    /// intervention this narrow means every keyboard that already worked keeps working
    /// through exactly the path it used before.
    static func needsTranslation(_ stroke: KeyStroke) -> Bool {
        let base = stroke.modifiers.contains(.control)
            || stroke.modifiers.contains(.option)
            || stroke.modifiers.contains(.command)
            ? stroke.charactersIgnoringModifiers
            : stroke.characters
        guard let base, !base.isEmpty else { return false }
        return !base.unicodeScalars.allSatisfy { $0.isASCII }
    }
}

/// Which path a key press takes into Neovim (REQ-014 2단계, D-13).
public enum EditorKeyRoute: Sendable, Hashable {
    /// Hand the press to the input context so the IME can compose it. What comes back
    /// through `insertText` is what gets sent.
    case interpretForComposition
    /// Send this notation straight through — no composition is wanted here.
    case notation(String)
    /// Commit whatever is being composed, *then* send this notation.
    case commitThenNotation(String)
}

extension EditorKeyInput {

    /// Keys that leave insert mode.
    ///
    /// All three, not just Escape: Vim users leave insert with `⌃[` and `⌃C` as readily,
    /// and handling only Escape would lose the composing syllable through the door nobody
    /// thought to close.
    /// macOS 가 **명령으로** 전달하는 키 — `doCommandBySelector` 로 온다.
    ///
    /// 우리는 그 메서드를 구현하지 않으므로 여기 있는 키는 전부 **조용히 사라진다.**
    /// 그래서 전부 표기로 보낸다.
    ///
    /// **근거는 시스템의 표다**(측정 2026-08-31, `plutil -p`):
    /// `/System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict`
    /// ```
    /// "\r" => insertNewline:      "\t" => insertTab:
    /// backspace => deleteBackward:    arrows => moveUp:/moveDown:/moveLeft:/moveRight:
    /// ```
    /// **`space` 는 그 표에 없다** — 그래서 진짜 글자로 `insertText:` 를 통해 온다.
    ///
    /// ⚠ 한때 `return`·`tab` 이 여기 없었다. "셋 다 글자를 만든다"는 **확인되지 않은
    /// 분류**를 근거로 뺐고, 그래서 Enter 가 죽었다(사용자 보고). 표가 있어도 **칸의 값이
    /// 틀리면 표가 그 오류를 고정한다** — 근거는 "누가 그렇게 말했다"가 아니라 "무엇으로
    /// 확인했다"여야 한다.
    static let commandKeys: Set<NamedKey> = [
        .left, .right, .up, .down,
        .backspace, .forwardDelete,
        .home, .end, .pageUp, .pageDown,
        .returnKey, .tab,
    ]

    /// 조합 중에는 **IME 의 것**인 키. 조합 안에서 이동하고 자모를 지운다.
    ///
    /// home·end·page 는 여기 없다 — 음절 안에서 페이지를 넘길 일이 없다. 그것들은 음절을
    /// 커밋하고 나간다.
    static let compositionKeys: Set<NamedKey> = [
        .left, .right, .up, .down, .backspace, .forwardDelete,
    ]

    static func isInsertModeExit(_ stroke: KeyStroke) -> Bool {
        if NamedKey.named(forKeyCode: stroke.keyCode) == .escape {
            return true
        }
        guard stroke.modifiers.contains(.control) else { return false }
        // The *physical* key, not the character it produced. Reading the character made
        // this layout-dependent: a Korean input source turns `⌃[` into `ㅐ` and `⌃C` into
        // `ㅊ`, so neither was ever recognised as an exit. `⌃C` therefore could not leave
        // insert mode at all, and `⌃[` only appeared to work because the failed detection
        // handed it to the input method, which committed the syllable and passed the escape
        // character through — the right result by the wrong route (QA measured all three).
        //
        // Escape above is already matched on its key code; these now use the same axis.
        return stroke.keyCode == KeyCode.leftBracket || stroke.keyCode == KeyCode.letterC
    }

    /// Physical key codes for the two chords that leave insert mode.
    ///
    /// Named rather than written as bare numbers at the comparison, because `33` and `8`
    /// say nothing about which keys they are.
    enum KeyCode {
        static let leftBracket: UInt16 = 33
        static let letterC: UInt16 = 8
    }

    /// Chooses the path, and guards the moment a syllable can be lost.
    ///
    /// The rule that needed thinking about is the last one. Composition holds text that is
    /// not in the buffer yet, so leaving insert mode mid-composition throws it away — the
    /// user typed `한`, pressed Escape believing it was written, and it never existed. That
    /// is the same class of silent loss this change exists to remove, so the exit commits
    /// first and transitions after.
    public static func route(
        for stroke: KeyStroke,
        editorMode: EditorMode,
        inputMode: InputMode,
        hasMarkedText: Bool,
        latinCharacter: (UInt16) -> String?
    ) -> EditorKeyRoute {
        let isComposingContext = inputMode == .standard || editorMode == .insert
        guard isComposingContext else {
            // Commands. The physical key is translated, because `ㅑ` is not `i`.
            let notation = self.notation(
                for: stroke,
                editorMode: editorMode,
                inputMode: inputMode,
                latinCharacter: latinCharacter
            )
            return .notation(notation ?? "")
        }

        // Standard mode has no insert mode to leave, so Escape belongs to the IME — it
        // cancels the composition, which is what pressing it asked for.
        //
        // The exit check comes *before* the composition check, and that order is the whole
        // point. With `hasMarkedText` in front, an exit key pressed while nothing was being
        // composed — which is every time someone types plain ASCII — fell through to the
        // input context, which swallowed it as `doCommand cancelOperation:`. Nobody could
        // leave insert mode: no save, no command, only force quit. It had nothing to do
        // with Korean, and every test before it supplied `hasMarkedText: true`.
        // **화음은 조합이 아니다** — 삽입 모드라도(D-21, D-19 후속).
        //
        // 이 분기는 한때 탈출 3종(`Esc`·`⌃[`·`⌃C`)만 통과시켰다. 그래서 `⌃W`(단어 지우기)·
        // `⌃U`·`⌃R`·`⌃O`·`⌃N`/`⌃P` 가 전부 IME 로 가서 **사라졌다** — 자판과 무관하게
        // 모든 사용자에게. IME 는 그 화음으로 만들 글자가 없으니 조용히 삼킨다.
        //
        // ⌥ 는 뺀다 — macOS 에서 ⌥ 는 *글자를 만드는* 수식어라(⌥e 는 é 를 시작한다)
        // 화음으로 단정하면 의도한 문자 입력을 가로챈다.
        //
        // **⌘ 도 뺀다. 이유가 다르다** — 비활성 `NSMenuItem` 은 자기 단축키를 소비하지
        // 않는다(`performKeyEquivalent` 가 false 를 주고 이벤트가 응답자 사슬로 내려온다).
        // ⌘ 를 화음에 넣으면 Vim 모드에서 REQ-010 AC-5 로 비활성인 ⌘V 가 keyDown 까지
        // 떨어져 `<D-v>` 로 nvim 에 가고, 표준 모드에서는 메뉴가 먹는다. **같은 키가
        // 메뉴 활성 상태에 따라 다른 곳으로 간다** — 그 상태는 모드·세션·프로젝트 유무로
        // 계속 바뀐다. 지금 무해한 이유가 "nvim 이 `<D-v>` 를 기본 매핑 안 해서"인데,
        // 그건 우리가 통제하는 조건이 아니다.
        //
        // ADR-0102 가 라우팅을 규칙 하나(`⌘면 앱`)로 압축한 것이 위임 근거였다. 여기서
        // ⌘ 를 가져가면 규칙이 둘이 되고 둘째는 숨은 조건을 갖는다 — 새 메뉴 항목을
        // 추가하는 사람이 키 라우팅까지 생각해야 한다.
        //
        // 표준 모드는 `inputMode == .vim` 이 걸러 낸다. 거기서 `⌃A`·`⌃E` 는 vim 키맵이
        // 아니라 macOS 텍스트 시스템의 것이고, 우리가 가로챌 것이 아니다.
        let isChord = stroke.modifiers.contains(.control)

        // **이동 키도 산문이 아니다.** IME 는 방향키나 delete 로 만들 음절이 없고, 그래서
        // 입력 컨텍스트는 그것들을 `doCommandBySelector` 로 넘긴다 — 우리는 그것을 구현하지
        // 않으므로 **조용히 사라진다.** 사용자 보고가 정확히 이것이었다.
        //
        // `space` 만 뺀다. 그것만이 진짜 글자로 `insertText:` 를 통해 오고 뷰가 이미
        // 받는다 — 표기로도 보내면 한 번의 입력이 두 번 처리된다.
        //
        // 조합 중이면 방향키·backspace 는 **IME 의 것**이다. 조합 안에서 이동하고 자모를
        // 지운다 — 여기서 가로채면 한글 입력이 망가지고, 그건 고치려던 결함보다 나쁘다.
        // home·end·page 는 음절 안에서 쓸 일이 없으므로 커밋하고 내보낸다(아래 공통 경로).
        let named = NamedKey.named(forKeyCode: stroke.keyCode)
        let isCommandKey = named.map(Self.commandKeys.contains) ?? false
        let belongsToCompositionNow = hasMarkedText && named.map(Self.compositionKeys.contains) ?? false

        if isCommandKey, !belongsToCompositionNow {
            guard let notation = KeyNotation.notation(for: stroke) else {
                return .interpretForComposition
            }
            return hasMarkedText ? .commitThenNotation(notation) : .notation(notation)
        }

        if inputMode == .vim, isChord || isInsertModeExit(stroke) {
            // **번역기를 거친다.** 예전엔 `KeyNotation` 을 직접 불러서, 한글 자판의 `⌃C` 가
            // `<C-ㅊ>` 로 나갔다 — 번역기는 옳은데 이 경로가 그것을 안 거쳤다. 값이 맞는
            // 것과 연결된 것은 다른 문제고, 번역기만 재는 테스트는 그 차이를 못 본다.
            guard let notation = self.notation(
                for: stroke,
                editorMode: editorMode,
                inputMode: inputMode,
                latinCharacter: latinCharacter
            ) else {
                return .interpretForComposition
            }
            // Composing: the syllable is not in the buffer yet, so it goes first.
            // Not composing: there is nothing to commit and the key just leaves.
            return hasMarkedText ? .commitThenNotation(notation) : .notation(notation)
        }

        return .interpretForComposition
    }
}
