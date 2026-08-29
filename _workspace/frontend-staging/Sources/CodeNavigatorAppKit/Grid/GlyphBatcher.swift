/// One character to draw at a grid position, with its resolved appearance.
public struct PositionedCell: Sendable, Hashable {
    public let character: Character
    public let row: Int
    public let column: Int
    public let foreground: RGBColor
    public let isBold: Bool

    public init(character: Character, row: Int, column: Int, foreground: RGBColor, isBold: Bool) {
        self.character = character
        self.row = row
        self.column = column
        self.foreground = foreground
        self.isBold = isBold
    }
}

/// Cells that can be drawn in one call because they share a font and a colour.
public struct GlyphBatch: Sendable, Hashable {
    public let foreground: RGBColor
    public let isBold: Bool
    public let cells: [PositionedCell]

    public init(foreground: RGBColor, isBold: Bool, cells: [PositionedCell]) {
        self.foreground = foreground
        self.isBold = isBold
        self.cells = cells
    }
}

/// Groups grid cells into the fewest draw calls.
///
/// Per-cell positioning is what makes the grid exact (ADR-0101), but issuing one draw call
/// per cell would mean ten thousand of them on a full screen. Cells sharing a font and a
/// colour are collected so each group is drawn once, with explicit positions — the
/// approach that measured 3.02 ms for a 50x200 grid against 4.36 ms for whole-line
/// rendering.
public enum GlyphBatcher {

    /// Characters with nothing to draw. Blanks are most of an indented source file, and
    /// carrying them through would inflate every batch for no pixels.
    private static func isBlank(_ character: Character) -> Bool {
        character == " " || character == "\t" || character == "\0"
    }

    private struct BatchKey: Hashable {
        let foreground: RGBColor
        let isBold: Bool
    }

    public static func batches(for cells: [PositionedCell]) -> [GlyphBatch] {
        // First-appearance order rather than dictionary order: a draw order that changes
        // between runs makes a rendering difference impossible to reproduce.
        var order: [BatchKey] = []
        var grouped: [BatchKey: [PositionedCell]] = [:]

        for cell in cells where !isBlank(cell.character) {
            let key = BatchKey(foreground: cell.foreground, isBold: cell.isBold)
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(cell)
        }

        return order.map { key in
            GlyphBatch(foreground: key.foreground, isBold: key.isBold, cells: grouped[key] ?? [])
        }
    }
}
