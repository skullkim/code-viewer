import Foundation
import CodeNavigatorContract

/// One labelled figure in the index details popover.
public struct IndexDetailRow: Sendable, Hashable, Identifiable {
    public let label: String
    public let value: String
    /// Drawn in the warning tone. Only the skip count ever sets it, and only when files
    /// were actually skipped.
    public let isWarning: Bool

    public var id: String { label }
}

/// The popover behind the index chip (design §3 W-10, REQ-009 · REQ-002 AC-4).
///
/// This is the **only** place a user can see that files were left out of the index.
/// REQ-002 AC-4 has the indexer skip a file it cannot parse rather than stopping the run,
/// which is right — but "silently" must not become "invisibly", or the index quietly
/// under-reports and a missing symbol has no explanation.
public struct IndexDetailsPresentation: Sendable, Hashable {
    public let title: String
    public let rows: [IndexDetailRow]
    /// Why files were skipped, shown only when some were.
    public let skippedNotice: String?
    /// Shown in every state but `ready`, so a stale answer is never presented as current.
    public let staleNotice: String?
    public let progress: IndexProgress?
}

extension IndexDetailsPresentation {

    static let neverUpdatedText = "아직 없음"
    static let skippedNoticeText = "파싱 실패 — 로그에 기록됨"
    static let staleNoticeText = "직전 인덱스로 응답 중 — 결과가 잠시 이전 상태일 수 있습니다"

    static let lastUpdatedLabel = "마지막 갱신"
    static let fileLabel = "파일"
    static let symbolLabel = "심볼"
    static let skippedLabel = "스킵"

    public static func make(
        indexState: IndexState,
        statistics: IndexStatistics?,
        now: Date,
        calendar: Calendar
    ) -> IndexDetailsPresentation {
        IndexDetailsPresentation(
            title: title(for: indexState),
            rows: rows(statistics: statistics, now: now, calendar: calendar),
            // Nothing to explain when nothing was skipped, and a notice with no subject
            // trains people to ignore the place the real one will appear.
            skippedNotice: (statistics?.skippedCount ?? 0) > 0 ? skippedNoticeText : nil,
            staleNotice: indexState == .ready ? nil : staleNoticeText,
            progress: indexState.progress
        )
    }

    /// The same words the chip carries, so the popover cannot disagree with the thing that
    /// opened it (design §3 W-10 lists one label per state).
    private static func title(for state: IndexState) -> String {
        switch state {
        case .notIndexed:
            return "인덱스 없음"
        case .indexing(let progress):
            return "인덱싱 중 \(grouped(progress.completed))/\(grouped(progress.total))"
        case .ready:
            return "인덱스 최신"
        case .updating:
            return "갱신 중"
        case .rescanning(let progress):
            return "전체 재스캔 중 \(grouped(progress.completed))/\(grouped(progress.total))"
        }
    }

    private static func rows(
        statistics: IndexStatistics?,
        now: Date,
        calendar: Calendar
    ) -> [IndexDetailRow] {
        guard let statistics else {
            // The engine has not answered yet. Zeros would be a claim about the index;
            // this says only that nothing is known.
            return [IndexDetailRow(label: lastUpdatedLabel, value: neverUpdatedText, isWarning: false)]
        }

        let skipped = statistics.skippedCount
        return [
            IndexDetailRow(
                label: lastUpdatedLabel,
                value: statistics.lastUpdatedAt.map {
                    RelativeTimeText.string(for: $0, now: now, calendar: calendar)
                } ?? neverUpdatedText,
                isWarning: false
            ),
            IndexDetailRow(label: fileLabel, value: "\(grouped(statistics.fileCount))개", isWarning: false),
            IndexDetailRow(label: symbolLabel, value: "\(grouped(statistics.symbolCount))개", isWarning: false),
            // Always present, even at zero: REQ-002 AC-4 is about the number being
            // findable, and a row that appears only on failure cannot be checked when a
            // user wonders whether anything was missed.
            IndexDetailRow(label: skippedLabel, value: "\(grouped(skipped))건", isWarning: skipped > 0),
        ]
    }

    /// Thousands separators, as design §7 writes the figures ("1,284/4,812").
    static func grouped(_ value: Int) -> String {
        GroupedNumberText.string(value)
    }
}
