import AppKit

/// What the user asked the window to look like, which is not the same as what it currently looks
/// like. `AppearanceScheme` is the answer ("this window is dark right now"); this is the question
/// ("follow the system, or override it").
///
/// The two have to stay separate. Storing a resolved scheme would freeze whatever the desktop
/// happened to be on the day the preference was saved, and "시스템 설정 따름" would quietly stop
/// following anything.
public enum AppearancePreference: String, Sendable, Hashable, CaseIterable {
    case system
    case light
    case dark

    /// The appearance to force on the application, or `nil` to leave it alone.
    ///
    /// `nil` is the whole of "follow the system": AppKit resolves an unset appearance against the
    /// desktop on every read, so the window keeps tracking it as the user flips the system switch.
    public var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: return nil
        case .light: return .aqua
        case .dark: return .darkAqua
        }
    }
}
