import Foundation

/// The engine's project-side surface: open a project, then query its index.
///
/// This is the machine contract between the engine and the application. Implementations
/// serialise their own state; every method is safe to call from any task. Queries are answered
/// in every index state — during a rebuild the previous index answers, and `indexState`
/// tells the UI that an update is in flight.
///
/// Nothing here writes to the repository. File modification happens only through
/// `EditorSession`, which delegates it to Neovim (INV-3).
public protocol ProjectSession: Sendable {
    /// Opens a project root and starts indexing. Throws if the path is missing or unreadable,
    /// leaving any previously opened project untouched (REQ-001 AC-3).
    func openProject(at rootPath: URL) async throws

    func currentProject() async -> ProjectDescriptor?

    func indexState() async -> IndexState

    /// Index-state transitions, for progress display. The stream yields the current state
    /// immediately on subscription, so a late subscriber is never left blank.
    func indexStateUpdates() async -> AsyncStream<IndexState>

    /// Definition sites for an exact symbol name, sorted by path then line (REQ-005).
    func definitions(named name: String) async -> [SymbolDefinition]

    /// Fuzzy symbol search, most relevant first, capped (REQ-007).
    func searchSymbols(matching query: String) async -> [SymbolSearchResult]

    /// Usage sites of a symbol name, definitions included and flagged (REQ-006).
    func references(to symbolName: String) async throws -> ReferenceSearchResult

    /// Full-text search across the project (REQ-008).
    func searchText(_ query: String, mode: TextSearchMode) async throws -> TextSearchResult

    /// One level of the file tree. Pass `""` for the project root (REQ-003).
    func directoryEntries(atRelativePath relativePath: String) async throws -> [DirectoryEntry]
}
