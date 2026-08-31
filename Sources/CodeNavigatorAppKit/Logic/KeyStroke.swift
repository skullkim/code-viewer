/// The modifier keys held during a key press.
///
/// Declared here rather than reused from AppKit so the notation logic stays a pure value
/// transformation that tests can drive without constructing window-server events.
public struct KeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
}

/// A key press, reduced to what the notation needs.
///
/// Both character forms are kept because they answer different questions. `characters` is
/// what the key produced — Shift-semicolon is a colon. `charactersIgnoringModifiers` is
/// what the key is called — Control-O is named after "o" whatever it produced.
public struct KeyStroke: Sendable, Hashable {
    public let keyCode: UInt16
    public let characters: String?
    public let charactersIgnoringModifiers: String?
    public let modifiers: KeyModifiers

    public init(
        keyCode: UInt16,
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifiers: KeyModifiers
    ) {
        self.keyCode = keyCode
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.modifiers = modifiers
    }
}

/// A key that Neovim addresses by name rather than by the character it produces.
public enum NamedKey: Sendable, Hashable, CaseIterable {
    case returnKey
    case tab
    case backspace
    case forwardDelete
    case escape
    case space
    case left
    case right
    case up
    case down
    case home
    case end
    case pageUp
    case pageDown

    /// The macOS virtual key code that produces this key.
    public var keyCode: UInt16 {
        switch self {
        case .returnKey: return 0x24
        case .tab: return 0x30
        case .backspace: return 0x33
        case .forwardDelete: return 0x75
        case .escape: return 0x35
        case .space: return 0x31
        case .left: return 0x7B
        case .right: return 0x7C
        case .down: return 0x7D
        case .up: return 0x7E
        case .home: return 0x73
        case .end: return 0x77
        case .pageUp: return 0x74
        case .pageDown: return 0x79
        }
    }

    /// The name Neovim uses inside angle brackets.
    public var neovimName: String {
        switch self {
        case .returnKey: return "CR"
        case .tab: return "Tab"
        case .backspace: return "BS"
        case .forwardDelete: return "Del"
        case .escape: return "Esc"
        case .space: return "Space"
        case .left: return "Left"
        case .right: return "Right"
        case .up: return "Up"
        case .down: return "Down"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "PageUp"
        case .pageDown: return "PageDown"
        }
    }

    /// The virtual key code of the numeric keypad's Enter, which Neovim treats as Return.
    public static let keypadEnterKeyCode: UInt16 = 0x4C

    public static func named(forKeyCode keyCode: UInt16) -> NamedKey? {
        if keyCode == keypadEnterKeyCode {
            return .returnKey
        }
        return allCases.first { $0.keyCode == keyCode }
    }
}

// MARK: - Convenience constructors for tests and call sites

extension KeyStroke {
    public static func character(_ character: String) -> KeyStroke {
        KeyStroke(keyCode: 0, characters: character, charactersIgnoringModifiers: character, modifiers: [])
    }

    public static func shifted(_ produced: String, unshifted: String) -> KeyStroke {
        KeyStroke(keyCode: 0, characters: produced, charactersIgnoringModifiers: unshifted, modifiers: .shift)
    }

    public static func control(_ key: String) -> KeyStroke {
        KeyStroke(keyCode: 0, characters: key, charactersIgnoringModifiers: key, modifiers: .control)
    }

    public static func option(_ key: String) -> KeyStroke {
        KeyStroke(keyCode: 0, characters: key, charactersIgnoringModifiers: key, modifiers: .option)
    }

    public static func command(_ key: String) -> KeyStroke {
        KeyStroke(keyCode: 0, characters: key, charactersIgnoringModifiers: key, modifiers: .command)
    }

    public static func named(_ key: NamedKey, modifiers: KeyModifiers = []) -> KeyStroke {
        KeyStroke(keyCode: key.keyCode, characters: nil, charactersIgnoringModifiers: nil, modifiers: modifiers)
    }
}

extension KeyStroke {
    /// The same press, reported as a different character.
    ///
    /// Used to hand the notation a Latin key recovered from the physical key code, so the
    /// rest of the rules — chord prefixes, Shift, the `<lt>` escape — keep working on the
    /// translated character rather than needing a second copy of themselves (REQ-014).
    func replacingCharacters(with character: String) -> KeyStroke {
        KeyStroke(
            keyCode: keyCode,
            characters: character,
            charactersIgnoringModifiers: character,
            modifiers: modifiers
        )
    }
}
