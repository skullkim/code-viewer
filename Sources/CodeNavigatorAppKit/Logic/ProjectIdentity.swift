import Foundation

/// One open project tab, as the tab bar and the tab commands see it.
public struct ProjectTabDescriptor: Sendable, Hashable, Identifiable {
    /// The canonical identity from `ProjectIdentity.canonical(for:isCaseSensitiveVolume:)`.
    public let id: String
    /// The path as the user chose it, for display and for reopening.
    public let rootPath: String
    public let name: String
    public let dirtyBufferCount: Int
    public let indexState: IndexStateSnapshot

    public var isDirty: Bool { dirtyBufferCount > 0 }

    public init(
        id: String,
        rootPath: String,
        name: String,
        dirtyBufferCount: Int = 0,
        indexState: IndexStateSnapshot = .ready
    ) {
        self.id = id
        self.rootPath = rootPath
        self.name = name
        self.dirtyBufferCount = dirtyBufferCount
        self.indexState = indexState
    }
}

/// What a tab needs to know about its project's index.
///
/// A separate type from the engine's `IndexState` on purpose: a tab shows a spinner and a
/// tooltip, and nothing else. Passing the engine enum here would let a view reach for
/// progress numbers the design deliberately keeps out of a tab (02b §3 W-11).
public enum IndexStateSnapshot: Sendable, Hashable {
    case ready
    case working(label: String)
}

/// Whether opening a path makes a new tab or activates one that is already open.
public enum ProjectOpenResolution: Sendable, Hashable {
    case activateExisting(tabID: String)
    case openNew(identity: String)
}

/// Deciding when two paths are the same project (REQ-012 AC-5).
///
/// Two rules, and both are decisions rather than obvious defaults:
///
/// **Symlinks are resolved.** `/tmp/repo` and `/private/tmp/repo` are one directory, and
/// macOS hands back either depending on which API produced the path — the same trap that
/// silently broke the file-tree highlight in this build (03 §3.1). Comparing unresolved
/// paths would open a second tab onto the project already in the first, which is precisely
/// what AC-5 forbids.
///
/// **Case is folded only where the volume folds it.** macOS volumes are usually
/// case-insensitive, so `~/Repo` and `~/repo` are one directory and must share a tab. But
/// case-sensitive volumes exist, and there `App/` and `app/` are two projects — folding
/// case there would activate the wrong tab and show the user someone else's files. So the
/// caller supplies what the volume does; this function does not guess.
public enum ProjectIdentity {

    /// The identity two paths must share to be the same project.
    public static func canonical(for path: String, isCaseSensitiveVolume: Bool) -> String {
        // `resolvingSymlinksInPath` standardises (`.`, `..`, `~`) and resolves links in one
        // step, which is what makes /tmp and /private/tmp agree.
        var resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path

        if resolved.count > 1 && resolved.hasSuffix("/") {
            resolved.removeLast()
        }

        return isCaseSensitiveVolume ? resolved : resolved.lowercased()
    }

    /// AC-5: reopening an open project activates its tab instead of adding another.
    public static func resolve(
        requestedPath: String,
        openTabs: [ProjectTabDescriptor],
        isCaseSensitiveVolume: Bool
    ) -> ProjectOpenResolution {
        let identity = canonical(for: requestedPath, isCaseSensitiveVolume: isCaseSensitiveVolume)

        if let existing = openTabs.first(where: { $0.id == identity }) {
            return .activateExisting(tabID: existing.id)
        }
        return .openNew(identity: identity)
    }

    /// Whether the volume holding `path` distinguishes `App` from `app`.
    ///
    /// Asked of the filesystem rather than assumed, and kept out of `canonical` so the rule
    /// above stays a pure function.
    ///
    /// **A volume that cannot answer is treated as case-sensitive** — the paths are left
    /// alone. This follows the severity order stated above rather than the odds: folding
    /// case where it should not be folded activates a tab onto *a different project* and
    /// shows the user files they did not open, which is silent. Not folding where it could
    /// have been folded opens a second tab onto one project — visible, and closed with
    /// `⌘W`. When the two mistakes differ this much, the rarer-but-worse one is the one to
    /// design against.
    ///
    /// (An earlier version defaulted the other way, reasoning that case-insensitive is the
    /// macOS norm. That is an argument about frequency answering a question about damage,
    /// and it contradicted the rule directly above it.)
    public static func isCaseSensitiveVolume(at path: String) -> Bool {
        let values = try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        return values?.volumeSupportsCaseSensitiveNames ?? true
    }
}
