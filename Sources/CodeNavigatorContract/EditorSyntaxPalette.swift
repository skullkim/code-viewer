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
    /// Annotations — `@Service`, `@Override`.
    ///
    /// Only reachable through tree-sitter: the regex syntax files have no notion of an
    /// annotation, so this slot stays unused on languages that fall back to them.
    public let annotation: EditorColor
    public let lineNumberForeground: EditorColor
    public let currentLineNumberForeground: EditorColor

    // MARK: 편집기 주변부
    //
    // 코드가 아니라서 오래 비어 있었고, 비어 있으면 nvim 기본값이 나온다. 그건 우리 배경을
    // 모르고 고른 색이라 대비가 맞을 이유가 없다 — 라이트 모드에서 밝은 화면 아래에 어두운
    // 회색 막대가 남아 편집기 절반이 다른 앱처럼 보였다.

    /// 편집기 하단 상태줄. 파일명과 위치를 담으므로 읽혀야 한다.
    public let statusLineForeground: EditorColor
    public let statusLineBackground: EditorColor
    /// 버퍼 끝의 `~`. 정보가 아니라 경계 표시다 — 코드로 오인될 만큼 밝으면 안 된다.
    public let endOfBufferForeground: EditorColor
    /// 줄바꿈·탭 같은 비출력 문자.
    public let nonTextForeground: EditorColor
    /// 사인 열(브레이크포인트가 놓이는 자리). 배경은 편집기와 **같아야** 한다 — 다르면
    /// 아무것도 없는 줄에도 세로 띠가 생기고, 사용자는 그것을 켜져 있는 표시로 읽는다.
    public let signColumnBackground: EditorColor

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
        annotation: EditorColor,
        lineNumberForeground: EditorColor,
        currentLineNumberForeground: EditorColor,
        statusLineForeground: EditorColor,
        statusLineBackground: EditorColor,
        endOfBufferForeground: EditorColor,
        nonTextForeground: EditorColor,
        signColumnBackground: EditorColor
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
        self.annotation = annotation
        self.lineNumberForeground = lineNumberForeground
        self.currentLineNumberForeground = currentLineNumberForeground
        self.statusLineForeground = statusLineForeground
        self.statusLineBackground = statusLineBackground
        self.endOfBufferForeground = endOfBufferForeground
        self.nonTextForeground = nonTextForeground
        self.signColumnBackground = signColumnBackground
    }
}
