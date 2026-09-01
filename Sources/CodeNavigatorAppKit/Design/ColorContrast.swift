import Foundation

/// WCAG 2.1 relative luminance and contrast ratio.
///
/// Design §4.5 requires 4.5:1 for text and states a measured ratio for every colour token.
/// Computing the ratios here turns those statements into something a test can check, so a
/// token edited by hand cannot quietly drop below the threshold.
public enum ColorContrast {

    /// Relative luminance of an sRGB colour, per WCAG 2.1.
    public static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Contrast ratio between two colours, from 1:1 to 21:1.
    public static func ratio(_ first: RGBColor, _ second: RGBColor) -> Double {
        let firstLuminance = relativeLuminance(red: first.red, green: first.green, blue: first.blue)
        let secondLuminance = relativeLuminance(red: second.red, green: second.green, blue: second.blue)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Perceptual distance between two colours — CIE76 ΔE in CIELAB (design §4.1.1).
    ///
    /// Contrast and distance answer different questions, and REQ-016 needs both. Contrast asks
    /// *can this be read*; distance asks *can this be told apart from its neighbour*. The defect
    /// this palette exists to fix scores perfectly on the first and zero on the second: Neovim's
    /// default keyword colour is the **same value** as the plain foreground, so keywords are
    /// entirely readable and completely invisible as keywords. A contrast-only check calls that
    /// palette healthy.
    ///
    /// CIE76 rather than CIEDE2000 because §4.1.1 publishes CIE76 numbers, and a check that
    /// computes a different metric than the document it is checking is not a check.
    public static func colorDistance(_ first: RGBColor, _ second: RGBColor) -> Double {
        let start = perceptualComponents(of: first)
        let end = perceptualComponents(of: second)
        let lightness = start.lightness - end.lightness
        let greenRed = start.greenRed - end.greenRed
        let blueYellow = start.blueYellow - end.blueYellow
        return (lightness * lightness + greenRed * greenRed + blueYellow * blueYellow).squareRoot()
    }

    /// sRGB → CIELAB under a D65 white point, the illuminant sRGB is defined against.
    private static func perceptualComponents(
        of color: RGBColor
    ) -> (lightness: Double, greenRed: Double, blueYellow: Double) {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let red = linear(color.red)
        let green = linear(color.green)
        let blue = linear(color.blue)

        // Normalised by the D65 white so that white lands on L*=100.
        let x = (0.4124564 * red + 0.3575761 * green + 0.1804375 * blue) / 0.95047
        let y = 0.2126729 * red + 0.7151522 * green + 0.0721750 * blue
        let z = (0.0193339 * red + 0.1191920 * green + 0.9503041 * blue) / 1.08883

        // The linear segment near black keeps the curve from going vertical there.
        func adjust(_ value: Double) -> Double {
            value > 0.008856 ? cbrt(value) : (7.787 * value + 16.0 / 116.0)
        }
        let fx = adjust(x)
        let fy = adjust(y)
        let fz = adjust(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
}

/// An sRGB colour with components in 0...1, parsed from the hex values in design §4.1.
public struct RGBColor: Sendable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses `#RRGGBB`, the form the design document and the prototype stylesheet use.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return nil
        }
        self.red = Double((value >> 16) & 0xFF) / 255
        self.green = Double((value >> 8) & 0xFF) / 255
        self.blue = Double(value & 0xFF) / 255
    }
}
