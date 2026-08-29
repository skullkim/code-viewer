/// The cursor's cell position in the editor grid, both 0-based.
public struct EditorCursorPosition: Sendable, Hashable, Codable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}
