import SwiftUI

/// A draggable divider between two shell areas (design §3 W-1).
///
/// The visible line is one pixel, but a one-pixel drag target is a line users chase rather
/// than grab, so the gesture area is widened around it. The resize cursor is what tells
/// them it can be grabbed at all.
struct ShellSplitter: View {

    /// Which way a drag makes the area grow: the tree grows to the right of its splitter,
    /// the panel grows to the left of its own.
    enum GrowthDirection {
        case trailing
        case leading
    }

    let width: CGFloat
    let direction: GrowthDirection
    let onChange: (CGFloat) -> Void

    @State private var widthAtDragStart: CGFloat?

    var body: some View {
        Rectangle()
            .fill(DesignTokens.border.dynamicColor)
            .frame(width: Metrics.lineWidth)
            .frame(width: Metrics.hitWidth)
            .contentShape(Rectangle())
            .onHover { isInside in
                if isInside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        // The width at the start of this drag, not the live one: reading
                        // the live width each frame compounds the translation and the
                        // divider runs away from the pointer.
                        let start = widthAtDragStart ?? width
                        widthAtDragStart = start
                        let delta = direction == .trailing ? value.translation.width : -value.translation.width
                        onChange(start + delta)
                    }
                    .onEnded { _ in widthAtDragStart = nil }
            )
            .accessibilityLabel("영역 크기 조절")
    }

    private enum Metrics {
        static let lineWidth: CGFloat = 1
        static let hitWidth: CGFloat = 7
    }
}
