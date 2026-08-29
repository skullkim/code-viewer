/// Reference-search results, with an explicit cap so the UI can say "showing the first N".
///
/// When `truncated` is true the search stopped early on purpose; `total` is then the number of
/// matches *observed before stopping*, not a repository-wide count.
public struct ReferenceSearchResult: Sendable, Hashable {
    public let references: [Reference]
    public let total: Int
    public let truncated: Bool
    public let limit: Int

    public init(references: [Reference], total: Int, truncated: Bool, limit: Int) {
        self.references = references
        self.total = total
        self.truncated = truncated
        self.limit = limit
    }
}
