import Foundation

/// A summary of what the index currently holds.
///
/// `skippedCount` is the only place a user can see that some files were not indexed. Parse
/// failures, unreadable files and binaries are skipped silently by design so one bad file cannot
/// stop a run (REQ-002 AC-4) — but "silently" must not mean "invisibly", or the index quietly
/// under-reports and nobody knows why a symbol is missing.
public struct IndexStatistics: Sendable, Hashable {
    public let fileCount: Int
    public let symbolCount: Int
    public let skippedCount: Int
    /// When the last full or incremental pass finished. `nil` before the first one completes.
    public let lastUpdatedAt: Date?

    public init(fileCount: Int, symbolCount: Int, skippedCount: Int, lastUpdatedAt: Date?) {
        self.fileCount = fileCount
        self.symbolCount = symbolCount
        self.skippedCount = skippedCount
        self.lastUpdatedAt = lastUpdatedAt
    }
}
