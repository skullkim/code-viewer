/// One row of the project file tree (REQ-003). Directories are listed before files.
public struct DirectoryEntry: Sendable, Hashable, Identifiable {
    public let name: String
    public let path: String
    public let isDirectory: Bool

    public var id: String { path }

    public init(name: String, path: String, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
    }
}
