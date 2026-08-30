import Foundation

/// Thousands separators, as design §7 writes figures ("1,284/4,812").
///
/// Grouped by hand rather than with `NumberFormatter`: this runs on paths the window body
/// takes for every update, and a formatter allocated per call is allocated hundreds of
/// times a second during a scan. The separator is `,` by design rather than by locale, so
/// there is nothing a formatter would decide.
///
/// Shared because three surfaces now write counts — the index popover, the tab tooltips and
/// the sandbox chip — and a second copy would let them drift apart on the same number.
public enum GroupedNumberText {

    public static func string(_ value: Int) -> String {
        // `magnitude` rather than `abs`, which traps on `Int.min`.
        let digits = String(value.magnitude)
        var result = ""
        result.reserveCapacity(digits.count + digits.count / 3)

        for (offset, digit) in digits.enumerated() {
            if offset > 0 && (digits.count - offset) % 3 == 0 {
                result.append(",")
            }
            result.append(digit)
        }

        return value < 0 ? "-" + result : result
    }
}
