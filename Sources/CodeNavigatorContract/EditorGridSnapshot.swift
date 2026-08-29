/// A complete, immutable picture of the editor at one `flush`.
///
/// Neovim's redraw protocol is incremental (line damage, scroll regions, highlight tables).
/// That machinery lives in the engine; the view renders whole snapshots and never has to
/// replay a diff. `revision` increases monotonically so a view can drop stale frames.
public struct EditorGridSnapshot: Sendable, Hashable {
    public let columns: Int
    public let rows: Int
    public let lines: [EditorGridLine]
    public let cursor: EditorCursorPosition
    public let mode: EditorMode
    public let defaultForeground: EditorColor
    public let defaultBackground: EditorColor
    public let revision: UInt64

    public init(
        columns: Int,
        rows: Int,
        lines: [EditorGridLine],
        cursor: EditorCursorPosition,
        mode: EditorMode,
        defaultForeground: EditorColor,
        defaultBackground: EditorColor,
        revision: UInt64
    ) {
        self.columns = columns
        self.rows = rows
        self.lines = lines
        self.cursor = cursor
        self.mode = mode
        self.defaultForeground = defaultForeground
        self.defaultBackground = defaultBackground
        self.revision = revision
    }
}
