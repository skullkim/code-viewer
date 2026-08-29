/// One fuzzy-search hit: the definition, its relevance score, and where the query matched its name.
public struct SymbolSearchResult: Sendable, Hashable, Identifiable {
    public let definition: SymbolDefinition
    public let score: Int
    public let matchRanges: [MatchRange]

    public var id: String { definition.id }

    public init(definition: SymbolDefinition, score: Int, matchRanges: [MatchRange]) {
        self.definition = definition
        self.score = score
        self.matchRanges = matchRanges
    }
}
