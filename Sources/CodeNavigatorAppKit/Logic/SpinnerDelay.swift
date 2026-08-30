import Foundation

/// When a spinner has waited long enough to be worth showing (design §3 W-3).
///
/// Symbol search answers from an in-memory index, so most queries finish in a few
/// milliseconds. Showing a spinner for those produces a flash that reads as a glitch
/// rather than as progress — the design asks for the spinner only once a search has run
/// past 200ms, which is roughly where a person starts to notice a wait at all.
///
/// A rule about time, kept out of the view: a view that compares dates in its body is a
/// view whose behaviour can only be checked by watching it.
public enum SpinnerDelay {

    /// Design §3 W-3: "로딩(200ms 이상일 때만 스피너 — 깜빡임 방지)".
    public static let threshold: TimeInterval = 0.2

    /// - Parameter startedAt: when the in-flight search began, or nil when none is running.
    public static func showsSpinner(startedAt: Date?, now: Date) -> Bool {
        guard let startedAt else {
            return false
        }
        // A negative interval means the clock moved backwards between the two readings.
        // Treating that as "long enough" would pop a spinner onto an idle screen.
        return now.timeIntervalSince(startedAt) >= threshold
    }
}
