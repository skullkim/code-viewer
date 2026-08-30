import Foundation

/// A key press the tab bar interprets (02b §4.1).
public enum ProjectTabKey: Sendable, Hashable {
    /// `⇧⌘]`
    case next
    /// `⇧⌘[`
    case previous
    /// `⌘1`…`⌘9`, one-based as the user counts them.
    case index(Int)
    /// `⌘W` — closes the tab, not the window (§12 ruling 3).
    case closeActive
}

/// What a tab key press asks for.
///
/// Closing is a *request* rather than an instruction: a tab with unsaved work opens the
/// confirmation sheet first (W-13), and that decision belongs to the view holding the sheet.
public enum ProjectTabAction: Sendable, Hashable {
    case activate(tabID: String)
    case requestClose(tabID: String)
    case none
}

/// What is left after a tab closes.
public struct ProjectTabClosure: Sendable, Hashable {
    public let remaining: [ProjectTabDescriptor]
    public let activeTabID: String?
    /// True when the last tab closed — §12 ruling 3 returns to the welcome screen rather
    /// than leaving an empty window with no way back.
    public let showsWelcome: Bool
}

/// Tab selection and closing (REQ-012 AC-2 · AC-3, 02b §4.1).
public enum ProjectTabCommand {

    /// The highest `⌘n` the design assigns.
    public static let highestIndexShortcut = 9

    public static func action(
        for key: ProjectTabKey,
        tabs: [ProjectTabDescriptor],
        activeTabID: String?
    ) -> ProjectTabAction {
        guard !tabs.isEmpty else {
            return .none
        }

        switch key {
        case .next:
            return .activate(tabID: neighbour(of: activeTabID, in: tabs, offset: 1))

        case .previous:
            return .activate(tabID: neighbour(of: activeTabID, in: tabs, offset: -1))

        case .index(let position):
            guard let tab = tab(atShortcutPosition: position, in: tabs) else {
                return .none
            }
            return .activate(tabID: tab.id)

        case .closeActive:
            guard let activeTabID, tabs.contains(where: { $0.id == activeTabID }) else {
                return .none
            }
            return .requestClose(tabID: activeTabID)
        }
    }

    /// The tab `⌘n` selects.
    ///
    /// `⌘9` is the **last** tab, not the ninth. That is what Safari, Finder and Terminal do,
    /// and 02b cites those three as the convention this design follows elsewhere; a `⌘9`
    /// that does nothing until nine projects are open would be dead most of the time.
    /// `⌘1`…`⌘8` are positional and do nothing when the position is empty.
    static func tab(atShortcutPosition position: Int, in tabs: [ProjectTabDescriptor]) -> ProjectTabDescriptor? {
        guard position >= 1, position <= highestIndexShortcut else {
            return nil
        }
        if position == highestIndexShortcut {
            return tabs.last
        }
        let index = position - 1
        return tabs.indices.contains(index) ? tabs[index] : nil
    }

    /// Cycling wraps at both ends, the way Safari's tab shortcuts do — with a handful of
    /// tabs, stopping at the edge just makes the key feel broken.
    private static func neighbour(
        of activeTabID: String?,
        in tabs: [ProjectTabDescriptor],
        offset: Int
    ) -> String {
        guard let activeTabID,
              let current = tabs.firstIndex(where: { $0.id == activeTabID })
        else {
            return tabs[0].id
        }
        let count = tabs.count
        return tabs[((current + offset) % count + count) % count].id
    }

    /// Applies a close, choosing what becomes active.
    public static func closing(
        tabID: String,
        tabs: [ProjectTabDescriptor],
        activeTabID: String?
    ) -> ProjectTabClosure {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return ProjectTabClosure(remaining: tabs, activeTabID: activeTabID, showsWelcome: tabs.isEmpty)
        }

        var remaining = tabs
        remaining.remove(at: index)

        guard !remaining.isEmpty else {
            return ProjectTabClosure(remaining: [], activeTabID: nil, showsWelcome: true)
        }

        // Closing a background tab must not move the user. Only closing the active tab
        // changes what is on screen.
        guard tabID == activeTabID else {
            return ProjectTabClosure(remaining: remaining, activeTabID: activeTabID, showsWelcome: false)
        }

        // The tab that slid into this slot, or the one before it at the end of the row —
        // the neighbour the eye is already on.
        let successor = remaining.indices.contains(index) ? remaining[index] : remaining[remaining.count - 1]
        return ProjectTabClosure(remaining: remaining, activeTabID: successor.id, showsWelcome: false)
    }
}
