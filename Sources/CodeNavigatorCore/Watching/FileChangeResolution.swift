/// What the indexer should do about a batch of changes.
enum FileChangeResolution: Equatable {
    /// Nothing pending.
    case none
    /// Re-index these paths individually.
    case incremental([String: FileChangeKind])
    /// Too much changed, or the watcher told us it dropped events. Rebuild from a fresh scan,
    /// which also restores INV-1 for files that vanished without an event of their own.
    case fullRescan
}
