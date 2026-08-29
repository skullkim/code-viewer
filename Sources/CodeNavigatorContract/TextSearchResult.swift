/// Full-text search results, with the same explicit-cap semantics as `ReferenceSearchResult`.
public struct TextSearchResult: Sendable, Hashable {
    public let items: [TextSearchItem]
    public let total: Int
    public let truncated: Bool
    public let limit: Int
    /// How many files were actually read before the search finished or hit its cap.
    ///
    /// Reported rather than left to the caller because only the search knows where it stopped:
    /// on a truncated search this is smaller than the project's file count, and a caller that
    /// showed the project total instead would be stating something that did not happen.
    public let filesSearched: Int

    /// `filesSearched` defaults to zero so a test fake that does not care about search scope
    /// stays compiling. The engine always reports the real count; a fake that searched nothing
    /// truthfully searched no files.
    public init(
        items: [TextSearchItem],
        total: Int,
        truncated: Bool,
        limit: Int,
        filesSearched: Int = 0
    ) {
        self.items = items
        self.total = total
        self.truncated = truncated
        self.limit = limit
        self.filesSearched = filesSearched
    }
}
