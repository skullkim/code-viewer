/// The Neovim mode currently in effect, for the mode indicator.
///
/// The names come from Neovim's `mode_change` redraw event, which reports the *mode info* name
/// rather than the one-letter code `nvim_get_mode` returns. Measured against Neovim 0.12.5, the
/// names actually emitted while editing are: `normal`, `insert`, `visual`, `replace`,
/// `cmdline_normal`. Select mode — which standard input mode enters on shift-arrow — reports as
/// `visual`, so it shows as a selection rather than as an unknown mode.
///
/// `other` carries Neovim's own name for anything not modelled here, so a mode added by a future
/// release is still displayed rather than silently shown as normal.
public enum EditorMode: Sendable, Hashable {
    case normal
    case insert
    case visual
    case replace
    case commandLine
    case terminal
    case other(String)

    /// Neovim's `mode_change` name for this mode.
    public var neovimName: String {
        switch self {
        case .normal: return "normal"
        case .insert: return "insert"
        case .visual: return "visual"
        case .replace: return "replace"
        case .commandLine: return "cmdline_normal"
        case .terminal: return "terminal"
        case .other(let name): return name
        }
    }

    public init(neovimName: String) {
        switch neovimName {
        case "normal", "normal_visual_select", "operator":
            self = .normal
        case "insert":
            self = .insert
        // Select mode arrives under this name too, which is what the user means by "selected".
        case "visual", "visual_select":
            self = .visual
        case "replace", "virtual_replace", "insert_replace":
            self = .replace
        case "cmdline_normal", "cmdline_insert", "cmdline_replace":
            self = .commandLine
        case "terminal":
            self = .terminal
        default:
            self = .other(neovimName)
        }
    }
}
