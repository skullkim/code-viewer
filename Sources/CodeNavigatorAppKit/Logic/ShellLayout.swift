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
        public static let statusBarHeight: CGFloat = 26

        public static let treeDefaultWidth: CGFloat = 240
        public static let treeMinimumWidth: CGFloat = 180
        public static let treeOverlayWidth: CGFloat = 220

        public static let panelDefaultWidth: CGFloat = 340
        public static let panelMinimumWidth: CGFloat = 280
        public static let panelOverlayWidth: CGFloat = 320

        public static let editorMinimumWidth: CGFloat = 420
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

    public static func resolve(windowSize: CGSize) -> ShellLayout {
        let width = windowSize.width
        let contentHeight = max(0, windowSize.height - Metrics.titleBarHeight - Metrics.statusBarHeight)

        let treePlacement: ShellAreaPlacement = width < Breakpoint.treeOverlay ? .overlay : .column
        let panelPlacement: ShellAreaPlacement = width < Breakpoint.panelOverlay ? .overlay : .column

        let widths = columnWidths(
            width: width,
            treePlacement: treePlacement,
            panelPlacement: panelPlacement
        )

        return ShellLayout(
            titleBarHeight: Metrics.titleBarHeight,
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

    private static func columnWidths(
        width: CGFloat,
        treePlacement: ShellAreaPlacement,
        panelPlacement: ShellAreaPlacement
    ) -> (tree: CGFloat, editor: CGFloat, panel: CGFloat) {
        // An overlay costs the editor nothing, so only the areas still in a column are
        // subtracted from the window width.
        let treeWidth = treePlacement == .overlay ? Metrics.treeOverlayWidth : Metrics.treeDefaultWidth
        let panelWidth = panelPlacement == .overlay ? Metrics.panelOverlayWidth : Metrics.panelDefaultWidth

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
