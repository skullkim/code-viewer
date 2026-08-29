import Foundation

/// An opened project: one local repository root.
public struct ProjectDescriptor: Sendable, Hashable, Identifiable {
    public let name: String
    public let rootPath: URL

    public var id: String { rootPath.path }

    public init(name: String, rootPath: URL) {
        self.name = name
        self.rootPath = rootPath
    }

    public init(rootPath: URL) {
        self.name = rootPath.lastPathComponent
        self.rootPath = rootPath
    }
}
