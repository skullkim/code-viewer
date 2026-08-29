import CodeNavigatorContract

/// Replays Neovim's `redraw` events into a full picture of the screen.
///
/// Neovim's `ext_linegrid` protocol is incremental: it sends line damage, scroll regions, and a
/// highlight table that later events refer to by number. Keeping that machinery here means the
/// view can render whole immutable snapshots and never has to replay a diff (ADR-0001).
///
/// Every event is tolerated. Malformed arguments and unknown event names are ignored rather than
/// trapped — a future Neovim release adding an event must not crash the editor (REQ-NF-004).
struct NeovimGridState {
    /// Neovim's global grid. Multigrid is not enabled, so everything else is ignored.
    private static let globalGridIdentifier = 1

    private var columns = 0
    private var rows = 0
    private var cells: [[NeovimGridCell]] = []
    private var cursor = EditorCursorPosition(row: 0, column: 0)
    private var mode = EditorMode.normal
    private var stylesByHighlightIdentifier: [Int: EditorTextStyle] = [:]
    private var defaultForeground = EditorColor(red: 0xD0, green: 0xD0, blue: 0xD0)
    private var defaultBackground = EditorColor(red: 0x1E, green: 0x1E, blue: 0x1E)
    private var revision: UInt64 = 0

    init() {}

    // MARK: - Applying events

    mutating func apply(eventName: String, arguments: [MessagePackValue]) {
        switch eventName {
        case "grid_resize": applyResize(arguments)
        case "grid_clear": applyClear(arguments)
        case "grid_line": applyLine(arguments)
        case "grid_scroll": applyScroll(arguments)
        case "grid_cursor_goto": applyCursorGoto(arguments)
        case "mode_change": applyModeChange(arguments)
        case "hl_attr_define": applyHighlightDefinition(arguments)
        case "default_colors_set": applyDefaultColors(arguments)
        default: break
        }
    }

    private mutating func applyResize(_ arguments: [MessagePackValue]) {
        guard arguments.count >= 3,
              isGlobalGrid(arguments[0]),
              let newColumns = arguments[1].integerValue,
              let newRows = arguments[2].integerValue,
              newColumns > 0, newRows > 0
        else {
            return
        }

        var resized = Array(
            repeating: Array(repeating: NeovimGridCell.blank, count: newColumns),
            count: newRows
        )
        // Keep whatever still fits, so a resize does not blank the screen for a frame.
        for row in 0..<min(rows, newRows) {
            for column in 0..<min(columns, newColumns) {
                resized[row][column] = cells[row][column]
            }
        }

        columns = newColumns
        rows = newRows
        cells = resized
        clampCursor()
    }

    private mutating func applyClear(_ arguments: [MessagePackValue]) {
        guard arguments.count >= 1, isGlobalGrid(arguments[0]), rows > 0 else { return }
        cells = Array(
            repeating: Array(repeating: NeovimGridCell.blank, count: columns),
            count: rows
        )
    }

    /// `grid_line` carries a run-length encoded slice of one row. A cell may omit its highlight
    /// identifier, which means "same as the previous cell", and may carry a repeat count.
    private mutating func applyLine(_ arguments: [MessagePackValue]) {
        guard arguments.count >= 4,
              isGlobalGrid(arguments[0]),
              let row = arguments[1].integerValue,
              let startColumn = arguments[2].integerValue,
              let cellValues = arguments[3].arrayValue,
              row >= 0, row < rows
        else {
            return
        }

        var column = startColumn
        var highlightIdentifier = 0

        for cellValue in cellValues {
            guard let parts = cellValue.arrayValue, let text = parts.first?.stringValue else {
                continue
            }
            if parts.count >= 2, let identifier = parts[1].integerValue {
                highlightIdentifier = identifier
            }
            let repeatCount = parts.count >= 3 ? (parts[2].integerValue ?? 1) : 1

            for _ in 0..<max(repeatCount, 0) {
                guard column >= 0, column < columns else { break }
                cells[row][column] = NeovimGridCell(text: text, highlightIdentifier: highlightIdentifier)
                column += 1
            }
        }
    }

    /// Moves a rectangular region. Positive `rowCount` scrolls content up (the top line leaves),
    /// negative scrolls it down. Neovim redraws the vacated lines separately.
    private mutating func applyScroll(_ arguments: [MessagePackValue]) {
        guard arguments.count >= 6,
              isGlobalGrid(arguments[0]),
              let top = arguments[1].integerValue,
              let bottom = arguments[2].integerValue,
              let left = arguments[3].integerValue,
              let right = arguments[4].integerValue,
              let rowCount = arguments[5].integerValue,
              rowCount != 0
        else {
            return
        }

        let firstRow = max(top, 0)
        let lastRow = min(bottom, rows)
        let firstColumn = max(left, 0)
        let lastColumn = min(right, columns)
        guard firstRow < lastRow, firstColumn < lastColumn else { return }

        let sourceRows: [Int] = rowCount > 0
            ? Array(firstRow..<lastRow)
            : Array((firstRow..<lastRow).reversed())

        for destinationRow in sourceRows {
            let sourceRow = destinationRow + rowCount
            guard sourceRow >= firstRow, sourceRow < lastRow else { continue }
            for column in firstColumn..<lastColumn {
                cells[destinationRow][column] = cells[sourceRow][column]
            }
        }
    }

    private mutating func applyCursorGoto(_ arguments: [MessagePackValue]) {
        guard arguments.count >= 3,
              isGlobalGrid(arguments[0]),
              let row = arguments[1].integerValue,
              let column = arguments[2].integerValue
        else {
            return
        }
        cursor = EditorCursorPosition(row: row, column: column)
        clampCursor()
    }

    private mutating func applyModeChange(_ arguments: [MessagePackValue]) {
        guard let name = arguments.first?.stringValue else { return }
        mode = EditorMode(neovimName: name)
    }

    private mutating func applyHighlightDefinition(_ arguments: [MessagePackValue]) {
        guard arguments.count >= 2,
              let identifier = arguments[0].integerValue,
              let attributes = arguments[1].mapValue
        else {
            return
        }
        stylesByHighlightIdentifier[identifier] = Self.style(fromAttributes: attributes)
    }

    private mutating func applyDefaultColors(_ arguments: [MessagePackValue]) {
        guard arguments.count >= 2,
              let foreground = arguments[0].integerValue,
              let background = arguments[1].integerValue
        else {
            return
        }
        defaultForeground = EditorColor(packedRGB: foreground)
        defaultBackground = EditorColor(packedRGB: background)
    }

    // MARK: - Snapshot

    /// Builds the immutable frame the view renders, merging neighbouring cells that share a
    /// style into runs. An 80×24 grid is 1,920 cells but usually only a few dozen runs, which is
    /// the difference between a view that redraws cheaply and one that does not.
    mutating func makeSnapshot() -> EditorGridSnapshot {
        revision += 1

        let lines = cells.map { row -> EditorGridLine in
            var runs: [EditorTextRun] = []
            var currentText = ""
            var currentIdentifier: Int?
            var runStartColumn = 0

            // The cell index *is* the grid column, so the run's position and width come straight
            // from the loop. This is the value a view cannot reconstruct from the text alone.
            for (column, cell) in row.enumerated() {
                if cell.highlightIdentifier == currentIdentifier {
                    currentText += cell.text
                    continue
                }
                if let identifier = currentIdentifier {
                    runs.append(
                        EditorTextRun(
                            text: currentText,
                            style: style(for: identifier),
                            startColumn: runStartColumn,
                            cellWidth: column - runStartColumn
                        )
                    )
                }
                currentText = cell.text
                currentIdentifier = cell.highlightIdentifier
                runStartColumn = column
            }
            if let identifier = currentIdentifier {
                runs.append(
                    EditorTextRun(
                        text: currentText,
                        style: style(for: identifier),
                        startColumn: runStartColumn,
                        cellWidth: row.count - runStartColumn
                    )
                )
            }
            return EditorGridLine(runs: runs)
        }

        return EditorGridSnapshot(
            columns: columns,
            rows: rows,
            lines: lines,
            cursor: cursor,
            mode: mode,
            defaultForeground: defaultForeground,
            defaultBackground: defaultBackground,
            revision: revision
        )
    }

    // MARK: - Helpers

    private func isGlobalGrid(_ value: MessagePackValue) -> Bool {
        value.integerValue == Self.globalGridIdentifier
    }

    private func style(for highlightIdentifier: Int) -> EditorTextStyle {
        stylesByHighlightIdentifier[highlightIdentifier] ?? .plain
    }

    private mutating func clampCursor() {
        guard rows > 0, columns > 0 else {
            cursor = EditorCursorPosition(row: 0, column: 0)
            return
        }
        cursor = EditorCursorPosition(
            row: min(max(cursor.row, 0), rows - 1),
            column: min(max(cursor.column, 0), columns - 1)
        )
    }

    private static func style(fromAttributes attributes: [MessagePackKeyValuePair]) -> EditorTextStyle {
        var foreground: EditorColor?
        var background: EditorColor?
        var isBold = false
        var isItalic = false
        var isUnderlined = false
        var isReverseVideo = false

        for pair in attributes {
            switch pair.key.stringValue {
            case "foreground":
                foreground = pair.value.integerValue.map { EditorColor(packedRGB: $0) }
            case "background":
                background = pair.value.integerValue.map { EditorColor(packedRGB: $0) }
            case "bold":
                isBold = pair.value.booleanValue ?? false
            case "italic":
                isItalic = pair.value.booleanValue ?? false
            case "underline":
                isUnderlined = pair.value.booleanValue ?? false
            case "reverse":
                isReverseVideo = pair.value.booleanValue ?? false
            default:
                break
            }
        }

        return EditorTextStyle(
            foreground: foreground,
            background: background,
            isBold: isBold,
            isItalic: isItalic,
            isUnderlined: isUnderlined,
            isReverseVideo: isReverseVideo
        )
    }
}
