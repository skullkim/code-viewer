import AppKit

/// A menu row that AppKit itself performs (D-20).
///
/// These are the rows every Mac application has — 정보, 가리기, 종료, 최소화 — and they are
/// **not** application commands. `NSApplication` and `NSWindow` already implement them, and
/// the responder chain finds the implementation when the item's target is nil.
///
/// Modelled as a closed set rather than a raw `Selector` on the descriptor for two reasons.
/// The descriptor stays a plain value that tests can read without a running application; and a
/// selector written as a string is a **silent** failure — a typo compiles, the responder chain
/// finds nobody, and the row sits permanently disabled looking exactly like the bug this type
/// exists to fix. `MenuRowInvariantTests` asks the runtime whether each selector is real.
public enum MenuSystemAction: Sendable, Hashable, CaseIterable {
    case about
    case hide
    case hideOthers
    case showAll
    case quit
    case minimize
    case zoom
    case help
    /// Not an action. AppKit fills this submenu once it is handed to `NSApp.servicesMenu`;
    /// a row with a selector here would do nothing, because there is nothing to perform.
    case services

    /// Who in the responder chain is expected to perform this.
    ///
    /// Named so the test can ask the **right** object. Checking "NSApplication or NSWindow
    /// responds" would pass a window selector wrongly filed as an application one, and the row
    /// would then be disabled whenever no window is key — a bug that only appears sometimes,
    /// which is worse than one that always appears.
    public enum Responder: Sendable, Hashable {
        case application
        case window
        /// No action to perform; AppKit owns the row's contents instead.
        case none
    }

    public var responder: Responder {
        switch self {
        case .about, .hide, .hideOthers, .showAll, .quit, .help: return .application
        case .minimize, .zoom: return .window
        case .services: return .none
        }
    }

    public var selector: Selector? {
        switch self {
        case .about: return #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        case .hide: return #selector(NSApplication.hide(_:))
        case .hideOthers: return #selector(NSApplication.hideOtherApplications(_:))
        case .showAll: return #selector(NSApplication.unhideAllApplications(_:))
        case .quit: return #selector(NSApplication.terminate(_:))
        // Window actions travel the responder chain to the key window, which is what makes
        // them follow the window the user is actually looking at.
        case .minimize: return #selector(NSWindow.performMiniaturize(_:))
        case .zoom: return #selector(NSWindow.performZoom(_:))
        case .help: return #selector(NSApplication.showHelp(_:))
        case .services: return nil
        }
    }
}
