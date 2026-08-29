import Foundation
import CodeNavigatorContract

/// A stretch of text, marked as matched or not.
public struct HighlightSegment: Sendable, Hashable {
    public let text: String
    public let isMatch: Bool

    public init(text: String, isMatch: Bool) {
        self.text = text
        self.isMatch = isMatch
    }
}

/// Splits a string into matched and unmatched segments.
///
/// `MatchRange` offsets are UTF-16 code units, which is what the engine's text handling
/// and AppKit both use — but not what Swift's `String` indexing uses. Counting characters
/// instead would place the highlight correctly on ASCII and wrongly on everything else:
/// Korean text, accents and emoji all break the assumption, and this repository's own
/// sources are full of Korean.
///
/// Every range is clamped and validated. A highlight is cosmetic, and an off-by-one from
/// the engine should cost a highlight, not the panel (REQ-NF-004).
public enum MatchHighlighter {

    public static func segments(text: String, ranges: [MatchRange]) -> [HighlightSegment] {
        guard !text.isEmpty else {
            return []
        }

        let units = Array(text.utf16)
        let normalised = normalise(ranges, units: units)
        guard !normalised.isEmpty else {
            return [HighlightSegment(text: text, isMatch: false)]
        }

        var segments: [HighlightSegment] = []
        var cursor = 0

        for range in normalised {
            if range.lowerBound > cursor {
                append(&segments, units: units, from: cursor, to: range.lowerBound, isMatch: false)
            }
            append(&segments, units: units, from: range.lowerBound, to: range.upperBound, isMatch: true)
            cursor = range.upperBound
        }
        if cursor < units.count {
            append(&segments, units: units, from: cursor, to: units.count, isMatch: false)
        }

        return segments
    }

    /// Clamps ranges to the string, drops the nonsensical ones, then sorts and merges what
    /// is left so overlapping matches produce one highlight rather than nested ones.
    private static func normalise(_ ranges: [MatchRange], units: [UInt16]) -> [Range<Int>] {
        let length = units.count
        let valid: [Range<Int>] = ranges.compactMap { range in
            // Clamp both ends independently before comparing them. A range entirely past
            // the end would otherwise produce a lower bound above its upper bound, which
            // is a trap rather than an empty range.
            let lower = snapToCharacterBoundary(min(max(0, range.start), length), in: units)
            let upper = snapToCharacterBoundary(min(max(0, range.end), length), in: units)
            guard lower < upper else { return nil }
            return lower..<upper
        }
        .sorted { $0.lowerBound < $1.lowerBound }

        var merged: [Range<Int>] = []
        for range in valid {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Moves an offset off the middle of a surrogate pair.
    ///
    /// A UTF-16 offset can name a position that is not a character boundary. Cutting there
    /// would turn one emoji into two replacement characters — the text would come back
    /// visibly corrupted, which is worse than a missing highlight.
    private static func snapToCharacterBoundary(_ offset: Int, in units: [UInt16]) -> Int {
        guard offset > 0, offset < units.count else {
            return offset
        }
        let isLowSurrogate = (0xDC00...0xDFFF).contains(units[offset])
        let followsHighSurrogate = (0xD800...0xDBFF).contains(units[offset - 1])
        return isLowSurrogate && followsHighSurrogate ? offset - 1 : offset
    }

    private static func append(
        _ segments: inout [HighlightSegment],
        units: [UInt16],
        from start: Int,
        to end: Int,
        isMatch: Bool
    ) {
        let slice = Array(units[start..<end])
        segments.append(HighlightSegment(
            text: String(utf16CodeUnits: slice, count: slice.count),
            isMatch: isMatch
        ))
    }
}
