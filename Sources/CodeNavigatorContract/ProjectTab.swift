import Foundation

/// One open project, as the tab bar draws it.
public struct ProjectTab: Sendable, Hashable, Identifiable {
    public let id: ProjectTabIdentifier

    /// The root directory's own name — what the user calls this project.
    public let displayName: String

    /// The canonical root. Normalisation belongs to the engine, and this is its answer: an
    /// application that normalised paths its own way would open the same project twice under two
    /// spellings and be unable to tell they were one project.
    public let rootPath: URL

    /// Only set when another open tab has the same `displayName`, and then only as much as it
    /// takes to tell them apart. Shown always, it would be noise on every tab.
    public let disambiguator: String?

    public init(
        id: ProjectTabIdentifier,
        displayName: String,
        rootPath: URL,
        disambiguator: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.rootPath = rootPath
        self.disambiguator = disambiguator
    }
}
