/// One key press, as standard mode sees it (REQ-010 AC-2).
///
/// This is deliberately not an AppKit type: the translation rules are pure logic and are tested
/// without a running app. The app shell maps `NSEvent` onto this at the edge.
public struct StandardKeyEvent: Sendable, Hashable {
    /// The text the key produced, already shifted ("A" rather than "a" + shift). Empty for
    /// keys that produce no text.
    public let characters: String

    public let keyCode: KeyCodeName
    public let modifiers: KeyModifiers

    public init(characters: String = "", keyCode: KeyCodeName, modifiers: KeyModifiers = []) {
        self.characters = characters
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}
