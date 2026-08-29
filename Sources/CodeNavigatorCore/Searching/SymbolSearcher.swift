import CodeNavigatorContract

/// Ranks symbols against a fuzzy query (REQ-007).
///
/// `FuzzyMatcher` scores one name against one query; ordering across candidates lives here, so
/// the scorer stays a pure function and the ranking policy stays in one place.
struct SymbolSearcher {
    /// The list is keyboard-driven and scanned by eye, so it is capped at what a person will
    /// actually read rather than at what the index can produce.
    static let resultLimit = 50

    func search(query: String, in definitions: [SymbolDefinition]) -> [SymbolSearchResult] {
        guard !query.isEmpty else { return [] }

        var results: [SymbolSearchResult] = []
        for definition in definitions {
            guard let match = FuzzyMatcher.match(query: query, candidate: definition.name) else {
                continue
            }
            results.append(
                SymbolSearchResult(
                    definition: definition,
                    score: match.score,
                    matchRanges: match.matchRanges
                )
            )
        }

        results.sort(by: Self.byRelevance)
        return Array(results.prefix(Self.resultLimit))
    }

    /// Best score first. Ties break towards the shorter name, because when two names score the
    /// same the shorter one is the closer fit to what was typed; the remaining keys only exist so
    /// the order is stable rather than dependent on index iteration.
    private static func byRelevance(_ left: SymbolSearchResult, _ right: SymbolSearchResult) -> Bool {
        if left.score != right.score {
            return left.score > right.score
        }
        if left.definition.name.count != right.definition.name.count {
            return left.definition.name.count < right.definition.name.count
        }
        if left.definition.path != right.definition.path {
            return left.definition.path < right.definition.path
        }
        return left.definition.line < right.definition.line
    }
}
