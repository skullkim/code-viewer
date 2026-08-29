import Foundation
import CodeNavigatorContract

/// One row of the recent-project list (design §3 W-2).
public struct RecentProjectRow: Sendable, Hashable, Identifiable {
    public let name: String
    /// The path as shown, with the home directory abbreviated to `~`.
    public let displayPath: String
    /// "오늘 09:12" · "어제" · "8월 26일".
    public let relativeTime: String
    /// The path to open. Kept unabbreviated: `displayPath` is for reading, not for opening.
    public let rootPath: String

    public var id: String { rootPath }
}

/// The sheet shown when a project fails to open (REQ-001 AC-3).
public struct ProjectOpenFailureSheet: Sendable, Hashable {
    public let title: String
    public let detail: String
    public let confirmTitle: String
    /// The recent entry to drop, when the failure proved the path is gone. Nil leaves the
    /// list untouched.
    public let forgetRecentProjectPath: String?
}

/// What the open flow is doing (design §3 W-2).
public enum ProjectOpenPhase: Sendable, Equatable {
    case idle
    case opening
    case failed(NavigatorError)
}

/// Everything the welcome screen draws (design §3 W-2, REQ-001).
///
/// The failure wording is the part that carries a requirement rather than a style. REQ-001
/// AC-3 asks for a clear error *and* for the previous state to survive it, so the sheet is
/// derived beside the recent list rather than replacing it, and a missing folder and an
/// unreadable one get different sentences — 03 §3 forbids masking one as the other.
public struct ProjectOpenPresentation: Sendable {
    public let appMark: String
    public let title: String
    public let detailText: String
    public let openButtonTitle: String
    public let openButtonShortcut: String
    public let isOpenButtonEnabled: Bool
    /// Nil hides the whole recent block, which is what design §3 W-2 asks for at zero
    /// entries — an empty bordered box would read as a list that failed to load.
    public let recentSectionTitle: String?
    public let recentProjects: [RecentProjectRow]
    public let exclusionNotice: String
    public let failureSheet: ProjectOpenFailureSheet?
}

extension ProjectOpenPresentation {

    static let appMarkText = "CN"
    static let titleText = "프로젝트를 여세요"
    static let detailMessage = "로컬 레포 폴더를 열면 트리가 표시되고 인덱싱이 시작됩니다."
    static let openButtonText = "프로젝트 열기…"
    static let openShortcut = "⌘O"
    static let recentTitle = "최근 프로젝트"
    static let confirmText = "확인"

    /// REQ-001 AC-4's only surface. The list matches `ScanExclusions` in the engine; it is
    /// spelled out rather than summarised because "기본 제외 목록" alone tells the user
    /// nothing about why their file is missing.
    static let exclusionNoticeText =
        "인덱싱은 .gitignore와 기본 제외 목록(node_modules · build · dist · .git · target)을 존중합니다"

    static let failureTitle = "프로젝트를 열 수 없습니다"
    static let genericFailureDetail = "프로젝트를 여는 데 실패했습니다"

    /// Design §3 W-2: at most five entries.
    static let maximumRecentProjects = 5

    public static func make(
        recentProjects: [RecentProject],
        phase: ProjectOpenPhase,
        now: Date,
        calendar: Calendar,
        homeDirectory: String
    ) -> ProjectOpenPresentation {
        let rows = recentRows(
            recentProjects,
            now: now,
            calendar: calendar,
            homeDirectory: homeDirectory
        )

        return ProjectOpenPresentation(
            appMark: appMarkText,
            title: titleText,
            detailText: detailMessage,
            openButtonTitle: openButtonText,
            openButtonShortcut: openShortcut,
            // Only an open in flight disables the button. A failed open re-enables it,
            // because trying again — or picking somewhere else — is the way out.
            isOpenButtonEnabled: phase != .opening,
            recentSectionTitle: rows.isEmpty ? nil : recentTitle,
            recentProjects: rows,
            exclusionNotice: exclusionNoticeText,
            failureSheet: sheet(for: phase, recentPaths: Set(rows.map(\.rootPath)))
        )
    }

    // MARK: 최근 목록

    private static func recentRows(
        _ projects: [RecentProject],
        now: Date,
        calendar: Calendar,
        homeDirectory: String
    ) -> [RecentProjectRow] {
        projects
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            .prefix(maximumRecentProjects)
            .map { project in
                RecentProjectRow(
                    name: project.name,
                    displayPath: abbreviatingHome(project.rootPath, homeDirectory: homeDirectory),
                    relativeTime: relativeTime(of: project.lastOpenedAt, now: now, calendar: calendar),
                    rootPath: project.rootPath
                )
            }
    }

    private static func abbreviatingHome(_ path: String, homeDirectory: String) -> String {
        if path == homeDirectory {
            return "~"
        }
        let homeWithSeparator = homeDirectory.hasSuffix("/") ? homeDirectory : homeDirectory + "/"
        // The separator has to be part of the check, or "/Users/development" would be
        // abbreviated as if it sat inside "/Users/dev".
        guard path.hasPrefix(homeWithSeparator) else {
            return path
        }
        return "~/" + path.dropFirst(homeWithSeparator.count)
    }

    /// "오늘 09:12" · "어제" · "8월 26일" · "2025년 8월 26일".
    ///
    /// The day is decided by the calendar rather than by subtracting 24 hours: something
    /// opened at 00:10 this morning is "오늘" even though it was less than a day ago, and
    /// that is what a person means by the word.
    private static func relativeTime(of date: Date, now: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return ""
        }

        if calendar.isDate(date, inSameDayAs: now) {
            return String(format: "오늘 %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "어제"
        }

        let currentYear = calendar.component(.year, from: now)
        // Design §3 W-2 names only three cases. Without the year, last August reads exactly
        // like three days ago, and a list sorted newest-first then looks shuffled.
        guard year == currentYear else {
            return "\(year)년 \(month)월 \(day)일"
        }
        return "\(month)월 \(day)일"
    }

    // MARK: 실패 시트 (AC-3)

    private static func sheet(for phase: ProjectOpenPhase, recentPaths: Set<String>) -> ProjectOpenFailureSheet? {
        guard case .failed(let error) = phase else {
            return nil
        }

        switch error {
        case .projectNotFound(let path):
            return ProjectOpenFailureSheet(
                title: failureTitle,
                // The whole path, unshortened: which folder is missing is the entire
                // content of this sheet.
                detail: "경로를 찾을 수 없습니다: \(path)",
                confirmTitle: confirmText,
                // The path is gone, so the entry is a door to nowhere. Only this failure
                // proves that — an unreadable folder is still there.
                forgetRecentProjectPath: recentPaths.contains(path) ? path : nil
            )

        case .projectNotReadable(let path, _):
            return ProjectOpenFailureSheet(
                title: failureTitle,
                // Deliberately without the underlying reason string: "Permission denied"
                // beside a Korean sentence adds nothing the sentence has not said.
                detail: "폴더에 접근할 권한이 없습니다: \(path)",
                confirmTitle: confirmText,
                // Kept: granting access makes this entry work again, and a user who lost
                // it from the list has no way back to it.
                forgetRecentProjectPath: nil
            )

        default:
            // Opening can fail in ways design §3 W-2 does not enumerate. Falling through to
            // no sheet would turn those into the silent no-op AC-3 forbids.
            return ProjectOpenFailureSheet(
                title: failureTitle,
                detail: error.errorDescription ?? genericFailureDetail,
                confirmTitle: confirmText,
                forgetRecentProjectPath: nil
            )
        }
    }
}
