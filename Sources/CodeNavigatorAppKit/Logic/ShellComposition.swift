/// A pane the main window can mount.
///
/// Named rather than implied so the window's wiring is something a test can state and
/// check. Views that compile and pass their own tests can still fail to reach the user if
/// nothing mounts them — that is exactly what happened here, with five finished views and
/// a window showing three grey stand-ins.
public enum ShellPane: String, Sendable, Hashable, CaseIterable {
    case projectOpen
    case fileTree
    case editorGrid
    case referencePanel
}

/// Decides which panes the main window mounts.
///
/// Kept apart from the view for the same reason every other judgement is: a `body` cannot
/// be asserted on, and "which panes are on screen" is a requirement (REQ-001 AC-1 for the
/// welcome screen, REQ-003 for the tree, REQ-004 AC-2 for the editor), not a detail.
public enum ShellComposition {

    /// The panes to mount, in leading-to-trailing order.
    ///
    /// With no project open the window is the welcome screen and nothing else — design §3
    /// W-1 says the three areas are replaced, not merely emptied.
    ///
    /// `isTreeVisible` and `isPanelVisible` are the 보기 menu's toggles (⌥⌘1 · ⌥⌘0). A
    /// hidden pane is genuinely absent, not merely narrow: the point of hiding it is to
    /// give the editor the room.
    public static func panes(
        hasOpenProject: Bool,
        layout: ShellLayout,
        isTreeVisible: Bool = true,
        isPanelVisible: Bool = true
    ) -> [ShellPane] {
        guard hasOpenProject else {
            return [.projectOpen]
        }

        var panes: [ShellPane] = []
        if isTreeVisible {
            panes.append(.fileTree)
        }
        // The editor is never hidden. It is the reason the window exists, and no menu row
        // offers to take it away.
        panes.append(.editorGrid)
        if isPanelVisible {
            panes.append(.referencePanel)
        }
        return panes
    }

    /// Whether a pane occupies a column of its own at this window size.
    public static func placement(of pane: ShellPane, layout: ShellLayout) -> ShellAreaPlacement {
        switch pane {
        case .fileTree: return layout.treePlacement
        case .referencePanel: return layout.panelPlacement
        case .editorGrid, .projectOpen: return .column
        }
    }
}
