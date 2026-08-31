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
        guard shouldTranslate(editorMode: editorMode, inputMode: inputMode) else {
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
    static func shouldTranslate(editorMode: EditorMode, inputMode: InputMode) -> Bool {
        guard inputMode == .vim else { return false }
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
        if inputMode == .vim, isInsertModeExit(stroke) {
            guard let notation = KeyNotation.notation(for: stroke) else {
                return .interpretForComposition
            }
            // Composing: the syllable is not in the buffer yet, so it goes first.
            // Not composing: there is nothing to commit and the key just leaves.
            return hasMarkedText ? .commitThenNotation(notation) : .notation(notation)
        }

        return .interpretForComposition
    }
}
