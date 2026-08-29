import CodeNavigatorContract
import Foundation

/// The engine's `ProjectSession` implementation: indexing, symbol lookup, and search.
///
/// Search reuses the scanner's file list rather than walking the tree itself, so what is indexed,
/// what is searched, and what the tree shows can never drift apart.
///
/// Every method here reads. There is no path from this type to a file write (INV-3).
public actor ProjectEngine: ProjectSession {
    private let indexer = ProjectIndexer()
    private let symbolSearcher = SymbolSearcher()
    private let textSearcher = TextSearcher()
    private let referenceSearcher = ReferenceSearcher()
    private let directoryTreeLister = DirectoryTreeLister()

    public init() {}

    // MARK: - Project

    public func openProject(at rootPath: URL) async throws {
        try await indexer.openProject(at: rootPath)
    }

    public func currentProject() async -> ProjectDescriptor? {
        await indexer.currentProject()
    }

    public func indexState() async -> IndexState {
        await indexer.indexState()
    }

    public func indexStateUpdates() async -> AsyncStream<IndexState> {
        await indexer.indexStateUpdates()
    }

    public func indexStatistics() async -> IndexStatistics {
        await indexer.statistics()
    }

    // MARK: - Symbols

    public func definitions(named name: String) async -> [SymbolDefinition] {
        await indexer.definitions(named: name)
    }

    public func searchSymbols(matching query: String) async -> [SymbolSearchResult] {
        let definitions = await indexer.allDefinitions()
        return symbolSearcher.search(query: query, in: definitions)
    }

    // MARK: - Search

    public func references(to symbolName: String) async throws -> ReferenceSearchResult {
        let context = try await searchContext()
        return await referenceSearcher.search(
            symbolName: symbolName,
            filePaths: context.scan.filePaths,
            rootPath: context.rootPath,
            symbolIndex: context.symbolIndex
        )
    }

    public func searchText(_ query: String, mode: TextSearchMode) async throws -> TextSearchResult {
        let context = try await searchContext()
        return try textSearcher.search(
            query: query,
            mode: mode,
            filePaths: context.scan.filePaths,
            rootPath: context.rootPath
        )
    }

    public func directoryEntries(atRelativePath relativePath: String) async throws -> [DirectoryEntry] {
        guard let rootPath = await indexer.rootPath() else {
            throw NavigatorError.noProjectOpen
        }
        return try directoryTreeLister.list(relativePath: relativePath, rootPath: rootPath)
    }

    // MARK: - Incremental updates

    /// Re-indexes a file the editor just wrote. Called with the absolute path Neovim reports, so
    /// an in-app save is reflected without waiting on the file watcher (REQ-009 AC-5).
    public func reindexSavedFile(atAbsolutePath absolutePath: String) async {
        guard let rootPath = await indexer.rootPath() else { return }
        let root = rootPath.path.hasSuffix("/") ? rootPath.path : rootPath.path + "/"
        guard absolutePath.hasPrefix(root) else { return }
        await indexer.reindexFile(atRelativePath: String(absolutePath.dropFirst(root.count)))
    }

    /// Waits for pending debounced work, so tests and the leader's verification can observe a
    /// settled index instead of guessing at a sleep duration.
    /// 테스트가 인덱싱 완료를 기다리기 위한 것. 계약 표면이 아니므로 internal 로 둔다.
    func waitUntilIndexIsIdle() async {
        await indexer.waitUntilIdle()
    }

    public func closeProject() async {
        await indexer.closeProject()
    }

    // MARK: - Helpers

    private struct SearchContext {
        let scan: ProjectScan
        let rootPath: URL
        let symbolIndex: SymbolIndex
    }

    private func searchContext() async throws -> SearchContext {
        guard let rootPath = await indexer.rootPath() else {
            throw NavigatorError.noProjectOpen
        }
        return SearchContext(
            scan: try await indexer.scanProjectFiles(),
            rootPath: rootPath,
            symbolIndex: await indexer.symbolIndexForSearching()
        )
    }
}
