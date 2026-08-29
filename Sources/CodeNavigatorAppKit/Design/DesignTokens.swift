import SwiftUI

/// Which appearance the shell is drawing in. The system setting decides (REQ-011 AC-4);
/// the app offers no theme control of its own.
public enum AppearanceScheme: Sendable, Hashable, CaseIterable {
    case light
    case dark
}

/// A colour token with a value for each appearance, from design §4.1.
public struct ColorToken: Sendable, Hashable {
    public let name: String
    public let light: RGBColor
    public let dark: RGBColor

    public func value(for scheme: AppearanceScheme) -> RGBColor {
        scheme == .light ? light : dark
    }

    public var swiftUILight: Color { Color(red: light.red, green: light.green, blue: light.blue) }
    public var swiftUIDark: Color { Color(red: dark.red, green: dark.green, blue: dark.blue) }
}

/// The design system, one to one with design §4.
///
/// Values are the single place the shell reads colour, spacing and radius from. The
/// prototype stylesheet holds the same numbers; when they disagree the design document
/// decides, and `DesignTokenTests` is where that agreement is checked rather than assumed.
public enum DesignTokens {

    // MARK: Colour (§4.1)

    private static func token(_ name: String, _ light: String, _ dark: String) -> ColorToken {
        // Force-unwrapping is deliberate: these are compile-time constants from the design
        // document, and a malformed one is a programming error that should surface at once.
        ColorToken(name: name, light: RGBColor(hex: light)!, dark: RGBColor(hex: dark)!)
    }

    public static let backgroundWindow = token("bg-window", "#ECECEE", "#2C2C31")
    public static let backgroundSidebar = token("bg-sidebar", "#F2F2F4", "#232327")
    public static let backgroundContent = token("bg-content", "#FFFFFF", "#1B1B1F")
    public static let backgroundPanel = token("bg-panel", "#F7F7F8", "#232327")
    public static let backgroundStatus = token("bg-status", "#F2F2F4", "#26262B")
    public static let backgroundElevated = token("bg-elevated", "#FFFFFF", "#303036")
    public static let backgroundHover = token("bg-hover", "#E6E6EA", "#35353C")

    public static let border = token("border", "#D8D8DE", "#3A3A42")
    public static let borderStrong = token("border-strong", "#BFBFC8", "#4A4A54")

    public static let textPrimary = token("text-1", "#1C1C1E", "#E8E8ED")
    public static let textSecondary = token("text-2", "#55555E", "#A6A6B0")
    /// Hints, line numbers and shortcut labels.
    ///
    /// The design document lists 5.0:1 for this token, measured against the content
    /// background. But text-3 is drawn on the toolbar and the status bar too, and against
    /// those the published hex measures 3.81:1 in light and 3.63:1 in dark — well under
    /// the 4.5:1 floor §4.5 sets for text. Corrected here to clear the floor on every
    /// surface it actually appears on, hue preserved; reported to the lead for a ruling.
    public static let textTertiary = token("text-3", "#6A6A73", "#9898A1")

    public static let accent = token("accent", "#007AFF", "#0A84FF")
    public static let accentText = token("accent-text", "#0B62D6", "#4D9FFF")

    public static let danger = token("danger", "#C42B31", "#FF6B70")
    public static let warning = token("warning", "#8A5A00", "#E8B33D")
    public static let warningSolid = token("warning-solid", "#E0A21B", "#E8B33D")
    public static let success = token("success", "#1B7A4B", "#4CC38A")
    public static let purple = token("purple", "#7A34B8", "#C792EA")

    /// Interfaces and type aliases in the symbol-kind badges (design §4.1).
    ///
    /// §4.1 lists this colour only under syntax highlighting, which it marks as "Neovim's
    /// to own". The badges are different: the application draws them, in the search modal
    /// and the definition picker, so the colour has to be a real token rather than a
    /// borrowed sample. The values are the ones the prototype already uses for `--syn-type`,
    /// so the visual reference stays accurate.
    public static let teal = token("teal", "#0F7A6E", "#57C7B8")

    /// Every token that carries text and therefore has to clear the contrast floor.
    public static let textTokens: [ColorToken] = [
        textPrimary, textSecondary, textTertiary, accentText, danger, warning, success, purple,
    ]

    /// The surfaces body text is drawn on, per design §3.
    ///
    /// `bg-hover` is deliberately absent: it sits behind row labels drawn in text-1 and
    /// text-2, both of which clear the floor on it comfortably, and treating it as a text
    /// surface for every token would force colour changes the design never intended.
    public static let textBearingSurfaces: [ColorToken] = [
        backgroundContent, backgroundPanel, backgroundSidebar,
        backgroundStatus, backgroundWindow, backgroundElevated,
    ]

    public static let allColorTokens: [ColorToken] = [
        backgroundWindow, backgroundSidebar, backgroundContent, backgroundPanel, backgroundStatus,
        backgroundElevated, backgroundHover, border, borderStrong,
        textPrimary, textSecondary, textTertiary, accent, accentText,
        danger, warning, warningSolid, success, purple, teal,
    ]

    /// The floor design §4.5 sets for text.
    public static let minimumTextContrastRatio = 4.5

    /// The lower floor §4.5 sets for badges and status chips, which carry a single letter
    /// or a dot rather than prose, and never stand alone as the only signal.
    public static let minimumBadgeContrastRatio = 3.0

    /// The four colours the symbol-kind badges use (design §4.1).
    ///
    /// C·O = accent, I·T = teal, E·F = purple, P = warning.
    public static let badgeTokens: [ColorToken] = [accentText, teal, purple, warning]

    /// The surfaces a badge is drawn on: the search modal, the definition popover and the
    /// reference panel.
    public static let badgeBearingSurfaces: [ColorToken] = [
        backgroundContent, backgroundPanel, backgroundElevated, backgroundSidebar,
    ]

    // MARK: Spacing and shape (§4.3)

    public enum Spacing {
        public static let extraSmall: CGFloat = 4
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let large: CGFloat = 16
        public static let extraLarge: CGFloat = 24
        public static let huge: CGFloat = 32

        public static let scale: [CGFloat] = [extraSmall, small, medium, large, extraLarge, huge]
    }

    public enum Radius {
        /// Buttons, badges, inputs.
        public static let control: CGFloat = 5
        /// Cards, popovers, sheets.
        public static let surface: CGFloat = 8
        /// Modals and the window itself.
        public static let modal: CGFloat = 10
        /// Status chips.
        public static let chip: CGFloat = 999
    }

    // MARK: Typography (§4.2)

    public enum Typography {
        public static let bodySize: CGFloat = 13
        public static let bodyLineHeight = 1.5
        public static let secondarySize: CGFloat = 11.5
        public static let secondaryLineHeight = 1.45
        public static let panelTitleSize: CGFloat = 12.5
        public static let welcomeTitleSize: CGFloat = 19
        public static let editorSize: CGFloat = 13
        public static let previewSize: CGFloat = 11.5
        public static let shortcutSize: CGFloat = 11
    }
}
