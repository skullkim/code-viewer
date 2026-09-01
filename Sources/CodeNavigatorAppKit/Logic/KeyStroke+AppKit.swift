import AppKit

extension KeyModifiers {
    /// The modifiers an AppKit event is holding.
    ///
    /// This reads `modifierFlags` and nothing else, which matters more than it looks: every
    /// kind of event answers `modifierFlags`, while `keyCode`, `characters`, and
    /// `charactersIgnoringModifiers` are keyboard-only. AppKit does not return a default for
    /// those on a mouse event — it raises `NSInternalInconsistencyException`. Reading the
    /// modifiers of a click by building a whole `KeyStroke` therefore threw before the click
    /// could be forwarded, so REQ-017 was dead in the shipped application while the engine
    /// underneath it was correct and covered by live tests. Keeping the modifier reading on
    /// its own type is what stops that from coming back.
    init(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: KeyModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }

    /// Held modifiers in the notation Neovim's mouse input expects.
    ///
    /// Command is deliberately absent: `nvim_input_mouse` takes shift, control and alt, and
    /// Command belongs to the menu bar (REQ-011 AC-2).
    var neovimModifierNotation: String {
        var parts: [String] = []
        if contains(.shift) { parts.append("S") }
        if contains(.control) { parts.append("C") }
        if contains(.option) { parts.append("A") }
        return parts.joined(separator: "-")
    }
}

extension KeyStroke {
    /// Builds a stroke from an AppKit **key** event.
    ///
    /// Both character forms are carried across because they answer different questions:
    /// `characters` is what the key produced (Shift-semicolon is a colon, and Vim's command
    /// line is unreachable without it), `charactersIgnoringModifiers` is what the key is
    /// called (Control-O is named after "o").
    ///
    /// Only key events belong here — the character properties raise on every other kind.
    /// `KeyModifiers.init(_:)` carries the failure that taught us so.
    init(_ event: NSEvent) {
        self.init(
            keyCode: event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: KeyModifiers(event)
        )
    }
}
