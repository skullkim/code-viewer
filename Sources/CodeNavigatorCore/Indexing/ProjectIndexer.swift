import CodeNavigatorContract
import Foundation

/// Builds and maintains the symbol index for one project.
///
/// The index is a derived product with no disk form, so opening a project always starts from a
/// full scan and the index can never be stale relative to a source tree it was not built from
/// (INV-2). Queries are answered in every state — during a rebuild the previous index answers,
/// and the state stream tells the interface that an update is running.
///
/// Nothing here writes to the project. Files are read, parsed, and dropped (INV-3).
public actor ProjectIndexer {
    /// How long to wait after the last change before acting, so a burst of saves becomes one pass.
    static let debounceInterval: Duration = .milliseconds(300)

    private let scanner = ProjectScanner()
    private let symbolIndex = SymbolIndex()

    private var projectRoot: URL?
    private var currentState: IndexState = .notIndexed
    private var stateBroadcaster = EventBroadcaster<IndexState>(initialValue: .notIndexed)
    private var watcher: FileSystemWatcher?
    private var pendingChanges = FileChangeBatch()
    private var debounceTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    /// Files that were scanned as indexable but produced nothing — unreadable, binary, oversized,
    /// or unparseable. Counted so the interface can show that the index is incomplete and why
    /// (REQ-002 AC-4 is otherwise invisible to the user).
    private var skippedFilePaths: Set<String> = []
    private var lastUpdatedAt: Date?

    public init() {}

    // MARK: - Project lifecycle

    /// Opens a project and starts indexing in the background.
    ///
    /// Validation happens before anything is torn down, so a bad path leaves the previously open
    /// project exactly as it was (REQ-001 AC-3).
    public func openProject(at rootPath: URL) async throws {
        let scan = try scanner.scan(rootPath: rootPath)

        stopWatching()
        await symbolIndex.clear()
        skippedFilePaths.removeAll()
        lastUpdatedAt = nil
        projectRoot = rootPath

        startWatching(rootPath: rootPath)
        await runFullIndexing(using: scan)
    }

    public func closeProject() async {
        stopWatching()
        debounceTask?.cancel()
        indexingTask?.cancel()
        await symbolIndex.clear()
        skippedFilePaths.removeAll()
        lastUpdatedAt = nil
        projectRoot = nil
        updateState(.notIndexed)
    }

    public func currentProject() -> ProjectDescriptor? {
        projectRoot.map { ProjectDescriptor(rootPath: $0) }
    }

    public func indexState() -> IndexState {
        currentState
    }

    public func indexStateUpdates() -> AsyncStream<IndexState> {
        stateBroadcaster.subscribe { [weak self] identifier in
            Task { await self?.unsubscribeState(identifier) }
        }
    }

    private func unsubscribeState(_ identifier: Int) {
        stateBroadcaster.unsubscribe(identifier)
    }

    // MARK: - Queries

    public func definitions(named name: String) async -> [SymbolDefinition] {
        await symbolIndex.definitions(named: name)
    }

    public func allDefinitions() async -> [SymbolDefinition] {
        await symbolIndex.allDefinitions()
    }

    public func hasDefinition(named name: String, atPath path: String, line: Int) async -> Bool {
        await symbolIndex.hasDefinition(named: name, atPath: path, line: line)
    }

    public func indexedFileCount() async -> Int {
        await symbolIndex.fileCount()
    }

    public func symbolCount() async -> Int {
        await symbolIndex.symbolCount()
    }

    public func statistics() async -> IndexStatistics {
        IndexStatistics(
            fileCount: await symbolIndex.fileCount(),
            symbolCount: await symbolIndex.symbolCount(),
            skippedCount: skippedFilePaths.count,
            lastUpdatedAt: lastUpdatedAt
        )
    }

    /// The current file list, used by full-text and reference search so that searching and
    /// indexing always agree on what the project contains.
    /// The index itself, for the searchers that need to ask whether a hit is a definition site.
    /// Handing over the actor keeps one index in the system rather than a copy that can drift.
    func symbolIndexForSearching() -> SymbolIndex {
        symbolIndex
    }

    func scanProjectFiles() throws -> ProjectScan {
        guard let projectRoot else {
            throw NavigatorError.noProjectOpen
        }
        return try scanner.scan(rootPath: projectRoot)
    }

    public func rootPath() -> URL? {
        projectRoot
    }

    // MARK: - Indexing

    private func runFullIndexing(using scan: ProjectScan) async {
        guard let projectRoot else { return }
        let paths = scan.indexableFilePaths
        updateState(.indexing(IndexProgress(completed: 0, total: paths.count)))

        let symbolsByPath = await Self.extractSymbols(forPaths: paths, projectRoot: projectRoot) { completed in
            await self.reportProgress(completed: completed, total: paths.count, isRescan: false)
        }

        skippedFilePaths = Set(paths).subtracting(symbolsByPath.keys)
        for (path, symbols) in symbolsByPath {
            await symbolIndex.replaceFile(path, with: symbols)
        }
        // Anything indexed but no longer scanned is gone. This is what restores INV-1 after a
        // change we never saw an event for.
        await symbolIndex.removeFiles(notIn: Set(paths))

        lastUpdatedAt = Date()
        updateState(.ready)
    }

    private func runFullRescan() async {
        guard let projectRoot, let scan = try? scanner.scan(rootPath: projectRoot) else {
            updateState(.ready)
            return
        }
        let paths = scan.indexableFilePaths
        updateState(.rescanning(IndexProgress(completed: 0, total: paths.count)))

        let symbolsByPath = await Self.extractSymbols(forPaths: paths, projectRoot: projectRoot) { completed in
            await self.reportProgress(completed: completed, total: paths.count, isRescan: true)
        }

        skippedFilePaths = Set(paths).subtracting(symbolsByPath.keys)
        for (path, symbols) in symbolsByPath {
            await symbolIndex.replaceFile(path, with: symbols)
        }
        await symbolIndex.removeFiles(notIn: Set(paths))
        lastUpdatedAt = Date()
        updateState(.ready)
    }

    /// Parses files concurrently, then hands finished results to the index.
    ///
    /// Each task builds its own extractor: tree-sitter parsers are not safe to share. Only the
    /// finished symbol arrays cross back, so the index is never a bottleneck for parsing.
    private static func extractSymbols(
        forPaths paths: [String],
        projectRoot: URL,
        onProgress: @escaping @Sendable (Int) async -> Void
    ) async -> [String: [SymbolDefinition]] {
        await withTaskGroup(of: (String, [SymbolDefinition])?.self) { group in
            for path in paths {
                group.addTask {
                    let fileURL = projectRoot.appendingPathComponent(path)
                    guard let text = SourceFileReader.readText(at: fileURL) else { return nil }
                    let extractor = SymbolExtractor()
                    return (path, extractor.extract(source: text, path: path))
                }
            }

            var results: [String: [SymbolDefinition]] = [:]
            var completed = 0
            for await result in group {
                completed += 1
                if completed % 200 == 0 {
                    await onProgress(completed)
                }
                guard let result else { continue }
                results[result.0] = result.1
            }
            return results
        }
    }

    private func reportProgress(completed: Int, total: Int, isRescan: Bool) {
        let progress = IndexProgress(completed: completed, total: total)
        updateState(isRescan ? .rescanning(progress) : .indexing(progress))
    }

    // MARK: - Incremental updates

    /// Re-indexes one file. Used by the watcher and by Neovim's own save notification, which
    /// arrives without waiting for the file system (REQ-009 AC-5).
    public func reindexFile(atRelativePath relativePath: String) async {
        guard let projectRoot else { return }
        guard SourceLanguage(filePath: relativePath) != nil else { return }

        let fileURL = projectRoot.appendingPathComponent(relativePath)
        guard let text = SourceFileReader.readText(at: fileURL) else {
            await symbolIndex.removeFile(relativePath)
            // Only counts as skipped if the file is still there; a deleted file is not a skip.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                skippedFilePaths.insert(relativePath)
            }
            lastUpdatedAt = Date()
            return
        }
        skippedFilePaths.remove(relativePath)
        let extractor = SymbolExtractor()
        await symbolIndex.replaceFile(relativePath, with: extractor.extract(source: text, path: relativePath))
        lastUpdatedAt = Date()
    }

    public func removeFile(atRelativePath relativePath: String) async {
        await symbolIndex.removeFile(relativePath)
        skippedFilePaths.remove(relativePath)
        lastUpdatedAt = Date()
    }

    /// Records a change and restarts the debounce window.
    func noteChange(relativePath: String, kind: FileChangeKind) {
        // A file we cannot index should not wake the indexer at all — editing a README must not
        // trigger a re-index pass.
        guard SourceLanguage(filePath: relativePath) != nil else { return }
        pendingChanges.note(path: relativePath, kind: kind)
        restartDebounce()
    }

    public func noteFullRescanRequired() {
        pendingChanges.requestFullRescan()
        restartDebounce()
    }

    private func restartDebounce() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: ProjectIndexer.debounceInterval)
            guard !Task.isCancelled else { return }
            await self?.applyPendingChanges()
        }
    }

    /// Applies whatever accumulated during the debounce window.
    func applyPendingChanges() async {
        let resolution = pendingChanges.drain()
        switch resolution {
        case .none:
            return

        case .fullRescan:
            await runFullRescan()

        case .incremental(let changes):
            updateState(.updating)
            // Re-scan once so a file that just became ignored is treated as removed, rather than
            // lingering in the index because it still exists on disk.
            let scannedPaths = (try? scanProjectFiles())?.fileSet ?? []
            for (path, kind) in changes {
                if kind == .removed || !scannedPaths.contains(path) {
                    await symbolIndex.removeFile(path)
                } else {
                    await reindexFile(atRelativePath: path)
                }
            }
            updateState(.ready)
        }
    }

    /// Waits for any in-flight debounce to settle, including one started while waiting.
    /// Tests use this instead of sleeping for a guessed duration.
    /// 테스트 전용 대기 지점. 제품 코드는 상태 스트림을 구독한다.
    func waitUntilIdle() async {
        while let task = debounceTask {
            debounceTask = nil
            _ = await task.value
        }
    }

    // MARK: - Watching

    private func startWatching(rootPath: URL) {
        let watcher = FileSystemWatcher(rootPath: rootPath.path) { [weak self] events in
            Task { await self?.handle(events: events) }
        }
        watcher.start()
        self.watcher = watcher
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    private func handle(events: [FileSystemChangeEvent]) {
        for event in events {
            if event.requiresFullRescan {
                noteFullRescanRequired()
                continue
            }
            guard let relativePath = event.relativePath else { continue }
            noteChange(relativePath: relativePath, kind: event.kind)
        }
    }

    private func updateState(_ newState: IndexState) {
        currentState = newState
        stateBroadcaster.send(newState)
    }
}
