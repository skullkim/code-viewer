/// Full-text search results, with the same explicit-cap semantics as `ReferenceSearchResult`.
public struct TextSearchResult: Sendable, Hashable {
    public let items: [TextSearchItem]
    public let total: Int
    public let truncated: Bool
    public let limit: Int

    public init(items: [TextSearchItem], total: Int, truncated: Bool, limit: Int) {
        self.items = items
        self.total = total
        self.truncated = truncated
        self.limit = limit
    }
}
