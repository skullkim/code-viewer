/// A mouse event to forward to the editor (REQ-010 AC-2: click to move the cursor, drag to select).
///
/// Key notation cannot carry a position, so mouse input needs its own entry point. Coordinates
/// are **grid cells**, the same space as `EditorCursorPosition` and `EditorTextRun.startColumn` —
/// not buffer lines and not pixels. The view converts from its own geometry, since it is the side
/// that knows the cell size.
public struct EditorMouseEvent: Sendable, Hashable {
    public enum Button: String, Sendable, Hashable {
        case left, right, middle, wheel
    }

    public enum Action: String, Sendable, Hashable {
        case press, drag, release, wheelUp, wheelDown, wheelLeft, wheelRight
    }

    public let button: Button
    public let action: Action
    /// Grid row, 0-based.
    public let row: Int
    /// Grid column, 0-based.
    public let column: Int
    /// Held modifiers in Neovim's notation: `""`, `"S"`, `"C"`, `"S-C"`, …
    public let modifiers: String

    public init(
        button: Button,
        action: Action,
        row: Int,
        column: Int,
        modifiers: String = ""
    ) {
        self.button = button
        self.action = action
        self.row = row
        self.column = column
        self.modifiers = modifiers
    }
}
