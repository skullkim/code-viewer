import AppKit

extension AppearanceScheme {
    /// Which of the two palettes an AppKit appearance calls for.
    ///
    /// `bestMatch(from:)` is used rather than comparing `name` directly, because the effective
    /// appearance can be a vibrant or high-contrast variant whose name is none of the two we know.
    /// Comparing names would quietly fall through to light for a user running increased contrast
    /// in dark mode — a wrong answer that only that user ever sees.
    init(_ appearance: NSAppearance) {
        let match = appearance.bestMatch(from: [.aqua, .darkAqua])
        self = match == .darkAqua ? .dark : .light
    }
}
