import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Fakes for the two engine protocols.
///
/// The contract is a Swift protocol rather than HTTP, so the frontend can drive the exact
/// sequences it needs — a session that dies mid-edit, an index that finishes after a
/// query — without a Neovim process or a repository on disk.
final class FakeProjectSession: ProjectSession, @unchecked Sendable {
    private let lock = NSLock()
    private var project: ProjectDescriptor?
    private var currentIndexState: IndexState = .notIndexed
    private var indexContinuation: AsyncStream<IndexState>.Continuation?

    var openProjectError: Error?
    var definitionsByName: [String: [SymbolDefinition]] = [:]
    var symbolSearchResults: [SymbolSearchResult] = []
    var referenceResult: ReferenceSearchResult = ReferenceSearchResult(references: [], total: 0, truncated: false, limit: 500)
    var textSearchResult: TextSearchResult = TextSearchResult(items: [], total: 0, truncated: false, limit: 500)
    var textSearchError: Error?
    var directoryEntries: [String: [DirectoryEntry]] = [:]
    var statistics = IndexStatistics(fileCount: 0, symbolCount: 0, skippedCount: 0, lastUpdatedAt: nil)


    /// A synchronous critical section. `NSLock.lock()` cannot be called from an async
    /// context, and every accessor here is reached from one.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func openProject(at rootPath: URL) async throws {
        if let openProjectError {
            throw openProjectError
        }
        locked { project = ProjectDescriptor(rootPath: rootPath) }
    }

    func currentProject() async -> ProjectDescriptor? {
        locked { project }
    }

    func indexState() async -> IndexState {
        locked { currentIndexState }
    }

    func indexStatistics() async -> IndexStatistics {
        locked { statistics }
    }

    func indexStateUpdates() async -> AsyncStream<IndexState> {
        AsyncStream { continuation in
            let current = locked { () -> IndexState in
                indexContinuation = continuation
                return currentIndexState
            }
            continuation.yield(current)
        }
    }

    /// Pushes a state the way the engine would.
    func emitIndexState(_ state: IndexState) {
        let continuation = locked { () -> AsyncStream<IndexState>.Continuation? in
            currentIndexState = state
            return indexContinuation
        }
        continuation?.yield(state)
    }

    func definitions(named name: String) async -> [SymbolDefinition] {
        definitionsByName[name] ?? []
    }

    func searchSymbols(matching query: String) async -> [SymbolSearchResult] {
        symbolSearchResults
    }

    func references(to symbolName: String) async throws -> ReferenceSearchResult {
        referenceResult
    }

    func searchText(_ query: String, mode: TextSearchMode) async throws -> TextSearchResult {
        if let textSearchError {
            throw textSearchError
        }
        return textSearchResult
    }

    func directoryEntries(atRelativePath relativePath: String) async throws -> [DirectoryEntry] {
        directoryEntries[relativePath] ?? []
    }
}

/// Not `final`: one suite subclasses it to add the saving seam W-13 needs.
class FakeEditorSession: EditorSession, @unchecked Sendable {
    private let lock = NSLock()
    private var currentState: EditorSessionState = .notStarted
    private var currentInputMode: InputMode = .vim
    private var stateContinuation: AsyncStream<EditorSessionState>.Continuation?
    private var gridContinuation: AsyncStream<EditorGridSnapshot>.Continuation?
    private var statusContinuation: AsyncStream<EditorStatus>.Continuation?
    private var savedContinuation: AsyncStream<SavedFile>.Continuation?

    private(set) var sentKeys: [String] = []
    private(set) var openedFiles: [(path: String, line: Int?, recordJump: Bool)] = []
    private(set) var resizeRequests: [(columns: Int, rows: Int)] = []
    private(set) var restartCount = 0
    private(set) var mouseEvents: [EditorMouseEvent] = []
    var wordUnderCursorValue: String?
    var startError: Error?

    func start(projectRoot: URL, columns: Int, rows: Int) async throws {
        if let startError {
            emit(.disconnected(reason: "\(startError)"))
            throw startError
        }
        emit(.connecting)
        emit(.connected)
    }


    /// A synchronous critical section. `NSLock.lock()` cannot be called from an async
    /// context, and every accessor here is reached from one.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func restart() async throws {
        locked { restartCount += 1 }
        emit(.connecting)
        emit(.connected)
    }

    func state() async -> EditorSessionState {
        locked { currentState }
    }

    func stateUpdates() async -> AsyncStream<EditorSessionState> {
        AsyncStream { continuation in
            let current = locked { () -> EditorSessionState in
                stateContinuation = continuation
                return currentState
            }
            continuation.yield(current)
        }
    }

    func gridUpdates() async -> AsyncStream<EditorGridSnapshot> {
        AsyncStream { continuation in
            locked { gridContinuation = continuation }
        }
    }

    func statusUpdates() async -> AsyncStream<EditorStatus> {
        AsyncStream { continuation in
            locked { statusContinuation = continuation }
        }
    }

    func savedFiles() async -> AsyncStream<SavedFile> {
        AsyncStream { continuation in
            locked { savedContinuation = continuation }
        }
    }

    func resizeGrid(columns: Int, rows: Int) async throws {
        locked { resizeRequests.append((columns, rows)) }
    }

    func sendKeys(_ keys: String) async throws {
        locked { sentKeys.append(keys) }
    }

    func sendMouse(_ event: EditorMouseEvent) async throws {
        locked { mouseEvents.append(event) }
    }

    func setInputMode(_ mode: InputMode) async throws {
        locked { currentInputMode = mode }
    }

    func inputMode() async -> InputMode {
        locked { currentInputMode }
    }

    func openFile(atRelativePath relativePath: String, line: Int?, recordJump: Bool) async throws {
        locked { openedFiles.append((relativePath, line, recordJump)) }
    }

    private(set) var jumpBackCount = 0
    /// Mode-independent editing commands, in the order the router asked for them. Recorded by
    /// name so a test can assert *which* command ran without depending on key notation — the
    /// point of these methods is that no key notation is involved.
    private(set) var editorCommands: [String] = []

    private func record(_ command: String) {
        lock.lock()
        defer { lock.unlock() }
        editorCommands.append(command)
    }

    func jumpForward() async throws { record("jumpForward") }
    func save() async throws { record("save") }
    func undo() async throws { record("undo") }
    func redo() async throws { record("redo") }
    func copySelection() async throws { record("copySelection") }
    func cutSelection() async throws { record("cutSelection") }
    func paste() async throws { record("paste") }
    func selectAll() async throws { record("selectAll") }

    func jumpBack() async throws {
        locked { jumpBackCount += 1 }
        record("jumpBack")
    }

    func wordUnderCursor() async throws -> String? {
        wordUnderCursorValue
    }

    func shutDown() async {}

    // MARK: Driving the fake

    func emit(_ state: EditorSessionState) {
        let continuation = locked { () -> AsyncStream<EditorSessionState>.Continuation? in
            currentState = state
            return stateContinuation
        }
        continuation?.yield(state)
    }

    func emit(_ snapshot: EditorGridSnapshot) {
        locked { gridContinuation }?.yield(snapshot)
    }

    func emit(_ status: EditorStatus) {
        locked { statusContinuation }?.yield(status)
    }

    func emitSaved(_ file: SavedFile) {
        locked { savedContinuation }?.yield(file)
    }
    // W-13. Overridden by the suite that measures saving; the default is a session with
    // nothing unsaved, which is what most tests want.
    var dirtyFilePaths: [String] = []
    var saveAllOutcome = SaveAllOutcome(savedPaths: [], failures: [])

    func dirtyFiles(inProjectRoot root: URL) async throws -> [String] { dirtyFilePaths }

    func saveAll(inProjectRoot root: URL) async throws -> SaveAllOutcome { saveAllOutcome }

}



/// A workspace that opens projects without an engine behind it.
///
/// Mirrors the engine's own rule for sameness — the canonical root decides, and reopening
/// activates rather than adds (REQ-012 AC-5) — so the application is exercised against the
/// behaviour the contract promises rather than a simplification of it.
final class FakeWorkspace: ProjectWorkspace, @unchecked Sendable {
    private let lock = NSLock()
    private var openTabs: [ProjectTab] = []
    private var active: ProjectTabIdentifier?
    private var sessions: [ProjectTabIdentifier: FakeProjectSession] = [:]

    /// When set, every tab is handed this session.
    ///
    /// Lets a test configure one session and see it through whichever tab is active, which
    /// is what most suites want. Leaving it nil gives each tab its own — the shape the
    /// isolation tests need.
    private let sharedSession: FakeProjectSession?

    init(sharedSession: FakeProjectSession? = nil) {
        self.sharedSession = sharedSession
    }

    /// Roots the fake reports as gone, for the restore path (AC-6).
    var missingRoots: [String] = []
    var missingReason: TabRestoreFailureReason = .notFound

    var openError: (any Error)?
    private(set) var openCallCount = 0
    /// Every root the application asked to open, in order.
    private(set) var openedRoots: [URL] = []
    private(set) var closedTabs: [ProjectTabIdentifier] = []
    /// Every tab the application asked the engine to bring forward.
    private(set) var activatedTabs: [ProjectTabIdentifier] = []
    /// How many times the application asked the engine to restore. Zero on a first run.
    private(set) var restoreCallCount = 0

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func openProject(at rootPath: URL) async throws -> ProjectOpenOutcome {
        if let openError {
            locked { openCallCount += 1 }
            throw openError
        }
        return locked {
            openCallCount += 1
            openedRoots.append(rootPath)
            let canonical = rootPath.resolvingSymlinksInPath().path
            if let existing = openTabs.first(where: { $0.rootPath.resolvingSymlinksInPath().path == canonical }) {
                active = existing.id
                return .activatedExisting(existing)
            }
            let tab = ProjectTab(
                id: ProjectTabIdentifier(),
                displayName: rootPath.lastPathComponent,
                rootPath: rootPath,
                disambiguator: nil
            )
            openTabs.append(tab)
            sessions[tab.id] = FakeProjectSession()
            active = tab.id
            return .opened(tab)
        }
    }

    func tabs() async -> [ProjectTab] { locked { openTabs } }

    func activeTab() async -> ProjectTab? {
        locked { openTabs.first { $0.id == active } }
    }

    func activate(_ identifier: ProjectTabIdentifier) async throws {
        locked {
            activatedTabs.append(identifier)
            guard openTabs.contains(where: { $0.id == identifier }) else { return }
            active = identifier
        }
    }

    func closeTab(_ identifier: ProjectTabIdentifier) async throws {
        locked {
            closedTabs.append(identifier)
            openTabs.removeAll { $0.id == identifier }
            sessions[identifier] = nil
            if active == identifier {
                active = openTabs.last?.id
            }
        }
    }

    func reorderTabs(_ order: [ProjectTabIdentifier]) async {
        locked {
            openTabs = order.compactMap { id in openTabs.first { $0.id == id } }
        }
    }

    func session(for identifier: ProjectTabIdentifier) async -> (any ProjectSession)? {
        if let sharedSession { return sharedSession }
        return locked { sessions[identifier] }
    }

    func restoreTabs(from rootPaths: [URL], activeRootPath: URL?) async -> TabRestoreOutcome {
        locked { restoreCallCount += 1 }
        var restored: [ProjectTab] = []
        var missing: [MissingTab] = []
        for path in rootPaths {
            guard !missingRoots.contains(path.path) else {
                missing.append(MissingTab(
                    displayName: path.lastPathComponent,
                    rootPath: path,
                    reason: missingReason
                ))
                continue
            }
            if let outcome = try? await openProject(at: path) {
                restored.append(outcome.tab)
            }
        }
        if let activeRootPath,
           let match = restored.first(where: { $0.rootPath.path == activeRootPath.path }) {
            try? await activate(match.id)
        }
        return TabRestoreOutcome(restored: restored, missing: missing)
    }
}
