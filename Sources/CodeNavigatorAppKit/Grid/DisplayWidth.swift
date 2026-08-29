/// How many grid cells a character occupies.
///
/// Neovim's grid gives every cell one column of width, but characters do not map to cells
/// one for one: East Asian characters take two, and combining marks take none. The engine
/// reports each run's total cell count, and this is what lets the renderer place the
/// characters *within* a run — otherwise everything after the first wide character on a
/// line, cursor included, lands in the wrong column.
///
/// The ranges are Unicode's East Asian Wide and Fullwidth classes, which is the same rule
/// Neovim itself applies.
public enum DisplayWidth {

    /// Unicode scalar ranges whose characters occupy two cells.
    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F,     // Hangul Jamo initial consonants
        0x2E80...0x303E,     // CJK radicals, Kangxi, CJK symbols
        0x3041...0x33FF,     // Hiragana, Katakana, CJK compatibility
        0x3400...0x4DBF,     // CJK unified ideographs extension A
        0x4E00...0x9FFF,     // CJK unified ideographs
        0xA000...0xA4CF,     // Yi syllables
        0xAC00...0xD7A3,     // Hangul syllables
        0xF900...0xFAFF,     // CJK compatibility ideographs
        0xFE10...0xFE19,     // Vertical forms
        0xFE30...0xFE6F,     // CJK compatibility forms
        0xFF00...0xFF60,     // Fullwidth forms
        0xFFE0...0xFFE6,     // Fullwidth signs
        0x1F300...0x1F64F,   // Emoji: symbols and pictographs, emoticons
        0x1F680...0x1F6FF,   // Emoji: transport and map
        0x1F900...0x1F9FF,   // Emoji: supplemental symbols
        0x20000...0x2FFFD,   // CJK extension B and beyond
        0x30000...0x3FFFD,
    ]

    /// Scalars that occupy no cell of their own.
    private static let zeroWidthRanges: [ClosedRange<UInt32>] = [
        0x0300...0x036F,     // Combining diacritical marks
        0x1AB0...0x1AFF,
        0x20D0...0x20FF,     // Combining marks for symbols
        0xFE00...0xFE0F,     // Variation selectors
        0xFE20...0xFE2F,     // Combining half marks
    ]

    public static func cells(of character: Character) -> Int {
        // A grapheme cluster's width is its base scalar's width: "e" plus a combining
        // acute is one character in one cell, not two.
        guard let base = character.unicodeScalars.first else {
            return 0
        }
        // Emoji are scattered across blocks rather than confined to one range — U+2705 ✅
        // sits among the dingbats. Unicode's own Emoji_Presentation property is the rule
        // that separates a two-cell emoji from a one-cell text symbol, so ✓ and ⚠ (which
        // this app uses in status messages) stay one cell as they should.
        if base.properties.isEmojiPresentation {
            return 2
        }
        return cells(ofScalar: base.value)
    }

    public static func cells(of text: String) -> Int {
        text.reduce(0) { $0 + cells(of: $1) }
    }

    private static func cells(ofScalar value: UInt32) -> Int {
        if zeroWidthRanges.contains(where: { $0.contains(value) }) {
            return 0
        }
        if wideRanges.contains(where: { $0.contains(value) }) {
            return 2
        }
        return 1
    }
}
