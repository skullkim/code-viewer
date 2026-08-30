import Foundation

/// Why a saved tab could not be reopened.
///
/// Kept apart because the user can do something different about each: a folder that is gone should
/// leave the list, while one that is merely unreadable comes back the moment access is granted.
/// Collapsing them would make the application offer the wrong remedy.
public enum TabRestoreFailureReason: Sendable, Hashable {
    case notFound
    case noPermission
}

/// A saved tab that did not come back.
public struct MissingTab: Sendable, Hashable {
    public let displayName: String
    public let rootPath: URL
    public let reason: TabRestoreFailureReason

    public init(displayName: String, rootPath: URL, reason: TabRestoreFailureReason) {
        self.displayName = displayName
        self.rootPath = rootPath
        self.reason = reason
    }
}

/// The result of restoring a saved session.
///
/// `missing` is part of the answer rather than a silent omission: a project that quietly fails to
/// reappear reads as the application having forgotten it, and the user's next move — reopening it
/// by hand — fails for a reason nobody has told them (REQ-012 AC-6).
public struct TabRestoreOutcome: Sendable {
    public let restored: [ProjectTab]
    public let missing: [MissingTab]

    public init(restored: [ProjectTab], missing: [MissingTab]) {
        self.restored = restored
        self.missing = missing
    }
}
