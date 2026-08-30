import CoreGraphics

/// Turns a splitter drag into a width the layout will actually draw (REQ-011 AC-3).
///
/// `ShellLayout.clampTreeWidth` bounds a width by the design's own limits, which is right
/// for a stored preference but not for a live drag: those limits know nothing about the
/// window. In a 1000pt window with the panel at its default 340, the tree has room for 240
/// before the editor hits its 420 minimum — yet the design clamp accepts up to 480.
///
/// Dragging past that point produces two visible faults. The divider stops following the
/// pointer, because `columnWidths` quietly shrinks the area back to fit; and the width that
/// gets stored is one that never rendered, so the next launch in a wider window jumps to a
/// split the user never chose.
///
/// So the ceiling is computed against the window as well as the design, and the invariant
/// worth holding is a round trip: a width this returns is a width `ShellLayout.resolve`
/// gives back unchanged.
public enum ShellSplitDrag {

    /// The widest the tree can be drawn without pushing the editor below its minimum.
    public static func maximumTreeWidth(
        windowWidth: CGFloat,
        panelWidth: CGFloat,
        panelPlacement: ShellAreaPlacement
    ) -> CGFloat {
        // An overlay floats above the editor, so it costs the editor no width and the tree
        // may use the space the panel appears to occupy.
        let occupiedByPanel = panelPlacement == .column ? panelWidth : 0
        let available = windowWidth - occupiedByPanel - ShellLayout.Metrics.editorMinimumWidth
        return ceiling(available, designMaximum: ShellLayout.Metrics.treeMaximumWidth,
                       minimum: ShellLayout.Metrics.treeMinimumWidth)
    }

    /// The widest the panel can be drawn without pushing the editor below its minimum.
    public static func maximumPanelWidth(
        windowWidth: CGFloat,
        treeWidth: CGFloat,
        treePlacement: ShellAreaPlacement
    ) -> CGFloat {
        let occupiedByTree = treePlacement == .column ? treeWidth : 0
        let available = windowWidth - occupiedByTree - ShellLayout.Metrics.editorMinimumWidth
        return ceiling(available, designMaximum: ShellLayout.Metrics.panelMaximumWidth,
                       minimum: ShellLayout.Metrics.panelMinimumWidth)
    }

    public static func treeWidth(
        draggedTo proposed: CGFloat,
        windowWidth: CGFloat,
        panelWidth: CGFloat,
        panelPlacement: ShellAreaPlacement
    ) -> CGFloat {
        let maximum = maximumTreeWidth(
            windowWidth: windowWidth,
            panelWidth: panelWidth,
            panelPlacement: panelPlacement
        )
        return min(max(proposed, ShellLayout.Metrics.treeMinimumWidth), maximum)
    }

    public static func panelWidth(
        draggedTo proposed: CGFloat,
        windowWidth: CGFloat,
        treeWidth: CGFloat,
        treePlacement: ShellAreaPlacement
    ) -> CGFloat {
        let maximum = maximumPanelWidth(
            windowWidth: windowWidth,
            treeWidth: treeWidth,
            treePlacement: treePlacement
        )
        return min(max(proposed, ShellLayout.Metrics.panelMinimumWidth), maximum)
    }

    /// The design limit, further bounded by what the window can spare — but never below the
    /// area's own minimum.
    ///
    /// A window too narrow to seat the minimum is not a reason to return something smaller
    /// than the minimum: the layout's own shrink rule owns that case, and returning less
    /// here would put two different answers in play for one width.
    private static func ceiling(_ available: CGFloat, designMaximum: CGFloat, minimum: CGFloat) -> CGFloat {
        max(minimum, min(designMaximum, available))
    }
}
