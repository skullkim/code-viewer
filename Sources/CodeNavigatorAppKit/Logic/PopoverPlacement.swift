import CoreGraphics

/// Where a cursor-anchored popover ends up (design §3 W-4).
public struct PopoverPlacement: Sendable, Hashable {
    /// The popover's top-left corner, in the anchoring area's coordinate space.
    public let origin: CGPoint
    /// True when the popover was put above the anchor because it did not fit below.
    public let isFlippedAbove: Bool
}

extension PopoverPlacement {
    /// Gap between the anchored line and the popover.
    static let anchorGap: CGFloat = 4
    /// How close the popover may come to the edge of the area.
    static let edgeMargin: CGFloat = 8

    /// Places a popover under the anchor, flipping it above when there is no room.
    ///
    /// The anchor is the cursor's cell, so the popover must never cover it — reading the
    /// candidates while the line they refer to is hidden is the one thing this popover
    /// cannot do. Falling off the bottom of the window is worse still, so when neither side
    /// has room the popover stays inside the area and above the cursor, where the code
    /// being navigated from is visible.
    public static func place(
        anchor: CGRect,
        contentSize: CGSize,
        in area: CGSize
    ) -> PopoverPlacement {
        let spaceBelow = area.height - anchor.maxY - anchorGap - edgeMargin
        let fitsBelow = spaceBelow >= contentSize.height

        let unclampedY = fitsBelow
            ? anchor.maxY + anchorGap
            : anchor.minY - anchorGap - contentSize.height

        let maximumY = max(edgeMargin, area.height - contentSize.height - edgeMargin)
        let y = min(max(unclampedY, edgeMargin), maximumY)

        let maximumX = max(edgeMargin, area.width - contentSize.width - edgeMargin)
        let x = min(max(anchor.minX, edgeMargin), maximumX)

        return PopoverPlacement(origin: CGPoint(x: x, y: y), isFlippedAbove: !fitsBelow)
    }

    /// The cursor's cell as a rectangle the popover can anchor to.
    ///
    /// SwiftUI's origin is top-left with y growing downward, which is what `place` expects,
    /// so a row is simply its index times the cell height. `GridGeometry.cellRect` is
    /// deliberately not reused: it answers the same question in Core Graphics' flipped
    /// space for the renderer, and mixing the two spaces puts the popover above the cursor
    /// exactly when it means below — a fault that looks like a layout quirk rather than a
    /// coordinate bug.
    public static func cursorAnchor(row: Int, column: Int, cellSize: CGSize) -> CGRect {
        CGRect(
            x: CGFloat(column) * cellSize.width,
            y: CGFloat(row) * cellSize.height,
            width: cellSize.width,
            height: cellSize.height
        )
    }
}
