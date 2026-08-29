/// A half-open range `[start, end)` of matched text, for highlighting.
///
/// Offsets are **UTF-16 code units** into the accompanying preview or name string,
/// which is what Swift's `String.UTF16View` and AppKit/SwiftUI text APIs use.
public struct MatchRange: Sendable, Hashable, Codable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}
