import Foundation

/// What opening a project actually did.
///
/// The two cases are different events to the user — a tab appeared, or an existing one came
/// forward — and the wording differs. Returning nothing, or a `Bool`, would leave the application
/// to infer which happened by comparing tab counts before and after, and an inference like that is
/// wrong exactly when it matters: opening a project that was already open.
public enum ProjectOpenOutcome: Sendable, Hashable {
    case opened(ProjectTab)
    case activatedExisting(ProjectTab)

    public var tab: ProjectTab {
        switch self {
        case .opened(let tab), .activatedExisting(let tab):
            return tab
        }
    }
}
