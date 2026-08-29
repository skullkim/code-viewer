/// Everything the status bar and the file tree need to know about the edit session.
///
/// `filePath` is the absolute path of the current buffer, or `nil` for an unnamed buffer.
/// Cursor coordinates are buffer positions (1-based line, 1-based column), not grid cells.
public struct EditorStatus: Sendable, Hashable {
    public let filePath: String?
    public let isDirty: Bool
    public let cursorLine: Int
    public let cursorColumn: Int
    public let mode: EditorMode
    public let inputMode: InputMode

    public init(
        filePath: String?,
        isDirty: Bool,
        cursorLine: Int,
        cursorColumn: Int,
        mode: EditorMode,
        inputMode: InputMode
    ) {
        self.filePath = filePath
        self.isDirty = isDirty
        self.cursorLine = cursorLine
        self.cursorColumn = cursorColumn
        self.mode = mode
        self.inputMode = inputMode
    }
}
