import SwiftUI

/// What the tab bar asks the application to do.
public enum ProjectTabBarAction: Sendable, Hashable {
    case activate(tabID: String)
    /// A close *request* — a tab with unsaved work opens the confirmation sheet first (W-13).
    case requestClose(tabID: String)
    /// The trailing `＋`.
    case openProject
}

/// The project tab bar (design 02b §3 W-11, REQ-012 AC-1·2·3).
///
/// A fixed 32pt chrome row. It asks for that height and nothing more — `ShellLayout`
/// subtracts the fixed chrome before the variable areas divide what remains (ADR-0104,
/// ADR-0108), and a bar that took residual height is the mechanism by which the editor once
/// pushed the status bar off screen.
///
/// Every decision it draws comes from `ProjectTabBarPresentation`: which tabs are visible,
/// which carry a parent-folder suffix, which show a spinner. The view re-derives none of it.
public struct ProjectTabBarView: View {

    private let bar: ProjectTabBarPresentation
    private let onAction: (ProjectTabBarAction) -> Void

    @State private var hoveredTabID: String?

    public init(bar: ProjectTabBarPresentation, onAction: @escaping (ProjectTabBarAction) -> Void) {
        self.bar = bar
        self.onAction = onAction
    }

    public var body: some View {
        // §12 ruling 1: the bar stays even at one tab. The toolbar's project popup was
        // removed, so hiding it would leave the open project's name nowhere on screen.
        if bar.isVisible {
            HStack(spacing: 0) {
                tabs
                Spacer(minLength: 0)
                trailingControls
            }
            .frame(height: ShellLayout.Metrics.tabBarHeight)
            .background(DesignTokens.backgroundWindow.dynamicColor)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DesignTokens.border.dynamicColor)
                    .frame(height: Metrics.hairline)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("프로젝트 탭")
        }
    }

    private var tabs: some View {
        // Only the visible slice is drawn. The presentation guarantees the active tab is in
        // it, which the view must not have to arrange for itself.
        ForEach(bar.visibleItems) { item in
            tabView(item)
                .frame(width: bar.tabWidth)
        }
    }

    private func tabView(_ item: ProjectTabItem) -> some View {
        HStack(spacing: Metrics.contentSpacing) {
            if item.showsIndexingSpinner {
                // A background tab's indexing appears nowhere else — the status bar belongs
                // to the active tab.
                MotionSafeSpinner(tone: foreground(item), size: Metrics.spinnerSize)
                    .help(item.indexingTooltip ?? "")
            }

            label(item)

            Spacer(minLength: 0)

            trailingSlot(item)
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .frame(maxHeight: .infinity)
        .background(background(item))
        .overlay(alignment: .top) {
            // Active is marked four ways — fill, weight, this line, and the accessibility
            // trait — because §4.5 forbids colour as the only signal.
            if item.isActive {
                Rectangle()
                    .fill(DesignTokens.accent.dynamicColor)
                    .frame(height: Metrics.activeIndicatorHeight)
            }
        }
        .overlay(alignment: .trailing) {
            if !item.isActive {
                Rectangle()
                    .fill(DesignTokens.border.dynamicColor)
                    .frame(width: Metrics.hairline)
                    .padding(.vertical, Metrics.separatorInset)
            }
        }
        .contentShape(Rectangle())
        .onHover { hoveredTabID = $0 ? item.id : (hoveredTabID == item.id ? nil : hoveredTabID) }
        .onTapGesture { onAction(.activate(tabID: item.id)) }
        .help(item.pathTooltip)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(item))
        .accessibilityAddTraits(item.isActive ? [.isButton, .isSelected] : .isButton)
    }

    private func label(_ item: ProjectTabItem) -> some View {
        HStack(spacing: Metrics.labelSpacing) {
            Text(item.label)
                .font(.system(size: Metrics.labelSize, weight: item.isActive ? .semibold : .medium))
                .foregroundStyle(foreground(item))
                // Repository names share prefixes far more often than suffixes
                // (`code-navigator-mac` / `code-navigator-web`), so trimming the tail would
                // make two tabs read identically.
                .truncationMode(.middle)
                .lineLimit(1)

            if let secondary = item.secondaryLabel {
                Text(secondary)
                    .font(.system(size: Metrics.secondaryLabelSize))
                    .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
    }

    /// The dirty dot and the close button share one slot (W-11).
    ///
    /// An inactive tab shows its dirty dot until pointed at, then offers the close button;
    /// the active tab keeps the close button available, since it is the one most often
    /// closed. `⌘W` covers both, so nothing here is the only path to closing a tab.
    @ViewBuilder
    private func trailingSlot(_ item: ProjectTabItem) -> some View {
        let showsClose = item.isActive || hoveredTabID == item.id

        ZStack {
            if showsClose {
                Button {
                    onAction(.requestClose(tabID: item.id))
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: Metrics.closeGlyphSize, weight: .semibold))
                        .foregroundStyle(foreground(item))
                        .frame(width: Metrics.slotSize, height: Metrics.slotSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("'\(item.label)' 탭 닫기")
            } else if item.isDirty {
                Circle()
                    .fill(DesignTokens.warningSolid.dynamicColor)
                    .frame(width: Metrics.dirtyDotSize, height: Metrics.dirtyDotSize)
                    .help(item.dirtyTooltip ?? "")
            }
        }
        .frame(width: Metrics.slotSize, height: Metrics.slotSize)
    }

    private var trailingControls: some View {
        HStack(spacing: 0) {
            if bar.overflowCount > 0 {
                Menu {
                    // Every tab is reachable here, so the horizontal scroll is never the
                    // only way to a tab (W-11 accessibility).
                    ForEach(bar.items) { item in
                        Button {
                            onAction(.activate(tabID: item.id))
                        } label: {
                            Text(item.isActive ? "✓ \(item.label)" : item.label)
                        }
                    }
                } label: {
                    Text("≫ \(GroupedNumberText.string(bar.overflowCount))")
                        .font(.system(size: Metrics.secondaryLabelSize))
                        .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: Metrics.controlWidth)
                .accessibilityLabel("숨은 탭 \(bar.overflowCount)개")
            }

            Button {
                onAction(.openProject)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: Metrics.controlGlyphSize))
                    .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                    .frame(width: Metrics.controlWidth, height: ShellLayout.Metrics.tabBarHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("프로젝트 열기")
        }
    }

    // MARK: 색

    private func background(_ item: ProjectTabItem) -> Color {
        if item.isActive {
            return DesignTokens.backgroundContent.dynamicColor
        }
        if hoveredTabID == item.id {
            return DesignTokens.backgroundHover.dynamicColor
        }
        return .clear
    }

    private func foreground(_ item: ProjectTabItem) -> Color {
        item.isActive
            ? DesignTokens.textPrimary.dynamicColor
            : DesignTokens.textSecondary.dynamicColor
    }

    private func accessibilityLabel(_ item: ProjectTabItem) -> String {
        var parts = [item.label]
        if let secondary = item.secondaryLabel {
            parts.append(secondary)
        }
        if item.showsIndexingSpinner {
            parts.append("인덱싱 중")
        }
        if item.isDirty {
            parts.append("저장하지 않은 변경 있음")
        }
        return parts.joined(separator: ", ")
    }

    /// Dimensions from 02b §3 W-11.
    private enum Metrics {
        static let horizontalPadding: CGFloat = 10
        static let contentSpacing: CGFloat = 6
        static let labelSpacing: CGFloat = 4
        /// 12.5pt rather than 11: the designer measured 11pt smudging on non-Retina.
        static let labelSize: CGFloat = 12.5
        static let secondaryLabelSize: CGFloat = 11.5
        static let slotSize: CGFloat = 22
        static let closeGlyphSize: CGFloat = 11
        static let dirtyDotSize: CGFloat = 7
        static let spinnerSize: CGFloat = 10
        static let controlWidth: CGFloat = 28
        static let controlGlyphSize: CGFloat = 12
        static let activeIndicatorHeight: CGFloat = 2
        static let hairline: CGFloat = 1
        static let separatorInset: CGFloat = 6
    }
}
