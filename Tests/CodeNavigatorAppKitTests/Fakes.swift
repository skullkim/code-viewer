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

final class FakeEditorSession: EditorSession, @unchecked Sendable {
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
}


/// Records what the application asked the workspace to open.
///
/// Lives here rather than in one suite's file because several suites build an `AppModel`
/// and therefore need it — the visual regression gate among them. While it sat inside
/// `AppModelCommandTests`, an edit to that one file could stop someone else's gate from
/// compiling, which is a coupling nobody chose (frontend-junior raised it after it happened).
/// Records what the shell asked the engine to open, so opening a project can be checked
/// without an engine. The two contract protocols each own half of that operation and
/// neither expresses that the halves move together.
final class RecordingWorkspace: SingleProjectWorkspace, @unchecked Sendable {
    private let lock = NSLock()
    private var opened: [(root: URL, columns: Int, rows: Int)] = []
    var openError: (any Error)?

    /// A synchronous critical section. `NSLock.lock()` cannot be called from an async
    /// context, and `openWorkspace` is reached from one.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var openedRoots: [URL] {
        locked { opened.map(\.root) }
    }

    var lastGridSize: (columns: Int, rows: Int)? {
        locked { opened.last.map { ($0.columns, $0.rows) } }
    }

    func openWorkspace(at projectRoot: URL, columns: Int, rows: Int) async throws {
        if let openError {
            throw openError
        }
        locked { opened.append((projectRoot, columns, rows)) }
    }
}
