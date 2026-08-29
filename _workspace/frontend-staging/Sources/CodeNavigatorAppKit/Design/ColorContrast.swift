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
