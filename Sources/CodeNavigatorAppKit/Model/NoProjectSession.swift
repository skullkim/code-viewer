import Foundation
import CodeNavigatorContract

/// Stands in while no project is open.
///
/// The welcome screen still builds a tree view, and a tree needs a session. Rather than
/// making every reader handle an optional — which would push "is a project open" into
/// thirteen call sites — the absence is expressed once, here, as a session that answers
/// nothing.
///
/// Every answer is the empty one. It never throws: a missing project is not an error the
/// user made, and turning it into one would put a failure on screen where the welcome
/// message belongs.
final class NoProjectSession: ProjectSession, @unchecked Sendable {

    func openProject(at rootPath: URL) async throws {}

    func currentProject() async -> ProjectDescriptor? { nil }

    func indexState() async -> IndexState { .notIndexed }

    func indexStateUpdates() async -> AsyncStream<IndexState> {
        AsyncStream { $0.finish() }
    }

    func definitions(named name: String) async -> [SymbolDefinition] { [] }

    func searchSymbols(matching query: String) async -> [SymbolSearchResult] { [] }

    func references(to symbolName: String) async throws -> ReferenceSearchResult {
        ReferenceSearchResult(references: [], total: 0, truncated: false, limit: 0)
    }

    func searchText(_ query: String, mode: TextSearchMode) async throws -> TextSearchResult {
        TextSearchResult(items: [], total: 0, truncated: false, limit: 0, filesSearched: 0)
    }

    func directoryEntries(atRelativePath relativePath: String) async throws -> [DirectoryEntry] { [] }

    func indexStatistics() async -> IndexStatistics {
        IndexStatistics(fileCount: 0, symbolCount: 0, skippedCount: 0, lastUpdatedAt: nil)
    }
}
