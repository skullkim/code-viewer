import CodeNavigatorContract

/// What the reference panel is doing right now.
public enum ReferencePhase: Sendable {
    case idle
    case searching
    case results(ReferenceSearchResult)
    case failed(NavigatorError)
}

/// Everything the reference panel draws (design §3 W-5).
///
/// Reference search has no type resolution, so results can include same-named symbols from
/// unrelated types. REQ-006 AC-3 requires that caveat to be visible at all times — most
/// of all on the empty state, where a bare "no references" would sound like a certainty
/// the search cannot offer.
public struct ReferencePresentation: Sendable {
    public let headerText: String?
    public let approximationNotice: String?
    public let partialResultsNotice: String?
    public let groups: [FileGroup<Reference>]
    public let placeholderText: String?
    public let emptyText: String?
    public let limitWarningText: String?
    public let errorText: String?
    public let isLoading: Bool
}

extension ReferencePresentation {

    /// Shown in every phase (REQ-006 AC-3).
    static let approximationNoticeText = "이름 기반 검색 — 동명 이의어 포함 가능"
    static let partialResultsNoticeText = "인덱싱 중 — 결과가 아직 부분적일 수 있습니다"
    static let placeholder = "심볼에 커서를 두고 ⇧⌘B를 누르면 참조 목록이 여기에 표시됩니다"

    public static func make(
        symbolName: String?,
        phase: ReferencePhase,
        indexState: IndexState
    ) -> ReferencePresentation {
        // Queries are answered from the previous index while a rebuild runs (INV-1), so
        // the panel says the results may be a moment behind rather than hiding it.
        let partialNotice = indexState.isWorking ? partialResultsNoticeText : nil

        switch phase {
        case .idle:
            return ReferencePresentation(
                headerText: nil,
                approximationNotice: approximationNoticeText,
                partialResultsNotice: partialNotice,
                groups: [],
                placeholderText: placeholder,
                emptyText: nil,
                limitWarningText: nil,
                errorText: nil,
                isLoading: false
            )

        case .searching:
            return ReferencePresentation(
                headerText: symbolName,
                approximationNotice: approximationNoticeText,
                partialResultsNotice: partialNotice,
                groups: [],
                placeholderText: nil,
                emptyText: nil,
                limitWarningText: nil,
                errorText: nil,
                isLoading: true
            )

        case .results(let result):
            let isEmpty = result.references.isEmpty
            let name = symbolName ?? ""
            return ReferencePresentation(
                headerText: isEmpty ? name : header(name: name, references: result.references),
                approximationNotice: approximationNoticeText,
                partialResultsNotice: partialNotice,
                groups: FileGrouping.group(result.references, by: \.path),
                placeholderText: nil,
                emptyText: isEmpty ? "'\(name)' 참조 없음" : nil,
                limitWarningText: result.truncated ? "상위 \(result.limit)건만 표시합니다 — 검색어를 더 구체적으로 좁혀 주세요" : nil,
                errorText: nil,
                isLoading: false
            )

        case .failed(let error):
            return ReferencePresentation(
                headerText: symbolName,
                approximationNotice: approximationNoticeText,
                partialResultsNotice: partialNotice,
                groups: [],
                placeholderText: nil,
                emptyText: nil,
                limitWarningText: nil,
                errorText: "⚠ " + (error.errorDescription ?? "참조 검색에 실패했습니다"),
                isLoading: false
            )
        }
    }

    private static func header(name: String, references: [Reference]) -> String {
        let definitionCount = references.filter(\.isDefinition).count
        return "\(name) · \(references.count)건 (정의 \(definitionCount))"
    }
}
