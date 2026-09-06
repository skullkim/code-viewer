/// Reference-search results, with an explicit cap so the UI can say "showing the first N".
///
/// When `truncated` is true the search stopped early on purpose; `total` is then the number of
/// matches *observed before stopping*, not a repository-wide count.
public struct ReferenceSearchResult: Sendable, Hashable {
    public let references: [Reference]
    public let total: Int
    public let truncated: Bool
    public let limit: Int
    /// How the list was narrowed, for the panel to say so. `nil` when nothing was narrowed.
    public let narrowing: ReferenceNarrowing?

    public init(
        references: [Reference],
        total: Int,
        truncated: Bool,
        limit: Int,
        narrowing: ReferenceNarrowing? = nil
    ) {
        self.references = references
        self.total = total
        self.truncated = truncated
        self.limit = limit
        self.narrowing = narrowing
    }
}

/// What a type-narrowed reference search did, so the panel can report it instead of claiming a
/// precision it does not have.
///
/// The counts are separate on purpose. `discarded` is what we are confident is a different symbol;
/// `unresolved` is what we could not judge and therefore kept. Merging them into one number would
/// let the panel say "정확한 참조" over results that include lines nobody resolved.
public struct ReferenceNarrowing: Sendable, Hashable {
    /// The receiver type the cursor was on, e.g. `Member`.
    public let receiverType: String
    /// Hits dropped because their receiver resolved to a different type.
    public let discarded: Int
    /// Hits kept although their receiver could not be resolved.
    public let unresolved: Int

    public init(receiverType: String, discarded: Int, unresolved: Int) {
        self.receiverType = receiverType
        self.discarded = discarded
        self.unresolved = unresolved
    }
}
