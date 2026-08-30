import AppKit
import CoreText

/// A glyph together with the font that can actually draw it.
struct ResolvedGlyph {
    let glyph: CGGlyph
    let font: CTFont
}

/// Caches character-to-glyph lookups, falling back to a font that has the character.
///
/// The monospaced system font contains no Hangul at all — measured, for both the upright
/// and the italic face. Without a fallback every Korean character resolves to glyph 0 and
/// is silently skipped, so a Korean comment renders as blank space. In a tool for reading
/// code, in a repository whose own comments are Korean, that is not an edge case.
///
/// A full redraw asks for thousands of glyphs, almost all repeats of a few dozen
/// characters, so both the hit and the fallback are cached.
@MainActor
final class GlyphCache {
    private struct Key: Hashable {
        let character: Character
        let style: GlyphStyle
    }

    private var resolved: [Key: ResolvedGlyph?] = [:]

    func resolve(_ character: Character, style: GlyphStyle, metrics: CellMetrics) -> ResolvedGlyph? {
        let key = Key(character: character, style: style)
        if let cached = resolved[key] {
            return cached
        }
        let value = lookUp(character, style: style, metrics: metrics)
        resolved[key] = value
        return value
    }

    private func lookUp(_ character: Character, style: GlyphStyle, metrics: CellMetrics) -> ResolvedGlyph? {
        let primary = metrics.font(for: style) as CTFont
        let utf16 = Array(String(character).utf16)

        if let glyph = glyph(for: utf16, in: primary) {
            return ResolvedGlyph(glyph: glyph, font: primary)
        }

        // The primary face cannot draw it. CoreText picks a font that can, preserving the
        // point size so the character still sits on the same baseline in the same cell.
        let text = String(character) as CFString
        let fallback = CTFontCreateForString(primary, text, CFRange(location: 0, length: CFStringGetLength(text)))
        guard let glyph = glyph(for: utf16, in: fallback) else {
            return nil
        }
        return ResolvedGlyph(glyph: glyph, font: fallback)
    }

    private func glyph(for utf16: [UInt16], in font: CTFont) -> CGGlyph? {
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        let converted = CTFontGetGlyphsForCharacters(font, utf16, &glyphs, utf16.count)
        guard converted, let first = glyphs.first, first != 0 else {
            return nil
        }
        return first
    }
}
