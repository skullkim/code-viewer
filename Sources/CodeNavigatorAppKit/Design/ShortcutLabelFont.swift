import SwiftUI

extension Font {
    /// The face for key and shortcut labels — ⌘P, ⇧⌘F, ↑↓, esc.
    ///
    /// Deliberately **not** monospaced. The monospaced system font has no glyphs for the
    /// modifier symbols (⌘ U+2318 · ⇧ U+21E7 · ⌥ U+2325 · ⌃ U+2303), so they come from a
    /// fallback face whose advances do not match the monospace cell. Two modifiers in a row
    /// then draw on top of each other: measured at 11pt, `⇧⌘F` rendered as a single
    /// unbroken mass of ink, while the same string in the system font resolves into three
    /// separated glyphs.
    ///
    /// Monospace still belongs to code, paths and line numbers (§4.2). It does not belong
    /// to key notation, and the two are easy to confuse because both look "technical".
    static func shortcutLabel(size: CGFloat = DesignTokens.Typography.shortcutSize) -> Font {
        .system(size: size)
    }
}
