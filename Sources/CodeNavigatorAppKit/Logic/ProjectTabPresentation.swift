import CoreGraphics
import Foundation

/// One tab as the bar draws it (02b §3 W-11).
public struct ProjectTabItem: Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    /// The parent folder, shown only when another open tab has the same name.
    public let secondaryLabel: String?
    public let isActive: Bool
    /// Whether this tab is drawn in the bar, or reached through the `≫` menu.
    public let isVisible: Bool
    public let isDirty: Bool
    public let showsIndexingSpinner: Bool
    /// The full path — kept out of the tab and put in a tooltip (W-11 drops it from the row).
    public let pathTooltip: String
    public let indexingTooltip: String?
    public let dirtyTooltip: String?
}

/// The whole tab bar (02b §3 W-11).
public struct ProjectTabBarPresentation: Sendable {
    /// False only with no tabs at all. One tab still shows the bar — §12 ruling 1: the
    /// toolbar's project popup was removed, so hiding the bar would leave the name of the
    /// open project nowhere on screen.
    public let isVisible: Bool
    public let items: [ProjectTabItem]
    public let tabWidth: CGFloat
    /// Tabs that do not fit, surfaced by the `≫ {n}` control.
    public let overflowCount: Int

    /// The tabs actually drawn, in order.
    public var visibleItems: [ProjectTabItem] { items.filter(\.isVisible) }
    /// The tabs reachable only through the `≫` menu.
    public var overflowItems: [ProjectTabItem] { items.filter { !$0.isVisible } }
    public var visibleCount: Int { items.count - overflowCount }
}

extension ProjectTabBarPresentation {

    /// Dimensions from 02b §3 W-11.
    public enum Metrics {
        public static let barHeight: CGFloat = 32
        public static let minimumTabWidth: CGFloat = 112
        public static let maximumTabWidth: CGFloat = 220
        /// The `＋` button, pinned to the trailing end whatever the tab count.
        public static let addButtonWidth: CGFloat = 28
        /// The `≫ {n}` overflow button, present only when tabs do not fit.
        public static let overflowButtonWidth: CGFloat = 28
    }

    public static func make(
        tabs: [ProjectTabDescriptor],
        activeTabID: String?,
        barWidth: CGFloat
    ) -> ProjectTabBarPresentation {
        guard !tabs.isEmpty else {
            return ProjectTabBarPresentation(isVisible: false, items: [], tabWidth: 0, overflowCount: 0)
        }

        let duplicated = duplicatedNames(in: tabs)
        let layout = layout(tabCount: tabs.count, barWidth: barWidth)
        let window = visibleWindow(
            tabCount: tabs.count,
            visibleCount: tabs.count - layout.overflowCount,
            activeIndex: tabs.firstIndex { $0.id == activeTabID }
        )

        let items = tabs.enumerated().map { index, tab in
            ProjectTabItem(
                id: tab.id,
                label: tab.name,
                // Only when it disambiguates. Adding it always would push the name — the
                // part that identifies the tab — out of a 112pt row for no gain.
                secondaryLabel: duplicated.contains(tab.name) ? parentFolderName(of: tab.rootPath) : nil,
                isActive: tab.id == activeTabID,
                isVisible: window.contains(index),
                isDirty: tab.isDirty,
                showsIndexingSpinner: tab.indexState != .ready,
                pathTooltip: tab.rootPath,
                indexingTooltip: indexingTooltip(for: tab.indexState),
                dirtyTooltip: tab.isDirty ? "저장하지 않은 변경 \(tab.dirtyBufferCount)건" : nil
            )
        }

        return ProjectTabBarPresentation(
            isVisible: true,
            items: items,
            tabWidth: layout.tabWidth,
            overflowCount: layout.overflowCount
        )
    }

    // MARK: 폭

    /// How wide each tab is, and how many do not fit.
    ///
    /// The overflow button only exists when there is overflow, and reserving its width
    /// changes whether there is overflow — so the fit is tried without it first. Reserving
    /// it unconditionally would push a borderline tab out and then show a `≫ 1` for a tab
    /// that would have fitted.
    static func layout(tabCount: Int, barWidth: CGFloat) -> (tabWidth: CGFloat, overflowCount: Int) {
        guard tabCount > 0 else {
            return (0, 0)
        }

        let withoutOverflowControl = max(0, barWidth - Metrics.addButtonWidth)
        if CGFloat(tabCount) * Metrics.minimumTabWidth <= withoutOverflowControl {
            let even = withoutOverflowControl / CGFloat(tabCount)
            return (min(max(even, Metrics.minimumTabWidth), Metrics.maximumTabWidth), 0)
        }

        let available = max(0, withoutOverflowControl - Metrics.overflowButtonWidth)
        let fitting = Int(available / Metrics.minimumTabWidth)
        // Even a single tab that cannot fit is still drawn; a bar with no tab at all would
        // hide the project entirely, which is what §12 ruling 1 forbids.
        let visible = max(1, min(fitting, tabCount))
        return (Metrics.minimumTabWidth, tabCount - visible)
    }

    /// Which slice of the tabs is drawn, always including the active one.
    ///
    /// 02b §5.3 requires the active tab to be scrolled into view, and a bar that reports
    /// only *how many* tabs fit cannot honour that — the view is left to assume "the first
    /// N", and the active tab silently disappears whenever it sits past them. Measured on
    /// eight tabs with the last active: at 900pt exactly one tab overflowed, and it was the
    /// active one, so `⌘9` changed the screen while the bar showed no selection at all.
    ///
    /// The window is pinned to the end of the range that contains the active tab, which is
    /// deterministic without a scroll position to remember.
    static func visibleWindow(tabCount: Int, visibleCount: Int, activeIndex: Int?) -> Range<Int> {
        guard tabCount > 0, visibleCount > 0 else {
            return 0..<0
        }
        let count = min(visibleCount, tabCount)
        guard let activeIndex, activeIndex >= 0, activeIndex < tabCount else {
            return 0..<count
        }

        // Show as many tabs before the active one as fit, without running past either end.
        let start = min(max(0, activeIndex - count + 1), max(0, tabCount - count))
        return start..<(start + count)
    }

    // MARK: 라벨

    /// Names shared by more than one open tab.
    ///
    /// Two checkouts of one repository are the common case, and they differ only by parent
    /// folder — the tab label alone cannot tell them apart.
    static func duplicatedNames(in tabs: [ProjectTabDescriptor]) -> Set<String> {
        var counts: [String: Int] = [:]
        for tab in tabs {
            counts[tab.name, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    static func parentFolderName(of path: String) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        let name = (parent as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    private static func indexingTooltip(for state: IndexStateSnapshot) -> String? {
        switch state {
        case .ready:
            return nil
        case .working(let label):
            return label
        }
    }
}
