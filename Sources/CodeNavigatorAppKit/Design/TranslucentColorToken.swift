import SwiftUI
import AppKit

/// A colour token design §4.1 states with an alpha channel.
///
/// `ColorToken` deliberately has no alpha — every opaque token in §4.1 is a hex triple, and
/// contrast measurement only means something for opaque colours. The two translucent
/// tokens are kept in their own type so the contrast tests keep walking exactly the set
/// they are meant to, rather than one padded with colours whose ratio depends on whatever
/// happens to be underneath.
public struct TranslucentColorToken: Sendable, Hashable {
    public let name: String
    public let light: RGBColor
    public let lightOpacity: Double
    public let dark: RGBColor
    public let darkOpacity: Double

    public func value(for scheme: AppearanceScheme) -> (color: RGBColor, opacity: Double) {
        scheme == .light ? (light, lightOpacity) : (dark, darkOpacity)
    }

    /// The opaque colour this token becomes when drawn over `background`.
    ///
    /// Needed because Neovim highlight groups have no alpha: `nvim_set_hl` takes one packed
    /// RGB, so a translucent token cannot be handed over as-is and has to be resolved against
    /// the surface it sits on first (REQ-016 AC-2, ADR-0112).
    ///
    /// The blend is done on the sRGB components directly, which is **not** the physically
    /// correct thing to do — compositing belongs in linear light. It is done this way because
    /// CSS `rgba()` composites in sRGB, the prototype states these tokens as `rgba()`, and the
    /// prototype is the reference the design-fidelity comparison is made against. Being
    /// physically right here would put the application a visible step away from the picture it
    /// is checked against, so the reference wins and the reason is written down.
    public func flattened(over background: RGBColor, for scheme: AppearanceScheme) -> RGBColor {
        let (color, opacity) = value(for: scheme)
        let alpha = min(max(opacity, 0), 1)
        func blend(_ source: Double, _ destination: Double) -> Double {
            source * alpha + destination * (1 - alpha)
        }
        return RGBColor(
            red: blend(color.red, background.red),
            green: blend(color.green, background.green),
            blue: blend(color.blue, background.blue)
        )
    }
}

extension DesignTokens {

    /// `accent-dim` — selected rows and banner backgrounds (§4.1).
    ///
    /// Light is `accent` at 12%; dark is `accent-text` at 16%. The dark base is the lighter
    /// blue on purpose: §4.1 writes `rgba(77,159,255,.16)`, which is `accent-text`, not
    /// `accent`. Reaching for `accent` in both appearances would look reasonable and be
    /// wrong.
    public static let accentDim = TranslucentColorToken(
        name: "accent-dim",
        light: accent.light,
        lightOpacity: 0.12,
        dark: accentText.dark,
        darkOpacity: 0.16
    )

    /// `match` — the search-hit highlight behind text in W-3, W-5 and W-6 (§4.1).
    ///
    /// `warning-solid` at 30% / 26%. It sits *behind* body text, so the text keeps its own
    /// token and the contrast floor still applies to that pairing.
    public static let match = TranslucentColorToken(
        name: "match",
        light: warningSolid.light,
        lightOpacity: 0.30,
        dark: warningSolid.dark,
        darkOpacity: 0.26
    )
}

extension ColorToken {

    /// The token as a colour that follows the system appearance by itself.
    ///
    /// REQ-011 AC-4 asks the shell to follow the system setting. A view could read
    /// `@Environment(\.colorScheme)` and pick, but then every view has to remember to —
    /// and the one that forgets is a light-mode colour in a dark window. A dynamic
    /// `NSColor` resolves at draw time, so the token is correct wherever it is used.
    public var dynamicColor: Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            NSColor(rgb: self.value(for: appearance.appearanceScheme))
        })
    }
}

extension TranslucentColorToken {

    /// The token as an appearance-following colour, alpha included.
    public var dynamicColor: Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            let resolved = self.value(for: appearance.appearanceScheme)
            return NSColor(rgb: resolved.color).withAlphaComponent(resolved.opacity)
        })
    }
}

extension NSAppearance {

    /// Which of the two appearances the design system defines this one is.
    ///
    /// Matched against the two named appearances rather than compared by name, so the
    /// high-contrast and vibrant variants resolve to the right side instead of falling
    /// through to a default.
    var appearanceScheme: AppearanceScheme {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

extension NSColor {
    fileprivate convenience init(rgb: RGBColor) {
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}
