import CodeNavigatorContract

/// A stretch of cells painted with a background colour of their own.
public struct GridBackgroundRun: Sendable, Hashable {
    public let row: Int
    public let startColumn: Int
    public let cellWidth: Int
    public let color: RGBColor
}

/// Where the cursor block goes.
public struct GridCursor: Sendable, Hashable {
    public let row: Int
    public let column: Int
    /// How many cells the cursor covers — two on a double-width character, so it never
    /// sits on half a glyph.
    public let cellWidth: Int
}

/// A snapshot turned into drawing instructions.
public struct GridFrame: Sendable, Hashable {
    public let cells: [PositionedCell]
    public let backgroundRuns: [GridBackgroundRun]
    public let cursor: GridCursor
    public let defaultBackground: RGBColor
    public let columns: Int
    public let rows: Int
    /// Monotonic, so a view can drop a frame that arrived after a newer one.
    public let revision: UInt64
}

/// Converts an editor snapshot into positioned cells.
///
/// Columns come from `EditorTextRun.startColumn` and each character's own cell width — the
/// renderer never counts characters. A live Neovim reported "인덱스 abc" as seven
/// Characters occupying ten cells, and a renderer that assumed otherwise would misplace
/// every glyph after the first wide character, cursor included (ADR-0101).
public enum GridFrameBuilder {

    public static func build(from snapshot: EditorGridSnapshot) -> GridFrame {
        var cells: [PositionedCell] = []
        var backgroundRuns: [GridBackgroundRun] = []
        let defaultForeground = RGBColor(snapshot.defaultForeground)
        let defaultBackground = RGBColor(snapshot.defaultBackground)

        for (row, line) in snapshot.lines.enumerated() {
            for run in line.runs {
                let colours = resolvedColours(
                    style: run.style,
                    defaultForeground: defaultForeground,
                    defaultBackground: defaultBackground
                )

                if let background = colours.background {
                    backgroundRuns.append(GridBackgroundRun(
                        row: row,
                        startColumn: run.startColumn,
                        cellWidth: run.cellWidth,
                        color: background
                    ))
                }

                var column = run.startColumn
                for character in run.text {
                    defer { column += DisplayWidth.cells(of: character) }
                    cells.append(PositionedCell(
                        character: character,
                        row: row,
                        column: column,
                        foreground: colours.foreground,
                        // Every trait the engine resolved, not just weight. Neovim already
                        // parsed italic and underline out of `hl_attr_define`; dropping
                        // them here flattens a user's italic comments and their diagnostic
                        // underlines into plain text, which is the application overriding
                        // the user's own colour scheme (REQ-004 AC-3).
                        style: GlyphStyle(
                            isBold: run.style.isBold,
                            isItalic: run.style.isItalic,
                            isUnderlined: run.style.isUnderlined
                        )
                    ))
                }
            }
        }

        return GridFrame(
            cells: cells,
            backgroundRuns: backgroundRuns,
            cursor: cursor(in: snapshot),
            defaultBackground: defaultBackground,
            columns: snapshot.columns,
            rows: snapshot.rows,
            revision: snapshot.revision
        )
    }

    /// Resolves a run's colours, returning a background only when it differs from the
    /// grid's own — the whole view is filled with the default first, so repainting it per
    /// run would be wasted work.
    private static func resolvedColours(
        style: EditorTextStyle,
        defaultForeground: RGBColor,
        defaultBackground: RGBColor
    ) -> (foreground: RGBColor, background: RGBColor?) {
        let declaredForeground = style.foreground.map(RGBColor.init) ?? defaultForeground
        let declaredBackground = style.background.map(RGBColor.init) ?? defaultBackground

        // Neovim signals selections, search matches and the like with reverse video rather
        // than with explicit colours. Ignoring the flag renders selected text invisible
        // against its own highlight.
        let foreground = style.isReverseVideo ? declaredBackground : declaredForeground
        let background = style.isReverseVideo ? declaredForeground : declaredBackground

        return (foreground, background == defaultBackground ? nil : background)
    }

    /// The cursor's cell, widened to cover a double-width character underneath it.
    private static func cursor(in snapshot: EditorGridSnapshot) -> GridCursor {
        let position = snapshot.cursor
        let width = characterWidth(atRow: position.row, column: position.column, in: snapshot) ?? 1
        return GridCursor(row: position.row, column: position.column, cellWidth: width)
    }

    private static func characterWidth(atRow row: Int, column: Int, in snapshot: EditorGridSnapshot) -> Int? {
        guard snapshot.lines.indices.contains(row) else {
            return nil
        }
        for run in snapshot.lines[row].runs {
            guard column >= run.startColumn, column < run.startColumn + run.cellWidth else {
                continue
            }
            var cursorColumn = run.startColumn
            for character in run.text {
                let width = DisplayWidth.cells(of: character)
                if cursorColumn == column {
                    return max(1, width)
                }
                cursorColumn += width
            }
        }
        return nil
    }
}

extension RGBColor {
    /// Bridges the contract's colour type into the renderer's.
    init(_ color: EditorColor) {
        self.init(
            red: Double(color.red) / 255,
            green: Double(color.green) / 255,
            blue: Double(color.blue) / 255
        )
    }
}
