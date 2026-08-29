import AppKit
import CoreText

/// Caches character-to-glyph lookups per font weight.
///
/// A full redraw asks for thousands of glyphs, almost all of them repeats of the same few
/// dozen source characters. Looking each one up through CoreText every frame was the
/// difference between the measured 3.02 ms and something far worse.
@MainActor
final class GlyphCache {
    private var regular: [Character: CGGlyph] = [:]
    private var bold: [Character: CGGlyph] = [:]

    func glyph(for character: Character, bold isBold: Bool, metrics: CellMetrics) -> CGGlyph? {
        if let cached = isBold ? bold[character] : regular[character] {
            return cached == 0 ? nil : cached
        }

        let font = (isBold ? metrics.boldFont : metrics.font) as CTFont
        let utf16 = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        let converted = CTFontGetGlyphsForCharacters(font, utf16, &glyphs, utf16.count)
        let resolved = converted ? (glyphs.first ?? 0) : 0

        // Misses are cached too: a character the font cannot draw would otherwise be looked
        // up again on every single frame.
        if isBold {
            bold[character] = resolved
        } else {
            regular[character] = resolved
        }
        return resolved == 0 ? nil : resolved
    }
}
