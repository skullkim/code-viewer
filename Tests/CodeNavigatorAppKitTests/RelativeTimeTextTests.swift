import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// The wording for "when did this happen", shared by the recent-projects list (design §3
/// W-2) and the index details popover (W-10).
///
/// It had no tests of its own while two consumers each covered it incidentally. Now that
/// it is the single source for both, a change here reaches two screens at once, so it is
/// tested directly.
@Suite("RelativeTimeText — 상대 시각 문구")
struct RelativeTimeTextTests {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone.current
        return calendar.date(from: components)!
    }

    @Test("오늘은 시각까지 보여준다")
    func todayShowsTheTime() {
        let now = date(2026, 8, 29, 15, 30)
        #expect(RelativeTimeText.string(for: date(2026, 8, 29, 9, 12), now: now, calendar: calendar) == "오늘 09:12")
    }

    @Test("한 자리 시각도 두 자리로 채운다")
    func singleDigitTimesArePadded() {
        let now = date(2026, 8, 29, 23, 0)
        #expect(RelativeTimeText.string(for: date(2026, 8, 29, 7, 5), now: now, calendar: calendar) == "오늘 07:05")
    }

    @Test("어제는 시각 없이 어제다")
    func yesterdayIsJustYesterday() {
        let now = date(2026, 8, 29, 15, 30)
        #expect(RelativeTimeText.string(for: date(2026, 8, 28, 9, 12), now: now, calendar: calendar) == "어제")
    }

    @Test("올해의 다른 날은 월·일이다")
    func otherDaysThisYearShowMonthAndDay() {
        let now = date(2026, 8, 29, 15, 30)
        #expect(RelativeTimeText.string(for: date(2026, 8, 26), now: now, calendar: calendar) == "8월 26일")
        #expect(RelativeTimeText.string(for: date(2026, 1, 3), now: now, calendar: calendar) == "1월 3일")
    }

    @Test("작년 이전은 연도를 붙인다")
    func earlierYearsCarryTheYear() {
        // Without the year, last August reads exactly like three days ago, and a list
        // sorted newest-first then looks shuffled.
        let now = date(2026, 8, 29, 15, 30)
        #expect(RelativeTimeText.string(for: date(2025, 8, 26), now: now, calendar: calendar) == "2025년 8월 26일")
    }

    @Test("자정 직후와 직전이 다른 날로 갈린다")
    func midnightSeparatesTheDays() {
        // A minute apart across midnight is "today" and "yesterday", not one bucket.
        let now = date(2026, 8, 29, 0, 30)
        #expect(RelativeTimeText.string(for: date(2026, 8, 29, 0, 1), now: now, calendar: calendar) == "오늘 00:01")
        #expect(RelativeTimeText.string(for: date(2026, 8, 28, 23, 59), now: now, calendar: calendar) == "어제")
    }

    @Test("해가 바뀐 직후에도 어제는 어제다")
    func yesterdayWorksAcrossANewYear() {
        // The year branch must not run before the yesterday branch, or 12월 31일 reads as
        // "2025년 12월 31일" on New Year's Day.
        let now = date(2026, 1, 1, 10, 0)
        #expect(RelativeTimeText.string(for: date(2025, 12, 31, 22, 0), now: now, calendar: calendar) == "어제")
    }

    @Test("미래 시각도 무너지지 않는다")
    func futureDatesAreSurvivable() {
        // A clock change or a restored preference can put a stored date ahead of now.
        let now = date(2026, 8, 29, 10, 0)
        let text = RelativeTimeText.string(for: date(2026, 9, 2), now: now, calendar: calendar)
        #expect(!text.isEmpty)
    }
}
