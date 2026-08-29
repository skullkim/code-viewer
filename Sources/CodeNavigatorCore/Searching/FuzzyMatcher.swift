import CodeNavigatorContract

/// Order-preserving fuzzy matching of a query against a symbol name (REQ-007 AC-1).
///
/// Every query character must appear in the candidate, in order — otherwise there is no match.
/// The score is built so that an exact match outranks a prefix/boundary match, which in turn
/// outranks a scattered match:
///
///     query "sym"   candidate "sym"           exact      → 20
///                             "SymbolIndex"   prefix     → 10
///                             "SystemMemory"  scattered  →  5
public enum FuzzyMatcher {

    // Score weights. Tuned together — changing one alone reorders results.
    private static let scorePerMatchedCharacter = 1
    private static let bonusForNameStart = 3
    private static let bonusForBoundary = 2
    private static let bonusForConsecutiveMatch = 2
    private static let bonusForExactMatch = 10
    private static let penaltyPerSkippedCharacter = 1
    private static let maximumGapPenalty = 3

    /// Characters that start a new word in identifiers, so the character after one is a boundary.
    private static let separatorCharacters: Set<Character> = ["_", "-", ".", "/", "$"]

    public static func match(query: String, candidate: String) -> FuzzyMatch? {
        let queryCharacters = lowercasedCharacters(of: query)
        guard !queryCharacters.isEmpty else {
            return nil
        }

        let candidateCharacters = Array(candidate)
        let candidateLowercased = lowercasedCharacters(of: candidate)
        guard
            let matchedIndexes = leftmostSubsequenceIndexes(
                of: queryCharacters,
                in: candidateLowercased
            )
        else {
            return nil
        }

        var score = 0
        for (matchOrder, characterIndex) in matchedIndexes.enumerated() {
            score += scorePerMatchedCharacter

            // Position bonuses are exclusive — starting the name beats merely being on a boundary.
            if characterIndex == 0 {
                score += bonusForNameStart
            } else if isBoundary(in: candidateCharacters, at: characterIndex) {
                score += bonusForBoundary
            }

            guard matchOrder > 0 else {
                continue
            }

            // Reward adjacency, penalise skipped characters, so a scattered match cannot tie
            // with a consecutive one. The penalty is capped so long names stay reachable.
            let gapSize = characterIndex - matchedIndexes[matchOrder - 1] - 1
            if gapSize == 0 {
                score += bonusForConsecutiveMatch
            } else {
                score -= min(gapSize * penaltyPerSkippedCharacter, maximumGapPenalty)
            }
        }

        if queryCharacters == candidateLowercased {
            score += bonusForExactMatch
        }

        return FuzzyMatch(
            score: score,
            matchRanges: mergedRanges(of: matchedIndexes, in: candidateCharacters)
        )
    }

    /// Greedy leftmost subsequence match, no backtracking: each query character is looked up
    /// from just after the previous hit. Returns nil as soon as one character is missing.
    private static func leftmostSubsequenceIndexes(
        of query: [Character],
        in candidate: [Character]
    ) -> [Int]? {
        var matchedIndexes: [Int] = []
        matchedIndexes.reserveCapacity(query.count)

        var searchStart = 0
        for queryCharacter in query {
            guard let foundIndex = candidate[searchStart...].firstIndex(of: queryCharacter) else {
                return nil
            }
            matchedIndexes.append(foundIndex)
            searchStart = foundIndex + 1
        }
        return matchedIndexes
    }

    /// Boundaries are judged on the **original** casing — lowercasing first would erase the
    /// camel-case boundary that makes "SymIdx" rank above a scattered match.
    private static func isBoundary(in characters: [Character], at index: Int) -> Bool {
        let previousCharacter = characters[index - 1]
        if separatorCharacters.contains(previousCharacter) {
            return true
        }
        return previousCharacter.isLowercase && characters[index].isUppercase
    }

    /// Merges consecutive matched indexes into single half-open ranges, in UTF-16 code units
    /// (the contract's offset unit, §3.1 MatchRange).
    private static func mergedRanges(
        of matchedIndexes: [Int],
        in characters: [Character]
    ) -> [MatchRange] {
        let utf16Offsets = utf16OffsetsByCharacterIndex(of: characters)

        var ranges: [MatchRange] = []
        var runStart = matchedIndexes[0]
        var runEnd = matchedIndexes[0] + 1

        for characterIndex in matchedIndexes.dropFirst() {
            if characterIndex == runEnd {
                runEnd += 1
                continue
            }
            ranges.append(MatchRange(start: utf16Offsets[runStart], end: utf16Offsets[runEnd]))
            runStart = characterIndex
            runEnd = characterIndex + 1
        }
        ranges.append(MatchRange(start: utf16Offsets[runStart], end: utf16Offsets[runEnd]))

        return ranges
    }

    /// Character index → the UTF-16 offset that character starts at. The last element is the
    /// total UTF-16 length, so a half-open range can end at it.
    private static func utf16OffsetsByCharacterIndex(of characters: [Character]) -> [Int] {
        var offsets: [Int] = [0]
        offsets.reserveCapacity(characters.count + 1)

        var offset = 0
        for character in characters {
            offset += character.utf16.count
            offsets.append(offset)
        }
        return offsets
    }

    /// Lowercases character by character. Lowercasing can expand one character into several
    /// (for example "İ"); keeping one character per index is what lets the match indexes point
    /// back into the original name.
    private static func lowercasedCharacters(of text: String) -> [Character] {
        text.map { character in character.lowercased().first ?? character }
    }
}
