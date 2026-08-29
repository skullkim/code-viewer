import CodeNavigatorContract

/// Which way a keyboard selection moves.
public enum SelectionDirection: Sendable, Hashable {
    case up
    case down
}

/// Everything the symbol search modal draws (design §3 W-3).
///
/// REQ-007 AC-3 requires the modal to be usable with the keyboard alone, so the selection
/// arithmetic — wrapping, clamping when the list shrinks under the cursor — is part of the
/// acceptance criteria rather than an implementation detail of a view.
public struct SymbolSearchPresentation: Sendable {
    public let results: [SymbolSearchResult]
    public let selectedIndex: Int
    public let hintText: String?
    public let emptyText: String?
    public let partialResultsNotice: String?
    public let showsSpinner: Bool

    public var selectedResult: SymbolSearchResult? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }
}

extension SymbolSearchPresentation {

    /// Design §3 W-3: at most fifty rows.
    public static let maximumResults = 50

    static let queryHint = "심볼 이름의 일부나 약어를 입력하세요"
    static let noResults = "결과 없음 — 다른 이름으로 검색해 보세요"

    public static func make(
        query: String,
        results: [SymbolSearchResult],
        indexState: IndexState,
        selectedIndex: Int,
        isLoading: Bool
    ) -> SymbolSearchPresentation {
        let visible = Array(results.prefix(maximumResults))
        let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return SymbolSearchPresentation(
            results: visible,
            // Typing narrows the list under a selection that pointed further down; an
            // unclamped index would read out of bounds the moment Enter is pressed.
            selectedIndex: visible.isEmpty ? 0 : min(max(0, selectedIndex), visible.count - 1),
            hintText: hasQuery ? nil : queryHint,
            emptyText: hasQuery && visible.isEmpty ? noResults : nil,
            // Without this, "no results" reads as "this symbol does not exist" when the
            // truth may be "it has not been indexed yet".
            partialResultsNotice: partialNotice(for: indexState),
            showsSpinner: isLoading
        )
    }

    /// The next selected row, wrapping at both ends.
    public static func nextIndex(from current: Int, resultCount: Int, direction: SelectionDirection) -> Int {
        guard resultCount > 0 else {
            return 0
        }
        let step = direction == .down ? 1 : -1
        return ((current + step) % resultCount + resultCount) % resultCount
    }

    private static func partialNotice(for indexState: IndexState) -> String? {
        guard indexState.isWorking else {
            return nil
        }
        guard let progress = indexState.progress else {
            return "인덱싱 중 — 결과가 아직 부분적일 수 있습니다"
        }
        return "인덱싱 중 — 결과가 아직 부분적일 수 있습니다 (\(progress.completed)/\(progress.total))"
    }
}
