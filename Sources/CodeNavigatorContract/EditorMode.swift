/// The Neovim mode currently in effect, for the mode indicator.
///
/// `other` carries Neovim's own mode name for modes we do not model explicitly,
/// so an unrecognised mode is still displayed rather than silently shown as normal.
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
        case "normal": self = .normal
        case "insert": self = .insert
        case "visual", "visual_select": self = .visual
        case "replace": self = .replace
        case "cmdline_normal", "cmdline_insert", "cmdline_replace": self = .commandLine
        case "terminal": self = .terminal
        default: self = .other(neovimName)
        }
    }
}
