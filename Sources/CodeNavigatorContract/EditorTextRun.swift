/// A stretch of editor text sharing one style — the unit the view draws.
public struct EditorTextRun: Sendable, Hashable {
    public let text: String
    public let style: EditorTextStyle

    public init(text: String, style: EditorTextStyle) {
        self.text = text
        self.style = style
    }
}
