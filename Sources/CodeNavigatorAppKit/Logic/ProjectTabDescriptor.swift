import Foundation

/// One open project tab, as the tab bar and the tab commands see it.
public struct ProjectTabDescriptor: Sendable, Hashable, Identifiable {
    /// The engine's identity for this tab, as a string.
    ///
    /// `ProjectTabIdentifier` wraps a UUID; this is `rawValue.uuidString`, converted at the
    /// one boundary where the presentation layer needs a `String` for `Identifiable`. Not
    /// the root path — a path would let a row keep naming a tab that was closed and
    /// reopened, and the engine deliberately moved off paths for that reason.
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
