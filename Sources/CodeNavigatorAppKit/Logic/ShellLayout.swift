import CoreGraphics

/// Where a side area sits relative to the editor.
public enum ShellAreaPlacement: Sendable, Hashable {
    /// A column of its own; the editor gets what is left.
    case column
    /// Floating over the editor, so it costs the editor no width.
    case overlay
}

/// The resolved dimensions of the application shell for one window size.
///
/// Every size in the shell is decided here rather than inside a view body, because the
/// rules are a table (design §4.4) and a table deserves a test, not an eye. The prototype
/// lost its status bar at 820x620 when the editor grew vertically and covered it, so the
/// fixed chrome is subtracted first and the variable areas divide what remains — the
/// editor is never in a position to push the status bar out.
public struct ShellLayout: Sendable, Hashable {
    public let titleBarHeight: CGFloat
    /// The project tab strip, between the toolbar and the three areas (ADR-0108).
    ///
    /// Fixed, and unconditional: the leader ruled the strip shows even with a single tab
    /// (02b §12-1), because removing the toolbar's project popup left it as the only place
    /// the open project's name appears. So the height budget carries no branch.
    public let tabBarHeight: CGFloat
    public let statusBarHeight: CGFloat
    public let contentHeight: CGFloat
    public let treeWidth: CGFloat
    public let editorWidth: CGFloat
    public let panelWidth: CGFloat
    public let treePlacement: ShellAreaPlacement
    public let panelPlacement: ShellAreaPlacement
    public let showsToolbarShortcutLabels: Bool
    public let showsToolbarButtonTitles: Bool
    public let showsStatusBarHint: Bool
    public let showsCursorPosition: Bool
    /// The input mode is the answer to "which keys am I typing" (REQ-010 AC-3), and the
    /// index chip to "are these results current" (REQ-009). Neither is ever hidden.
    public let showsInputModeSegment: Bool
    public let showsIndexChip: Bool
}

extension ShellLayout {
    /// Fixed dimensions from design §4.3.
    public enum Metrics {
        public static let titleBarHeight: CGFloat = 48
        public static let tabBarHeight: CGFloat = 32
        public static let statusBarHeight: CGFloat = 26

        /// What the three areas never get: 48 + 32 + 26.
        ///
        /// Subtracted before anything variable is sized. The editor pushed the status bar
        /// off screen once by growing into it (ADR-0104); a third fixed row is a third
        /// chance to repeat that, so the total lives here rather than in view bodies.
        public static var fixedChromeHeight: CGFloat {
            titleBarHeight + tabBarHeight + statusBarHeight
        }

        public static let treeDefaultWidth: CGFloat = 240
        public static let treeMinimumWidth: CGFloat = 180
        public static let treeOverlayWidth: CGFloat = 220

        public static let panelDefaultWidth: CGFloat = 340
        public static let panelMinimumWidth: CGFloat = 280
        public static let panelOverlayWidth: CGFloat = 320

        public static let editorMinimumWidth: CGFloat = 420

        /// How far a splitter may be dragged before the side area stops growing. Without a
        /// ceiling a stored width from a wide monitor would swallow a narrow window whole.
        public static let treeMaximumWidth: CGFloat = 480
        public static let panelMaximumWidth: CGFloat = 600
    }

    /// Window widths at which the layout changes, from design §4.4.
    public enum Breakpoint {
        /// Below this the toolbar buttons drop their shortcut labels.
        public static let toolbarShortcutLabels: CGFloat = 1100
        /// Below this the right panel floats over the editor and status hints are dropped.
        public static let panelOverlay: CGFloat = 900
        /// Below this the file tree floats too, toolbar buttons become icons, and the
        /// status bar drops the language and cursor position.
        public static let treeOverlay: CGFloat = 720
    }

    /// Resolves the shell for a window size.
    ///
    /// `preferredTreeWidth` and `preferredPanelWidth` are the widths the user dragged the
    /// splitters to, restored from the last run (REQ-011 AC-3). They are preferences, not
    /// commands: the editor's minimum still outranks them, so a stored width from a wider
    /// monitor cannot squeeze the editor out on a smaller one.
    public static func resolve(
        windowSize: CGSize,
        preferredTreeWidth: CGFloat? = nil,
        preferredPanelWidth: CGFloat? = nil
    ) -> ShellLayout {
        let width = windowSize.width
        let contentHeight = max(0, windowSize.height - Metrics.fixedChromeHeight)

        let treePlacement: ShellAreaPlacement = width < Breakpoint.treeOverlay ? .overlay : .column
        let panelPlacement: ShellAreaPlacement = width < Breakpoint.panelOverlay ? .overlay : .column

        let widths = columnWidths(
            width: width,
            treePlacement: treePlacement,
            panelPlacement: panelPlacement,
            preferredTreeWidth: preferredTreeWidth,
            preferredPanelWidth: preferredPanelWidth
        )

        return ShellLayout(
            titleBarHeight: Metrics.titleBarHeight,
            tabBarHeight: Metrics.tabBarHeight,
            statusBarHeight: Metrics.statusBarHeight,
            contentHeight: contentHeight,
            treeWidth: widths.tree,
            editorWidth: widths.editor,
            panelWidth: widths.panel,
            treePlacement: treePlacement,
            panelPlacement: panelPlacement,
            showsToolbarShortcutLabels: width >= Breakpoint.toolbarShortcutLabels,
            showsToolbarButtonTitles: width >= Breakpoint.treeOverlay,
            showsStatusBarHint: width >= Breakpoint.panelOverlay,
            showsCursorPosition: width >= Breakpoint.treeOverlay,
            showsInputModeSegment: true,
            showsIndexChip: true
        )
    }

    /// Clamps a dragged width to what the design allows for that area.
    public static func clampTreeWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, Metrics.treeMinimumWidth), Metrics.treeMaximumWidth)
    }

    public static func clampPanelWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, Metrics.panelMinimumWidth), Metrics.panelMaximumWidth)
    }

    private static func columnWidths(
        width: CGFloat,
        treePlacement: ShellAreaPlacement,
        panelPlacement: ShellAreaPlacement,
        preferredTreeWidth: CGFloat?,
        preferredPanelWidth: CGFloat?
    ) -> (tree: CGFloat, editor: CGFloat, panel: CGFloat) {
        // An overlay costs the editor nothing, so only the areas still in a column are
        // subtracted from the window width. An overlay also has a fixed width of its own,
        // so a dragged column width does not carry into it.
        let treeWidth = treePlacement == .overlay
            ? Metrics.treeOverlayWidth
            : clampTreeWidth(preferredTreeWidth ?? Metrics.treeDefaultWidth)
        let panelWidth = panelPlacement == .overlay
            ? Metrics.panelOverlayWidth
            : clampPanelWidth(preferredPanelWidth ?? Metrics.panelDefaultWidth)

        guard treePlacement == .column, panelPlacement == .column else {
            let occupied = (treePlacement == .column ? treeWidth : 0)
                + (panelPlacement == .column ? panelWidth : 0)
            return (treeWidth, max(0, width - occupied), panelWidth)
        }

        // Both are columns. The editor's minimum outranks the side areas' preferred widths,
        // so the shortfall is taken from the panel first and from the tree only if that is
        // not enough. Neither goes below its own minimum.
        let shortfall = Metrics.editorMinimumWidth - (width - treeWidth - panelWidth)
        guard shortfall > 0 else {
            return (treeWidth, width - treeWidth - panelWidth, panelWidth)
        }

        let panelGive = min(shortfall, panelWidth - Metrics.panelMinimumWidth)
        let shrunkPanel = panelWidth - panelGive

        let treeGive = min(shortfall - panelGive, treeWidth - Metrics.treeMinimumWidth)
        let shrunkTree = treeWidth - treeGive

        return (shrunkTree, width - shrunkTree - shrunkPanel, shrunkPanel)
    }
}
