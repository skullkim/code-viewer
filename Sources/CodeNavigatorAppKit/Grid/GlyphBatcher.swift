/// The typographic traits a cell carries, grouped so they travel together.
///
/// Three separate flags threaded through every layer is how the first version lost italic
/// and underline: `isBold` was copied at each step and the other two were simply not, and
/// nothing in the types noticed. A single value cannot be half-copied.
public struct GlyphStyle: Sendable, Hashable {
    public let isBold: Bool
    public let isItalic: Bool
    public let isUnderlined: Bool

    public static let plain = GlyphStyle()

    public init(isBold: Bool = false, isItalic: Bool = false, isUnderlined: Bool = false) {
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
    }
}

/// One character to draw at a grid position, with its resolved appearance.
public struct PositionedCell: Sendable, Hashable {
    public let character: Character
    public let row: Int
    public let column: Int
    public let foreground: RGBColor
    public let style: GlyphStyle

    public var isBold: Bool { style.isBold }

    public init(character: Character, row: Int, column: Int, foreground: RGBColor, style: GlyphStyle) {
        self.character = character
        self.row = row
        self.column = column
        self.foreground = foreground
        self.style = style
    }
}

/// Cells that can be drawn in one call because they share a font and a colour.
public struct GlyphBatch: Sendable, Hashable {
    public let foreground: RGBColor
    public let style: GlyphStyle
    public let cells: [PositionedCell]

    public var isBold: Bool { style.isBold }

    public init(foreground: RGBColor, style: GlyphStyle, cells: [PositionedCell]) {
        self.foreground = foreground
        self.style = style
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
        // The whole style, not just weight: an italic run and an upright one need
        // different fonts, so batching them together would draw one of them wrong.
        let style: GlyphStyle
    }

    public static func batches(for cells: [PositionedCell]) -> [GlyphBatch] {
        // First-appearance order rather than dictionary order: a draw order that changes
        // between runs makes a rendering difference impossible to reproduce.
        var order: [BatchKey] = []
        var grouped: [BatchKey: [PositionedCell]] = [:]

        for cell in cells where !isBlank(cell.character) {
            let key = BatchKey(foreground: cell.foreground, style: cell.style)
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(cell)
        }

        return order.map { key in
            GlyphBatch(foreground: key.foreground, style: key.style, cells: grouped[key] ?? [])
        }
    }
}
