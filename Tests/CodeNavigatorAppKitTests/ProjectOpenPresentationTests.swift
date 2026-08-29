import Foundation
import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// REQ-001. The screen the user meets with nothing open, and the two ways opening fails.
///
/// AC-3 is the one worth testing hardest: "명확한 에러를 표시하고 이전 상태를 유지한다".
/// A missing folder and a folder you are not allowed to read need different sentences —
/// 03 §3 forbids masking one as the other, because the fixes are different (find the
/// project vs. grant access), and a single "열 수 없습니다" sends the user looking in the
/// wrong place.
@Suite("ProjectOpenPresentation — 프로젝트 열기 W-2 (REQ-001)")
struct ProjectOpenPresentationTests {

    private let home = "/Users/dev"

    /// A fixed calendar and clock. Relative time is the whole point of the recent list, so
    /// letting the machine's timezone decide what "오늘" means would make these cases pass
    /// or fail by the hour (RecentProjectStore injects its clock for the same reason).
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.locale = Locale(identifier: "ko_KR")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 2026-08-29 14:30 Asia/Seoul — "now" for every case below.
    private var now: Date { date(2026, 8, 29, 14, 30) }

    private func project(_ name: String, _ path: String, _ openedAt: Date) -> RecentProject {
        RecentProject(name: name, rootPath: path, lastOpenedAt: openedAt)
    }

    private func make(
        recent: [RecentProject] = [],
        phase: ProjectOpenPhase = .idle
    ) -> ProjectOpenPresentation {
        ProjectOpenPresentation.make(
            recentProjects: recent,
            phase: phase,
            now: now,
            calendar: calendar,
            homeDirectory: home
        )
    }

    // MARK: 안내 문구 (AC-1 · AC-4)

    @Test("웰컴 화면은 02 W-2의 제목·설명·버튼 문구를 그대로 쓴다")
    func theWelcomeCopyMatchesTheDesign() {
        let screen = make()

        #expect(screen.appMark == "CN")
        #expect(screen.title == "프로젝트를 여세요")
        #expect(screen.detailText == "로컬 레포 폴더를 열면 트리가 표시되고 인덱싱이 시작됩니다.")
        #expect(screen.openButtonTitle == "프로젝트 열기…")
        #expect(screen.openButtonShortcut == "⌘O")
    }

    @Test("제외 규칙 고지가 상시 표시된다")
    func theExclusionNoticeIsAlwaysShown() {
        // REQ-001 AC-4의 유일한 UI 표면이다. 사용자가 "왜 이 파일이 안 보이지"를
        // 묻기 전에 답해 두는 문구라, 어떤 상태에서도 사라지면 안 된다.
        for phase in [ProjectOpenPhase.idle, .opening, .failed(.projectNotFound(path: "/gone"))] {
            let screen = make(phase: phase)

            #expect(screen.exclusionNotice.contains(".gitignore"))
            #expect(screen.exclusionNotice.contains("node_modules"))
        }
    }

    // MARK: 최근 목록 (AC-2)

    @Test("최근 0건이면 리스트 블록 자체가 사라진다")
    func theRecentBlockDisappearsWhenThereAreNone() {
        // 02 W-2: "리스트 블록 자체를 숨기고 [프로젝트 열기…]만".
        // 제목만 남기고 비우면 목록을 못 불러온 것처럼 읽힌다.
        let screen = make(recent: [])

        #expect(screen.recentSectionTitle == nil)
        #expect(screen.recentProjects.isEmpty)
    }

    @Test("최근 N건은 제목과 함께 최신순으로 나온다")
    func recentProjectsAreListedNewestFirst() {
        let screen = make(recent: [
            project("older", "\(home)/repo/older", date(2026, 8, 20)),
            project("newest", "\(home)/repo/newest", date(2026, 8, 29, 9, 12)),
            project("middle", "\(home)/repo/middle", date(2026, 8, 28)),
        ])

        #expect(screen.recentSectionTitle == "최근 프로젝트")
        #expect(screen.recentProjects.map(\.name) == ["newest", "middle", "older"])
    }

    @Test("최근 목록은 5건에서 잘린다")
    func theRecentListIsCappedAtFive() {
        // 저장소도 5건에서 자르지만, 화면의 상한은 화면이 지킨다.
        // 다른 층의 약속에 기대면 그 층이 바뀔 때 조용히 6건이 그려진다.
        let seven = (1...7).map { index in
            project("p\(index)", "\(home)/repo/p\(index)", date(2026, 8, 29 - index))
        }

        #expect(make(recent: seven).recentProjects.count == 5)
    }

    @Test("경로는 홈 디렉토리를 ~로 줄여 보여준다")
    func theHomeDirectoryIsAbbreviated() {
        let screen = make(recent: [
            project("inside", "\(home)/repo/inside", now),
            project("outside", "/opt/work/outside", now),
        ])

        #expect(screen.recentProjects[0].displayPath == "~/repo/inside")
        // 홈 밖 경로는 줄일 곳이 없다 — 그대로 보여주는 것이 정확하다.
        #expect(screen.recentProjects[1].displayPath == "/opt/work/outside")
    }

    @Test("줄인 것은 표시용이고, 여는 데 쓰는 경로는 원본 그대로다")
    func theAbbreviatedPathIsNeverUsedToOpen() {
        // "~"를 그대로 열기에 넘기면 존재하지 않는 경로가 되어 AC-3의 실패 시트가
        // 사용자 잘못이 아닌 이유로 뜬다.
        let screen = make(recent: [project("inside", "\(home)/repo/inside", now)])

        #expect(screen.recentProjects[0].rootPath == "\(home)/repo/inside")
        #expect(screen.recentProjects[0].id == "\(home)/repo/inside")
    }

    // MARK: 마지막 연 시각

    @Test("오늘 연 프로젝트는 시각까지 보여준다")
    func todayShowsTheTime() {
        let screen = make(recent: [project("today", "\(home)/a", date(2026, 8, 29, 9, 12))])

        #expect(screen.recentProjects[0].relativeTime == "오늘 09:12")
    }

    @Test("어제 연 프로젝트는 '어제'로만 보여준다")
    func yesterdayShowsNoTime() {
        let screen = make(recent: [project("yesterday", "\(home)/a", date(2026, 8, 28, 23, 59))])

        #expect(screen.recentProjects[0].relativeTime == "어제")
    }

    @Test("그 이전은 날짜로 보여준다")
    func olderEntriesShowTheDate() {
        let screen = make(recent: [project("older", "\(home)/a", date(2026, 8, 26, 10, 0))])

        #expect(screen.recentProjects[0].relativeTime == "8월 26일")
    }

    @Test("해가 다르면 연도를 붙인다")
    func adifferentYearKeepsItsYear() {
        // 02는 세 경우만 적어 뒀다. 작년 8월 26일을 "8월 26일"로 쓰면 오늘로부터
        // 사흘 전과 구분되지 않아, 최신순으로 정렬된 목록이 뒤죽박죽으로 보인다.
        let screen = make(recent: [project("lastYear", "\(home)/a", date(2025, 8, 26, 10, 0))])

        #expect(screen.recentProjects[0].relativeTime == "2025년 8월 26일")
    }

    @Test("자정 직전과 직후는 하루 차이로 갈린다")
    func theDayBoundaryIsCalendarBased() {
        // 24시간 뺄셈으로 판정하면 오늘 00:10에 연 것이 "어제"가 된다.
        // 사람이 말하는 "어제"는 달력의 날짜 경계다.
        let screen = make(recent: [
            project("earlyToday", "\(home)/a", date(2026, 8, 29, 0, 10)),
            project("lateYesterday", "\(home)/b", date(2026, 8, 28, 23, 50)),
        ])

        #expect(screen.recentProjects[0].relativeTime == "오늘 00:10")
        #expect(screen.recentProjects[1].relativeTime == "어제")
    }

    // MARK: 여는 중

    @Test("여는 동안에는 열기 버튼이 비활성이다")
    func theOpenButtonIsDisabledWhileOpening() {
        #expect(make(phase: .idle).isOpenButtonEnabled)
        #expect(!make(phase: .opening).isOpenButtonEnabled)
    }

    @Test("여는 동안에도 최근 목록은 그대로 보인다")
    func theRecentListSurvivesOpening() {
        let screen = make(recent: [project("a", "\(home)/a", now)], phase: .opening)

        #expect(screen.recentProjects.count == 1)
        #expect(screen.failureSheet == nil)
    }

    // MARK: 실패 시트 (AC-3)

    @Test("경로 없음과 권한 없음은 서로 다른 문구로 나온다")
    func theTwoFailuresGetDifferentWording() {
        // 03 §3: 사유별 분기, 마스킹 금지. 두 실패의 해결 방법이 다르다 —
        // 하나는 프로젝트를 찾는 일이고 하나는 권한을 주는 일이다.
        let missing = make(phase: .failed(.projectNotFound(path: "/Users/dev/gone")))
        let unreadable = make(phase: .failed(
            .projectNotReadable(path: "/Users/dev/locked", reason: "Permission denied")
        ))

        #expect(missing.failureSheet?.title == "프로젝트를 열 수 없습니다")
        #expect(missing.failureSheet?.detail == "경로를 찾을 수 없습니다: /Users/dev/gone")

        #expect(unreadable.failureSheet?.title == "프로젝트를 열 수 없습니다")
        #expect(unreadable.failureSheet?.detail == "폴더에 접근할 권한이 없습니다: /Users/dev/locked")

        #expect(missing.failureSheet?.detail != unreadable.failureSheet?.detail)
        #expect(missing.failureSheet?.confirmTitle == "확인")
    }

    @Test("실패 시트는 경로를 줄이지 않고 그대로 싣는다")
    func theFailureSheetShowsTheWholePath() {
        // 어느 경로가 없다는 것인지가 이 시트의 전부다. ~로 줄이거나 앞을 자르면
        // 사용자가 확인해야 할 바로 그 정보가 사라진다.
        let deep = "/Users/dev/very/deep/nested/project/that/is/long"
        let screen = make(phase: .failed(.projectNotFound(path: deep)))

        #expect(screen.failureSheet?.detail.contains(deep) == true)
    }

    @Test("실패해도 이전 상태 — 최근 목록과 안내 문구 — 가 유지된다")
    func thePreviousStateSurvivesAFailure() {
        // AC-3의 "이전 상태를 유지한다". 시트 뒤에 아무것도 없으면 실패가
        // 프로젝트 목록을 날린 것처럼 보인다.
        let screen = make(
            recent: [project("a", "\(home)/a", now), project("b", "\(home)/b", now)],
            phase: .failed(.projectNotFound(path: "/gone"))
        )

        #expect(screen.recentProjects.count == 2)
        #expect(screen.recentSectionTitle == "최근 프로젝트")
        #expect(screen.isOpenButtonEnabled)
    }

    @Test("사라진 최근 항목은 목록에서 지우도록 표시된다")
    func aMissingRecentProjectIsMarkedForRemoval() {
        // 02 W-2: "최근 항목이 사라진 경로: 열기 시도 시 실패 시트 + 해당 항목을 목록에서 제거".
        let gone = "\(home)/repo/gone"
        let screen = make(
            recent: [project("gone", gone, now), project("alive", "\(home)/repo/alive", now)],
            phase: .failed(.projectNotFound(path: gone))
        )

        #expect(screen.failureSheet?.forgetRecentProjectPath == gone)
    }

    @Test("최근 목록에 없는 경로를 열다 실패하면 지울 것이 없다")
    func failingOnAPathThatIsNotInTheListRemovesNothing() {
        let screen = make(
            recent: [project("alive", "\(home)/repo/alive", now)],
            phase: .failed(.projectNotFound(path: "/somewhere/else"))
        )

        #expect(screen.failureSheet?.forgetRecentProjectPath == nil)
    }

    @Test("권한 없음은 최근 목록에서 지우지 않는다")
    func anUnreadableProjectStaysInTheList() {
        // 폴더는 여전히 거기 있다. 권한을 고치면 다시 열리는데 목록에서 지워 버리면
        // 사용자가 되찾을 길이 없어진다 — "사라진 경로"와 다른 사건이다.
        let locked = "\(home)/repo/locked"
        let screen = make(
            recent: [project("locked", locked, now)],
            phase: .failed(.projectNotReadable(path: locked, reason: "Permission denied"))
        )

        #expect(screen.failureSheet != nil)
        #expect(screen.failureSheet?.forgetRecentProjectPath == nil)
    }

    @Test("그 밖의 실패도 조용히 삼키지 않는다")
    func anyOtherFailureStillGetsASheet() {
        // 계약에는 열기 실패로 올 수 있는 케이스가 둘 말고도 있다. switch 의 default 가
        // nil 을 내면 실패가 무반응이 되고, 그건 REQ-001 AC-3이 금지하는 상태다.
        let screen = make(phase: .failed(.invalidPath("~~")))

        #expect(screen.failureSheet != nil)
        #expect(screen.failureSheet?.detail.isEmpty == false)
    }

    @Test("성공 상태에는 시트가 없다")
    func thereIsNoSheetWithoutAFailure() {
        #expect(make(phase: .idle).failureSheet == nil)
        #expect(make(phase: .opening).failureSheet == nil)
    }
}
