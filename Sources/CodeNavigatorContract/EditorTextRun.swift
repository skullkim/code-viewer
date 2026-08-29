/// A stretch of editor text sharing one style — the unit the view draws.
///
/// `startColumn` and `cellWidth` are carried explicitly because **grid columns cannot be derived
/// from `text`**. Neovim's grid is a matrix of fixed-width cells, and the mapping from characters
/// to cells is not one-to-one in three separate ways:
///
/// - A double-width character (CJK, and much of the punctuation around it) occupies two cells.
///   Neovim reports the second cell as an empty string, which vanishes when a run's cells are
///   joined into one string — so `"한"` is one Character but two columns.
/// - Cells arrive run-length encoded, so one wire entry can cover many columns.
/// - A combining sequence is several scalars in one cell.
///
/// The engine knows the true column while it is filling the grid, so it reports it. A view that
/// counted characters instead would misplace every glyph after the first wide character on a
/// line — and the cursor with them.
public struct EditorTextRun: Sendable, Hashable {
    public let text: String
    public let style: EditorTextStyle
    /// The grid column this run begins at, 0-based, in the same coordinate space as
    /// `EditorCursorPosition`.
    public let startColumn: Int
    /// How many grid cells this run occupies. Not the character count.
    public let cellWidth: Int

    public init(text: String, style: EditorTextStyle, startColumn: Int, cellWidth: Int) {
        self.text = text
        self.style = style
        self.startColumn = startColumn
        self.cellWidth = cellWidth
    }
}
