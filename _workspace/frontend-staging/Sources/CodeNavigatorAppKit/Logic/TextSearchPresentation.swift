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

    public static func make(
        phase: TextSearchPhase,
        previousResult: TextSearchResult?,
        elapsedSeconds: Double?,
        filesSearched: Int?
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
                metaText: meta(count: result.items.count, items: result.items, elapsedSeconds: elapsedSeconds, filesSearched: filesSearched),
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

    private static func meta(
        count: Int,
        items: [TextSearchItem],
        elapsedSeconds: Double?,
        filesSearched: Int?
    ) -> String {
        let duration = String(format: "%.2f초", elapsedSeconds ?? 0)
        guard let filesSearched else {
            // The engine does not report how many files it looked at, so the panel reports
            // what it can actually see rather than inventing a number.
            let matchedFiles = Set(items.map(\.path)).count
            return "\(count)건 표시 · \(matchedFiles)개 파일에서 일치 · \(duration)"
        }
        return "\(count)건 표시 · \(grouped(filesSearched)) 파일 검색 · \(duration)"
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
