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
    public let italicFont: NSFont
    public let boldItalicFont: NSFont
    public let size: CGSize

    public init(pointSize: CGFloat = 13) {
        let regular = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .bold)
        self.font = regular
        self.boldFont = bold
        // The monospaced system font has no italic face of its own, so the trait is applied
        // through the font manager. If it cannot be, the upright face is used rather than a
        // synthesised slant, because a slanted glyph in a fixed grid changes its advance and
        // the column arithmetic stops holding.
        self.italicFont = NSFontManager.shared.convert(regular, toHaveTrait: .italicFontMask)
        self.boldItalicFont = NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)

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

    /// The face for a style.
    public func font(for style: GlyphStyle) -> NSFont {
        switch (style.isBold, style.isItalic) {
        case (true, true): return boldItalicFont
        case (true, false): return boldFont
        case (false, true): return italicFont
        case (false, false): return font
        }
    }

    /// Where an underline sits below the baseline, and how thick it is.
    ///
    /// Taken from the font rather than guessed, so it lands where the typeface intends and
    /// scales with the point size.
    public var underlineOffset: CGFloat { font.underlinePosition }
    public var underlineThickness: CGFloat { max(1, font.underlineThickness) }
}
