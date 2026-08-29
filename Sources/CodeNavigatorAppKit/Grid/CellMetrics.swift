import AppKit
import CoreText

/// The size of one grid cell, taken from the font rather than from measured text.
///
/// Measuring a laid-out string would let the cell size drift as content changes, which is
/// the opposite of what a grid is. The advance of the space glyph is the cell width by
/// definition in a monospaced face.
@MainActor
public struct CellMetrics {
    public let font: NSFont
    public let boldFont: NSFont
    public let size: CGSize

    public init(pointSize: CGFloat = 13) {
        let regular = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        self.font = regular
        self.boldFont = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .bold)

        let ctFont = regular as CTFont
        var glyph = CTFontGetGlyphWithName(ctFont, "space" as CFString)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)

        let width = advance.width > 0 ? advance.width : regular.maximumAdvancement.width
        let height = ceil(regular.ascender - regular.descender + regular.leading)
        self.size = CGSize(width: width, height: height)
    }

    /// Distance from a row's bottom edge up to its text baseline.
    public var baselineOffset: CGFloat { -font.descender }
}
