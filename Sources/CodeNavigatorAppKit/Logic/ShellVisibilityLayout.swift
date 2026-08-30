import CoreGraphics

/// The shell's dimensions once the user's show/hide choices are applied (REQ-011 AC-3).
///
/// `ShellLayout` answers "how wide is each area in a window this size". It cannot answer
/// "is this area showing at all", because that is a user choice rather than a consequence
/// of the window — ⌥⌘1 hides the tree, ⌥⌘0 hides the panel (design §3 W-9), and both
/// choices come back on the next launch.
///
/// Hiding is not the same as making an area narrow. A hidden area occupies nothing, and the
/// space it gives up belongs to the editor — including space a *visible* neighbour had been
/// forced to give up. In a 1000pt window a tree dragged to 400 renders at 300, because the
/// panel and the editor's minimum leave nothing else; hide the panel and that same tree has
/// room for all 400. Reusing the width computed while the panel was showing would quietly
/// keep the tree small for a constraint that no longer exists.
public struct ShellVisibilityLayout: Sendable, Hashable {
    public let layout: ShellLayout
    /// Whether the area is drawn at all. `layout.treeWidth` is zero when it is not.
    public let isTreeMounted: Bool
    public let isPanelMounted: Bool
}

extension ShellVisibilityLayout {

    public static func resolve(
        windowSize: CGSize,
        preferredTreeWidth: CGFloat? = nil,
        preferredPanelWidth: CGFloat? = nil,
        isTreeVisible: Bool = true,
        isPanelVisible: Bool = true
    ) -> ShellVisibilityLayout {
        let base = ShellLayout.resolve(
            windowSize: windowSize,
            preferredTreeWidth: preferredTreeWidth,
            preferredPanelWidth: preferredPanelWidth
        )

        guard !isTreeVisible || !isPanelVisible else {
            // Both showing: this is exactly the case `ShellLayout` already arbitrates,
            // including the rule for who gives way when the editor's minimum is at stake.
            // Recomputing it here would put two answers in play for one window.
            return ShellVisibilityLayout(layout: base, isTreeMounted: true, isPanelMounted: true)
        }

        let windowWidth = windowSize.width
        var occupiedByColumns: CGFloat = 0

        var treeWidth: CGFloat = 0
        if isTreeVisible {
            if base.treePlacement == .overlay {
                // An overlay floats above the editor, so it has a width but costs none.
                treeWidth = ShellLayout.Metrics.treeOverlayWidth
            } else {
                treeWidth = soleColumnWidth(
                    preferred: ShellLayout.clampTreeWidth(
                        preferredTreeWidth ?? ShellLayout.Metrics.treeDefaultWidth
                    ),
                    windowWidth: windowWidth,
                    minimum: ShellLayout.Metrics.treeMinimumWidth
                )
                occupiedByColumns += treeWidth
            }
        }

        var panelWidth: CGFloat = 0
        if isPanelVisible {
            if base.panelPlacement == .overlay {
                panelWidth = ShellLayout.Metrics.panelOverlayWidth
            } else {
                panelWidth = soleColumnWidth(
                    preferred: ShellLayout.clampPanelWidth(
                        preferredPanelWidth ?? ShellLayout.Metrics.panelDefaultWidth
                    ),
                    windowWidth: windowWidth,
                    minimum: ShellLayout.Metrics.panelMinimumWidth
                )
                occupiedByColumns += panelWidth
            }
        }

        return ShellVisibilityLayout(
            layout: ShellLayout(
                titleBarHeight: base.titleBarHeight,
                tabBarHeight: base.tabBarHeight,
                statusBarHeight: base.statusBarHeight,
                contentHeight: base.contentHeight,
                treeWidth: treeWidth,
                editorWidth: max(0, windowWidth - occupiedByColumns),
                panelWidth: panelWidth,
                treePlacement: base.treePlacement,
                panelPlacement: base.panelPlacement,
                showsToolbarShortcutLabels: base.showsToolbarShortcutLabels,
                showsToolbarButtonTitles: base.showsToolbarButtonTitles,
                showsStatusBarHint: base.showsStatusBarHint,
                showsCursorPosition: base.showsCursorPosition,
                // Never hidden at any width or in any combination: they answer "which keys
                // am I typing" (REQ-010 AC-3) and "are these results current" (REQ-009).
                showsInputModeSegment: true,
                showsIndexChip: true
            ),
            isTreeMounted: isTreeVisible,
            isPanelMounted: isPanelVisible
        )
    }

    /// The width of the one side area still showing.
    ///
    /// With a single column there is no contest to arbitrate: it takes the width the user
    /// chose, and gives some back only if the editor would otherwise fall below its
    /// minimum — never going under its own.
    private static func soleColumnWidth(
        preferred: CGFloat,
        windowWidth: CGFloat,
        minimum: CGFloat
    ) -> CGFloat {
        let shortfall = ShellLayout.Metrics.editorMinimumWidth - (windowWidth - preferred)
        guard shortfall > 0 else {
            return preferred
        }
        return max(minimum, preferred - shortfall)
    }
}
