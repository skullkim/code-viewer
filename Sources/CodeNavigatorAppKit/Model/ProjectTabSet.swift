import CodeNavigatorContract
import Foundation
import Observation

/// The open tabs and which one is active (ADR-0107, REQ-012).
///
/// Switching is one assignment. REQ-012 AC-2 asks for switching "재인덱싱 대기 없이 즉시",
/// and that is bought by keeping every tab's state alive and moving only `activeTabID` —
/// not by rebuilding the tab that comes forward.
///
/// Ordering decisions (who succeeds a closed tab, whether the welcome screen returns) are
/// not made here. They live in `ProjectTabCommand` as pure functions over descriptors, so
/// they can be tested without constructing sessions.
@MainActor
@Observable
public final class ProjectTabSet {

    public private(set) var tabs: [ProjectTabState] = []
    public private(set) var activeTabID: ProjectTabIdentifier?

    public init() {}

    public var activeTab: ProjectTabState? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    /// Opens a project, or activates the tab already showing it (REQ-012 AC-5).
    ///
    /// The existing tab is kept rather than replaced by the newcomer: replacing would
    /// discard the tree and index the user built up, which is the state AC-2 exists to
    /// preserve.
    public func open(_ tab: ProjectTabState) {
        if tabs.contains(where: { $0.id == tab.id }) {
            activeTabID = tab.id
            return
        }
        tabs.append(tab)
        activeTabID = tab.id
    }

    /// Activates a tab, ignoring an identifier no tab has.
    ///
    /// Ignoring is the point: pointing `activeTabID` at nothing empties the screen while
    /// the bar still shows tabs, which reads as the application breaking rather than a
    /// stale request being dropped.
    public func activate(id: ProjectTabIdentifier) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
    }

    /// Closes a tab and returns whether the welcome screen takes over (§12 ruling 3).
    @discardableResult
    public func close(id: ProjectTabIdentifier) -> Bool {
        // Succession is decided by the pure command layer, which speaks in the presentation
        // layer's string identities — so the identity is converted at the call and back
        // again, rather than the tab carrying two of them.
        let closure = ProjectTabCommand.closing(
            tabID: id.rawValue.uuidString,
            tabs: descriptors(),
            activeTabID: activeTabID?.rawValue.uuidString
        )
        let remaining = Set(closure.remaining.map(\.id))
        tabs.removeAll { !remaining.contains($0.id.rawValue.uuidString) }
        activeTabID = closure.activeTabID.flatMap { successor in
            tabs.first { $0.id.rawValue.uuidString == successor }?.id
        }
        return closure.showsWelcome
    }

    /// What the tab bar is built from.
    public func descriptors() -> [ProjectTabDescriptor] {
        tabs.map(\.descriptor)
    }
}
