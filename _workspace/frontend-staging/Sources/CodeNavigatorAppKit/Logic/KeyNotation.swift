/// Turns a key press into Neovim key notation, and says whether the application takes the
/// key for itself instead of forwarding it.
///
/// The routing rule is deliberately coarse (design §3 W-9): the application claims
/// Command combinations and nothing else. Every Control chord Vim relies on — ^O, ^R, ^V,
/// ^W — therefore reaches Neovim untouched, which is how REQ-011 AC-2 stops being a matter
/// of remembering to check and starts being a property of the design.
///
/// The notation produced here does not depend on the input mode. The same press yields the
/// same string in Vim and standard mode; interpreting it is the edit session's job
/// (REQ-010), which keeps buffer state in one owner.
public enum KeyNotation {

    /// The notation for a key press, or nil when the press carries nothing to send.
    public static func notation(for stroke: KeyStroke) -> String? {
        let prefix = chordPrefix(for: stroke.modifiers)

        if let named = NamedKey.named(forKeyCode: stroke.keyCode) {
            let shift = stroke.modifiers.contains(.shift) ? "S-" : ""
            return "<\(prefix)\(shift)\(named.neovimName)>"
        }

        guard let base = baseCharacter(for: stroke), !base.isEmpty else {
            return nil
        }

        guard !prefix.isEmpty else {
            // "<" is the one literal that has to be escaped, or Neovim reads it as the
            // start of a notation sequence.
            return base == "<" ? "<lt>" : base
        }

        // On a chord the base is the unshifted key name, so Shift survives as a prefix.
        let shift = stroke.modifiers.contains(.shift) ? "S-" : ""
        return "<\(prefix)\(shift)\(base)>"
    }

    /// True when the application handles the press itself instead of forwarding it.
    public static func isApplicationShortcut(_ stroke: KeyStroke) -> Bool {
        stroke.modifiers.contains(.command)
    }

    private static func chordPrefix(for modifiers: KeyModifiers) -> String {
        var prefix = ""
        if modifiers.contains(.control) { prefix += "C-" }
        if modifiers.contains(.option) { prefix += "M-" }
        if modifiers.contains(.command) { prefix += "D-" }
        return prefix
    }

    private static func baseCharacter(for stroke: KeyStroke) -> String? {
        // A chord is named after the key, not after what the key produced: Control-O stays
        // "o". A plain press is the character it produced: Shift-semicolon is a colon, and
        // taking the unshifted key there would put Vim's command line out of reach.
        let namedAfterTheKey = stroke.modifiers.contains(.control)
            || stroke.modifiers.contains(.option)
            || stroke.modifiers.contains(.command)
        return namedAfterTheKey ? stroke.charactersIgnoringModifiers : stroke.characters
    }
}
