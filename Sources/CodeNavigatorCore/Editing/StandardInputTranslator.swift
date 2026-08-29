import Foundation

/// Translates macOS key presses into Neovim key notation for standard mode (REQ-010 AC-2).
///
/// Standard mode is a translation layer, not a second editor: the buffer, the undo history and
/// the dirty state stay in Neovim (INV-3). That is why every mapping here comes out as keys to
/// send rather than as an edit to apply.
///
/// Returning nil means "not mine" — the app handles that combination (a menu shortcut, say)
/// and nothing is forwarded to Neovim.
public enum StandardInputTranslator {

    /// The system clipboard is Vim's `+` register. Whether these act on a selection or a single
    /// character is decided by the mode Neovim is in, which the editor session owns.
    private static let copyToSystemClipboardKeys = "\"+y"
    private static let cutToSystemClipboardKeys = "\"+d"
    private static let pasteFromSystemClipboardKeys = "\"+p"

    private static let undoKeys = "u"
    private static let redoKeys = "<C-r>"
    private static let saveKeys = ":w<CR>"
    private static let selectAllKeys = "ggVG"
    private static let documentStartKeys = "gg"
    private static let documentEndKeys = "G"

    public static func translate(_ event: StandardKeyEvent) -> String? {
        switch event.keyCode {
        case .upArrow, .downArrow, .leftArrow, .rightArrow:
            return translateArrow(event.keyCode, modifiers: event.modifiers)

        case .home, .end, .deleteBackward, .deleteForward, .enter, .tab, .escape:
            return translateNamedKey(event.keyCode, modifiers: event.modifiers)

        case .character:
            return translateCharacters(event.characters, modifiers: event.modifiers)
        }
    }

    private static func translateArrow(_ keyCode: KeyCodeName, modifiers: KeyModifiers) -> String? {
        // ⌘ jumps to the ends of the line and of the document, as everywhere else on macOS.
        if modifiers == .command {
            switch keyCode {
            case .leftArrow: return "<Home>"
            case .rightArrow: return "<End>"
            case .upArrow: return documentStartKeys
            case .downArrow: return documentEndKeys
            default: return nil
            }
        }

        // ⌥ moves by word. Neovim spells that as <C-Left> / <C-Right>.
        if modifiers == .option {
            switch keyCode {
            case .leftArrow: return "<C-Left>"
            case .rightArrow: return "<C-Right>"
            default: return nil
            }
        }

        // Bare arrows move; ⇧+arrow extends the selection.
        guard modifiers.isEmpty || modifiers == .shift else {
            return nil
        }

        let directionName: String
        switch keyCode {
        case .upArrow: directionName = "Up"
        case .downArrow: directionName = "Down"
        case .leftArrow: directionName = "Left"
        case .rightArrow: directionName = "Right"
        default: return nil
        }

        let selectionPrefix = modifiers.contains(.shift) ? "S-" : ""

        return "<\(selectionPrefix)\(directionName)>"
    }

    /// These keys mean one thing each. A modifier on top of them is an app shortcut, not text.
    private static func translateNamedKey(_ keyCode: KeyCodeName, modifiers: KeyModifiers) -> String? {
        guard modifiers.isEmpty else {
            return nil
        }

        switch keyCode {
        case .home: return "<Home>"
        case .end: return "<End>"
        case .deleteBackward: return "<BS>"
        case .deleteForward: return "<Del>"
        case .enter: return "<CR>"
        case .tab: return "<Tab>"
        case .escape: return "<Esc>"
        default: return nil
        }
    }

    private static func translateCharacters(_ characters: String, modifiers: KeyModifiers) -> String? {
        guard !characters.isEmpty else {
            return nil
        }

        if modifiers.contains(.command) {
            return translateCommandShortcut(characters, modifiers: modifiers)
        }

        // ⌥ and ⌃ combinations have no standard-mode meaning. ⇧ is already baked into
        // `characters`, so a plain character press falls through and is typed as-is —
        // that is REQ-010 AC-5: "i", ":" and "hjkl" are text here, not commands.
        guard !modifiers.contains(.option), !modifiers.contains(.control) else {
            return nil
        }

        return escapedForKeyNotation(characters)
    }

    private static func translateCommandShortcut(
        _ characters: String,
        modifiers: KeyModifiers
    ) -> String? {
        guard !modifiers.contains(.option), !modifiers.contains(.control) else {
            return nil
        }

        switch characters.lowercased() {
        case "c": return copyToSystemClipboardKeys
        case "x": return cutToSystemClipboardKeys
        case "v": return pasteFromSystemClipboardKeys
        case "z": return modifiers.contains(.shift) ? redoKeys : undoKeys
        case "s": return saveKeys
        case "a": return selectAllKeys
        default: return nil
        }
    }

    /// "<" opens a key name in Neovim notation, so a typed "<" has to be spelled "<lt>" or the
    /// next characters would be read as a key name.
    private static func escapedForKeyNotation(_ characters: String) -> String {
        characters.replacingOccurrences(of: "<", with: "<lt>")
    }
}
