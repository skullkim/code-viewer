import SwiftUI

/// The width a row should fill even when its own content is narrower.
///
/// Published by `BidirectionalScrollView` so rows can be **at least** as wide as the panel while
/// still being allowed to exceed it. A row that says `maxWidth: .infinity` instead is pinned to
/// the viewport, and then long text is clipped rather than scrolled to — which is the state the
/// tree shipped in.
private struct ScrollViewportWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var scrollViewportWidth: CGFloat {
        get { self[ScrollViewportWidthKey.self] }
        set { self[ScrollViewportWidthKey.self] = newValue }
    }
}

/// A list that scrolls sideways as well as down, with rows that still fill the viewport.
///
/// The tree and the reference panel both hold text longer than their column is wide — deep
/// package paths in one, source lines in the other — and both cut it with an ellipsis.
/// Truncation removes exactly the part that tells `SlackAlarmFailedEvent` from
/// `SlackAlarmFailedListener`, so the panel shows a name the reader cannot use while the whole
/// one sits a few pixels away.
///
/// AppKit turns a vertical wheel into a horizontal one while ⇧ is held, but only for a scroll
/// view that *can* scroll horizontally. Declaring the axis is what makes ⇧-scroll work; there is
/// no gesture handling here.
///
/// Two details are load-bearing, and both were found by watching the panel rather than by
/// reading the code:
///
/// - The viewport is measured from a **background**. Wrapping the scroll view in a
///   `GeometryReader` instead put the rows halfway down the panel.
/// - The content carries a **minimum height** as well as a minimum width. A two-axis scroll view
///   centres content vertically when it is shorter than the viewport, so a one-row tree floated
///   to the middle.
struct BidirectionalScrollView<Content: View>: View {
    @State private var viewport: CGSize = .zero

    /// How wide the content actually needs to be.
    ///
    /// Passed in rather than inferred. A lazy stack reports the width it was offered, so asking
    /// SwiftUI how wide the rows *want* to be returns the viewport and the scroll view concludes
    /// there is nothing to scroll — which is exactly the state this view shipped in first.
    /// The caller knows the strings, so the caller measures them.
    var contentWidth: CGFloat = 0

    @ViewBuilder var content: Content

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            content
                // A lazy stack takes the width it is offered, and inside a scroll view that is
                // the viewport — so a row wider than the panel was clipped instead of reachable.
                // `fixedSize` makes the stack take its own widest row instead.
                .frame(width: max(contentWidth, viewport.width), alignment: .topLeading)
                .frame(minHeight: viewport.height, alignment: .topLeading)
                .environment(\.scrollViewportWidth, viewport.width)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { viewport = proxy.size }
                    .onChange(of: proxy.size) { _, size in viewport = size }
            }
        }
    }
}

extension View {
    /// Makes a row span the panel without capping it there.
    ///
    /// `minWidth` rather than `maxWidth: .infinity`: the maximum form takes the proposed width,
    /// which inside a horizontal scroll view is the viewport — so the row can never be wider than
    /// the panel and its long text is clipped instead of reachable.
    func fillsScrollViewportWidth() -> some View {
        modifier(FillScrollViewportWidth())
    }
}

private struct FillScrollViewportWidth: ViewModifier {
    @Environment(\.scrollViewportWidth) private var viewportWidth

    func body(content: Content) -> some View {
        content.frame(minWidth: viewportWidth, alignment: .leading)
    }
}
