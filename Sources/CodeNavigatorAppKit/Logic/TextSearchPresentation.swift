import Foundation
import CodeNavigatorContract

/// What the full-text panel is doing right now.
public enum TextSearchPhase: Sendable {
    case idle
    case searching
    case results(TextSearchResult)
    case failed(NavigatorError)
}

/// Everything the full-text search panel draws (design §3 W-6).
///
/// The rule this type exists to keep is SC-6: an invalid regular expression is an error,
/// never an empty result set. Those two look identical if the panel simply clears itself,
/// and the user reads "no matches" when the truth is "no search ran". So the previous
/// results stay, dimmed, with a notice saying they are stale.
public struct TextSearchPresentation: Sendable {
    public let items: [TextSearchItem]
    public let groups: [FileGroup<TextSearchItem>]
    public let isLoading: Bool
    public let resultsAreDimmed: Bool
    public let staleResultNotice: String?
    public let metaText: String?
    public let emptyText: String?
    public let limitWarningText: String?
    public let errorText: String?
}

extension TextSearchPresentation {

    static let emptyMessage = "결과 없음"
    static let staleNotice = "이전 결과 유지 (새 검색 미실행)"

    /// `filesSearched` is not a parameter: the count belongs to the result, because only
    /// the search knows where it stopped. Passing it alongside would let a caller state a
    /// number the search never reported.
    public static func make(
        phase: TextSearchPhase,
        previousResult: TextSearchResult?,
        elapsedSeconds: Double?
    ) -> TextSearchPresentation {
        switch phase {
        case .idle:
            return presentation(items: [])

        case .searching:
            // The previous results stay readable. Dimming here would be indistinguishable
            // from the dimming that signals a failed search.
            return presentation(items: previousResult?.items ?? [], isLoading: true)

        case .results(let result):
            return presentation(
                items: result.items,
                metaText: meta(result: result, elapsedSeconds: elapsedSeconds),
                emptyText: result.items.isEmpty ? emptyMessage : nil,
                limitWarningText: result.truncated ? limitWarning(limit: result.limit) : nil
            )

        case .failed(let error):
            let survivingItems = previousResult?.items ?? []
            return presentation(
                items: survivingItems,
                resultsAreDimmed: !survivingItems.isEmpty,
                // Saying results are being kept when there are none would be noise.
                staleResultNotice: survivingItems.isEmpty ? nil : staleNotice,
                // Deliberately no empty message: the result set is unknown, not empty.
                errorText: message(for: error)
            )
        }
    }

    private static func presentation(
        items: [TextSearchItem],
        isLoading: Bool = false,
        resultsAreDimmed: Bool = false,
        staleResultNotice: String? = nil,
        metaText: String? = nil,
        emptyText: String? = nil,
        limitWarningText: String? = nil,
        errorText: String? = nil
    ) -> TextSearchPresentation {
        TextSearchPresentation(
            items: items,
            groups: FileGrouping.group(items, by: \.path),
            isLoading: isLoading,
            resultsAreDimmed: resultsAreDimmed,
            staleResultNotice: staleResultNotice,
            metaText: metaText,
            emptyText: emptyText,
            limitWarningText: limitWarningText,
            errorText: errorText
        )
    }

    /// The panel's wording for a failure.
    ///
    /// `NavigatorError` spells out the offending pattern, which is right for a log and
    /// wrong here: the pattern is already visible in the input field directly above, and
    /// repeating it in a narrow panel crowds out the part the user does not know — why it
    /// is invalid. Design §2 F-6 asks for the cause alone.
    private static func message(for error: NavigatorError) -> String {
        if case .invalidRegularExpression(_, let reason) = error {
            return "⚠ 잘못된 정규식: \(reason)"
        }
        return "⚠ " + (error.errorDescription ?? "검색에 실패했습니다")
    }

    private static func limitWarning(limit: Int) -> String {
        "상위 \(limit)건만 표시합니다 — 검색어를 더 구체적으로 좁혀 주세요"
    }

    private static func meta(result: TextSearchResult, elapsedSeconds: Double?) -> String {
        let duration = String(format: "%.2f초", elapsedSeconds ?? 0)
        return "\(result.items.count)건 표시 · \(grouped(result.filesSearched)) 파일 검색 · \(duration)"
    }

    /// 자릿수 구분은 한 곳에서만 정한다.
    ///
    /// `NumberFormatter` 사본이었다. `groupingSeparator` 를 "," 로 못박아도 **묶음 크기**는
    /// 로케일이 정하므로(hi_IN 은 12,00,000 으로 끊는다) 같은 수가 화면 위치마다 달라졌다.
    private static func grouped(_ value: Int) -> String {
        GroupedNumberText.string(value)
    }
}
