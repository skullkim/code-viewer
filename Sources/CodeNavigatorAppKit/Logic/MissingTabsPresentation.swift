import Foundation
import CodeNavigatorContract

/// The sheet shown when saved tabs could not be reopened (02b W-12, REQ-012 AC-6).
///
/// AC-6 asks that a project which did not come back is reported rather than dropped.
/// Dropping it silently is indistinguishable from the application forgetting: the user
/// cannot tell whether their folder moved or something went wrong here, and those need
/// different responses from them.
public struct MissingTabsPresentation: Sendable, Hashable {

    public struct Row: Sendable, Hashable, Identifiable {
        public let id: String
        public let text: String
    }

    public let title: String
    public let body: String
    public let rows: [Row]
    public let confirmLabel: String
}

extension MissingTabsPresentation {

    /// Builds the sheet, or nothing when every tab came back.
    ///
    /// One sheet for all of them, never one each: five sheets teach the user to hit 확인
    /// five times without reading, and then the sixth — the one that mattered — goes unread
    /// too (02b W-12).
    public static func make(missing: [MissingTab]) -> MissingTabsPresentation? {
        guard !missing.isEmpty else {
            return nil
        }
        return MissingTabsPresentation(
            title: "일부 프로젝트를 복원하지 못했습니다",
            // The count is stated even for one, so the sentence does not fork into a
            // singular variant that then drifts from the plural one.
            body: "다음 \(missing.count)개 프로젝트는 열 수 없어 탭 목록에서 제거했습니다.",
            rows: missing.map { Row(id: $0.rootPath.path, text: description(of: $0)) },
            // One button, because nothing here is a choice: the tabs are already gone from
            // the list and no action of the user's can bring them back from this sheet.
            confirmLabel: "확인"
        )
    }

    /// Says which kind of failure this was, in the words W-2 already uses for the same two
    /// cases — the user should not have to learn a second vocabulary for one situation.
    private static func description(of tab: MissingTab) -> String {
        switch tab.reason {
        case .notFound:
            return "\(tab.displayName) — 경로를 찾을 수 없습니다: \(tab.rootPath.path)"
        case .noPermission:
            return "\(tab.displayName) — 폴더에 접근할 권한이 없습니다: \(tab.rootPath.path)"
        }
    }
}
