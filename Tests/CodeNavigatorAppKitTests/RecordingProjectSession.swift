import Foundation
import CodeNavigatorContract

/// A project session that records what was asked of it.
///
/// `FakeProjectSession` answers queries but does not remember them, and lazy loading
/// (REQ-003 AC-1) is a claim about *how many times* the engine is asked — a fake that only
/// returns the right entries cannot tell a lazy tree from an eager one. Kept separate
/// rather than added to the shared fake, which another agent owns.
final class RecordingProjectSession: ProjectSession, @unchecked Sendable {

    private let lock = NSLock()

    var directoryEntriesByPath: [String: [DirectoryEntry]] = [:]
    /// Paths whose listing fails, so a partial tree can be exercised.
    var failingDirectoryPaths: Set<String> = []
    var symbolSearchResults: [SymbolSearchResult] = []
    var referenceResult = ReferenceSearchResult(references: [], total: 0, truncated: false, limit: 500)
    var referenceError: Error?
    var textSearchResult = TextSearchResult(items: [], total: 0, truncated: false, limit: 500, filesSearched: 0)
    var textSearchError: Error?
    var statistics = IndexStatistics(fileCount: 0, symbolCount: 0, skippedCount: 0, lastUpdatedAt: nil)
    var openProjectError: Error?

    private(set) var requestedDirectoryPaths: [String] = []
    private(set) var symbolQueries: [String] = []
    private(set) var referenceQueries: [String] = []
    private(set) var textSearchQueries: [(query: String, mode: TextSearchMode)] = []
    private(set) var openedProjectPaths: [String] = []

    private var project: ProjectDescriptor?

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// How many times this exact directory was listed.
    func directoryRequestCount(for path: String) -> Int {
        locked { requestedDirectoryPaths.filter { $0 == path }.count }
    }

    func openProject(at rootPath: URL) async throws {
        if let openProjectError {
            throw openProjectError
        }
        locked {
            openedProjectPaths.append(rootPath.path)
            project = ProjectDescriptor(rootPath: rootPath)
        }
    }

    func currentProject() async -> ProjectDescriptor? {
        locked { project }
    }

    func indexState() async -> IndexState { .ready }

    func indexStateUpdates() async -> AsyncStream<IndexState> {
        AsyncStream { $0.finish() }
    }

    func definitions(named name: String) async -> [SymbolDefinition] { [] }

    func searchSymbols(matching query: String) async -> [SymbolSearchResult] {
        locked {
            symbolQueries.append(query)
            return symbolSearchResults
        }
    }

    func references(to symbolName: String) async throws -> ReferenceSearchResult {
        locked { referenceQueries.append(symbolName) }
        if let referenceError {
            throw referenceError
        }
        return referenceResult
    }

    func searchText(_ query: String, mode: TextSearchMode) async throws -> TextSearchResult {
        locked { textSearchQueries.append((query, mode)) }
        if let textSearchError {
            throw textSearchError
        }
        return textSearchResult
    }

    func directoryEntries(atRelativePath relativePath: String) async throws -> [DirectoryEntry] {
        locked { requestedDirectoryPaths.append(relativePath) }
        if failingDirectoryPaths.contains(relativePath) {
            throw NavigatorError.invalidPath(relativePath)
        }
        return locked { directoryEntriesByPath[relativePath] ?? [] }
    }

    func indexStatistics() async -> IndexStatistics {
        locked { statistics }
    }
}
