import AppKit

extension KeyStroke {
    /// Builds a stroke from an AppKit event.
    ///
    /// Both character forms are carried across because they answer different questions:
    /// `characters` is what the key produced (Shift-semicolon is a colon, and Vim's command
    /// line is unreachable without it), `charactersIgnoringModifiers` is what the key is
    /// called (Control-O is named after "o").
    init(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: KeyModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }

        self.init(
            keyCode: event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: modifiers
        )
    }

    /// Held modifiers in the notation Neovim's mouse input expects.
    var neovimModifierNotation: String {
        var parts: [String] = []
        if modifiers.contains(.shift) { parts.append("S") }
        if modifiers.contains(.control) { parts.append("C") }
        if modifiers.contains(.option) { parts.append("A") }
        return parts.joined(separator: "-")
    }
}
