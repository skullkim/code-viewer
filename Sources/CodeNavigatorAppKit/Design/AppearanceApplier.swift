import AppKit

/// Puts an `AppearancePreference` into effect.
///
/// Separate from the preference itself so the rule can be tested without a running application,
/// and separate from `AppModel` so the model never reaches for `NSApp` — a model that touches
/// application-global state cannot be built twice in one test process.
public enum AppearanceApplier {

    /// Setting this on the application rather than on the window is deliberate: panels, sheets and
    /// the menu bar are not in the window's view hierarchy, and a per-window appearance leaves
    /// them following the desktop while the window follows the user. Half-applied is worse than
    /// not applied — it reads as a rendering bug rather than as a setting.
    public static func apply(_ preference: AppearancePreference, to application: NSApplication) {
        application.appearance = preference.appearanceName.map { NSAppearance(named: $0) } ?? nil
    }
}
