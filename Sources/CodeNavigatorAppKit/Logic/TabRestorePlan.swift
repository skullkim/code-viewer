import Foundation

/// A tab as it was written to disk at the end of the last session.
public struct SavedTab: Sendable, Hashable {
    public let identity: String
    public let rootPath: String
    public let displayName: String

    public init(identity: String, rootPath: String, displayName: String) {
        self.identity = identity
        self.rootPath = rootPath
        self.displayName = displayName
    }
}

/// Why a saved tab could not come back.
///
/// The two cases are kept apart because the user can act on one and not the other: a folder
/// that moved is gone, a folder they lack permission for is still there. Design 02b §7
/// forbids masking one as the other, and W-2 already words them separately — this reuses
/// that split rather than inventing a third vocabulary.
public enum TabRestoreFailure: Sendable, Hashable {
    case notFound
    case noPermission

    /// The sentence W-12's sheet shows, matching W-2's existing failure wording.
    public func message(displayName: String, rootPath: String) -> String {
        switch self {
        case .notFound:
            return "\(displayName) — 경로를 찾을 수 없습니다: \(rootPath)"
        case .noPermission:
            return "\(displayName) — 폴더에 접근할 권한이 없습니다: \(rootPath)"
        }
    }
}

/// A saved tab that did not come back, with the reason.
public struct TabRestoreOmission: Sendable, Hashable {
    public let tab: SavedTab
    public let reason: TabRestoreFailure

    public var message: String {
        reason.message(displayName: tab.displayName, rootPath: tab.rootPath)
    }
}

/// What to open at launch, and what to tell the user was dropped.
public struct TabRestorePlan: Sendable, Hashable {
    public let restored: [SavedTab]
    public let omitted: [TabRestoreOmission]
    /// Index into `restored`. Nil when nothing survived.
    public let activeIndex: Int?
    /// True when nothing was saved and nothing failed — the welcome screen, no sheet.
    public var isFirstRun: Bool { restored.isEmpty && omitted.isEmpty }
    /// The sheet is shown for any omission at all (W-12).
    public var showsFailureSheet: Bool { !omitted.isEmpty }
    public var showsWelcome: Bool { restored.isEmpty }
}

/// Restoring the tab list at launch (REQ-012 AC-4 · AC-6).
///
/// AC-6 is the whole reason this is a decision rather than a filter: a saved tab whose
/// folder is gone must be **told about**, not quietly dropped. Silently shortening the list
/// is indistinguishable from the app forgetting, and this build has already shipped one
/// silent failure that cost hours to find.
public enum TabRestorePlanner {

    /// - Parameter reachability: answers whether a path can be opened, and why not.
    ///   Injected so the plan can be tested without a disk — and so the real check can
    ///   later come from the engine, which is what actually opens these folders.
    public static func plan(
        saved: [SavedTab],
        activeIdentity: String?,
        reachability: (SavedTab) -> TabRestoreFailure?
    ) -> TabRestorePlan {
        var restored: [SavedTab] = []
        var omitted: [TabRestoreOmission] = []

        for tab in saved {
            if let reason = reachability(tab) {
                omitted.append(TabRestoreOmission(tab: tab, reason: reason))
            } else {
                restored.append(tab)
            }
        }

        return TabRestorePlan(
            restored: restored,
            omitted: omitted,
            activeIndex: activeIndex(in: restored, preferring: activeIdentity)
        )
    }

    /// The tab to show first.
    ///
    /// The saved active tab when it survived; otherwise the first that did. Falling back
    /// rather than opening nothing matters because the alternative — a window of tabs with
    /// none selected — has no equivalent in the design's states.
    private static func activeIndex(in restored: [SavedTab], preferring identity: String?) -> Int? {
        guard !restored.isEmpty else {
            return nil
        }
        if let identity, let index = restored.firstIndex(where: { $0.identity == identity }) {
            return index
        }
        return 0
    }
}
