import Foundation

/// How the shell writes a past moment: "오늘 09:12" · "어제" · "8월 26일" · "2025년 8월 26일".
///
/// Two screens show one — the recent-project list (design §3 W-2) and the index details
/// popover (§3 W-10). The wording is the same in both, so the rule is one function; a
/// second copy would drift the moment either screen's wording is adjusted.
///
/// The day is decided by the calendar rather than by subtracting twenty-four hours:
/// something that happened at 00:10 this morning is "오늘" even though it was less than a
/// day ago, and that is what a person means by the word.
public enum RelativeTimeText {

    public static func string(for date: Date, now: Date, calendar: Calendar) -> String {
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

        // Without the year, last August reads exactly like three days ago, and a list
        // sorted newest-first then looks shuffled.
        let currentYear = calendar.component(.year, from: now)
        guard year == currentYear else {
            return "\(year)년 \(month)월 \(day)일"
        }
        return "\(month)월 \(day)일"
    }
}
