/// The colours the editor paints code with (REQ-016 AC-3, AC-6).
///
/// The application owns these, not the engine. Two reasons, and the second is the one that
/// matters: the application is what knows the current theme, and routing the colours through
/// here makes "the app's theme wins over the user's colourscheme" a **direction of data flow**
/// instead of a rule somebody has to keep remembering.
///
/// Not applying a palette is a supported state — the editor keeps its own colours and text still
/// renders, because highlighting is derived and its absence must not stop editing (INV-8).
public struct EditorSyntaxPalette: Sendable, Hashable, Codable {
    public let keyword: EditorColor
    public let type: EditorColor
    public let function: EditorColor
    public let string: EditorColor
    public let number: EditorColor
    public let comment: EditorColor
    /// Whether keywords are drawn bold as well as coloured.
    ///
    /// Measured: Neovim's stock keyword colour is the same value as its default foreground, so
    /// keywords read as plain text. Colour alone fixes that on this screen and stops fixing it on
    /// a low-saturation one, or for a reader with a colour vision deficiency — weight does not
    /// depend on either.
    public let keywordIsBold: Bool
    /// Plain text, and the editor's own background.
    ///
    /// Carried because "no colour" and "the plain colour" are different states. A group left
    /// undefined is one the user's colourscheme fills in, which puts a colour on screen that the
    /// application did not choose (AC-6).
    public let normalForeground: EditorColor
    public let normalBackground: EditorColor
    /// Behind every other occurrence of the symbol under the cursor, within the file (AC-2).
    public let sameSymbolBackground: EditorColor
    /// Behind a visual selection, including one made with the mouse (REQ-017 AC-3).
    public let selectionBackground: EditorColor
    /// The line-number gutter, and the number on the line the cursor is on.
    ///
    /// Carried for the same reason as `normalForeground`: left undefined, Neovim's stock `LineNr`
    /// (`#4F5258`) stays, which sits at 2.19:1 on the editor background — under half the 4.5:1
    /// floor. Painting `Normal` made that *worse* (2.34 → 2.19), so owning the background without
    /// owning the gutter degrades a surface the application did not mean to touch.
    public let lineNumberForeground: EditorColor
    public let currentLineNumberForeground: EditorColor

    public init(
        keyword: EditorColor,
        type: EditorColor,
        function: EditorColor,
        string: EditorColor,
        number: EditorColor,
        comment: EditorColor,
        keywordIsBold: Bool,
        normalForeground: EditorColor,
        normalBackground: EditorColor,
        sameSymbolBackground: EditorColor,
        selectionBackground: EditorColor,
        lineNumberForeground: EditorColor,
        currentLineNumberForeground: EditorColor
    ) {
        self.keyword = keyword
        self.type = type
        self.function = function
        self.string = string
        self.number = number
        self.comment = comment
        self.keywordIsBold = keywordIsBold
        self.normalForeground = normalForeground
        self.normalBackground = normalBackground
        self.sameSymbolBackground = sameSymbolBackground
        self.selectionBackground = selectionBackground
        self.lineNumberForeground = lineNumberForeground
        self.currentLineNumberForeground = currentLineNumberForeground
    }
}
