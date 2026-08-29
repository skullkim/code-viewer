/// Which physical key was pressed, for the keys whose meaning is not their character.
///
/// `deleteBackward` is the key macOS labels "Delete" (⌫); `deleteForward` is fn+Delete.
/// Naming them by direction avoids the macOS/Vim clash over what "Delete" means.
public enum KeyCodeName: Sendable, Hashable, CaseIterable {
    case upArrow
    case downArrow
    case leftArrow
    case rightArrow
    case home
    case end
    case deleteBackward
    case deleteForward
    case enter
    case tab
    case escape

    /// Any key that produces text; the text itself is in `StandardKeyEvent.characters`.
    case character
}
