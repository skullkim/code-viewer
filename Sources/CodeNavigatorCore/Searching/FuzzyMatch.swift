import CodeNavigatorContract

/// One fuzzy-match hit against a symbol name (REQ-007 AC-1).
///
/// The score is only meaningful *relative to other candidates for the same query*; it ranks
/// results and carries no absolute meaning.
public struct FuzzyMatch: Sendable, Hashable {
    public let score: Int

    /// Where the query matched inside the candidate, for highlighting.
    /// UTF-16 code units, half-open, with consecutive characters merged into one range.
    public let matchRanges: [MatchRange]

    public init(score: Int, matchRanges: [MatchRange]) {
        self.score = score
        self.matchRanges = matchRanges
    }
}
