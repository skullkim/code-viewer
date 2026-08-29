import CoreServices

/// Reads the FSEvents flag bits we act on.
///
/// Individual flags are not trusted on their own: measurement showed `ItemCreated`,
/// `ItemModified` and `ItemRenamed` arriving OR'd together, and the same path appearing twice in
/// one batch with different combinations. An editor's atomic save (write a temporary file, rename
/// it over the target) shows up as a rename, so a watcher that listens only for "modified" misses
/// most real saves. The rule that survives all of that is simply: if it is a file and it was not
/// removed, read it again.
struct FileSystemEventFlags {
    private let rawValue: FSEventStreamEventFlags

    init(rawValue: FSEventStreamEventFlags) {
        self.rawValue = rawValue
    }

    private func contains(_ flag: Int) -> Bool {
        rawValue & FSEventStreamEventFlags(flag) != 0
    }

    var isFile: Bool { contains(kFSEventStreamEventFlagItemIsFile) }
    var isDirectory: Bool { contains(kFSEventStreamEventFlagItemIsDir) }
    var wasRemoved: Bool { contains(kFSEventStreamEventFlagItemRemoved) }
    var wasRenamed: Bool { contains(kFSEventStreamEventFlagItemRenamed) }

    /// The watcher could not keep up and stopped itemising. Everything below must be rescanned.
    var requiresFullRescan: Bool {
        contains(kFSEventStreamEventFlagMustScanSubDirs)
            || contains(kFSEventStreamEventFlagUserDropped)
            || contains(kFSEventStreamEventFlagKernelDropped)
    }

    /// The watched root itself moved or was deleted, so the stream is watching nothing useful.
    var rootChanged: Bool { contains(kFSEventStreamEventFlagRootChanged) }

    /// A renamed path may be either the source (now gone) or the destination (now present), and
    /// the flags do not say which. Existence on disk is the only reliable answer.
    func changeKind(pathExists: Bool) -> FileChangeKind {
        if wasRemoved || !pathExists {
            return .removed
        }
        return .changed
    }
}
