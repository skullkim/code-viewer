/// One row of the menu bar (design §3 W-9).
///
/// A description rather than an `NSMenuItem` so the menu can be checked without a running
/// application: which commands exist, what they are bound to and when they are live are
/// acceptance criteria (REQ-010 AC-5, REQ-011 AC-2), not presentation.
public struct MenuItemDescriptor: Sendable, Hashable {
    public let title: String
    /// The command this row runs, or nil for a separator or a plain container.
    public let command: MenuCommand?
    /// The character of the key equivalent, lowercase, or "" for none.
    public let keyEquivalent: String
    public let modifiers: KeyModifiers
    public let isSeparator: Bool
    public let submenu: [MenuItemDescriptor]

    public init(
        title: String,
        command: MenuCommand? = nil,
        keyEquivalent: String = "",
        modifiers: KeyModifiers = [],
        isSeparator: Bool = false,
        submenu: [MenuItemDescriptor] = []
    ) {
        self.title = title
        self.command = command
        self.keyEquivalent = keyEquivalent
        self.modifiers = modifiers
        self.isSeparator = isSeparator
        self.submenu = submenu
    }

    public static let separator = MenuItemDescriptor(title: "", isSeparator: true)

    public var hasKeyEquivalent: Bool {
        !keyEquivalent.isEmpty
    }
}
