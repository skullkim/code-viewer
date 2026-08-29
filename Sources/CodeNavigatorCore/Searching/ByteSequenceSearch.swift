/// Finds every occurrence of one byte sequence inside another.
///
/// Matches never overlap: after a hit the search resumes past it, so `"aa"` is found once in
/// `"aaa"` — the same counting rule line-oriented search tools use.
enum ByteSequenceSearch {

    /// Offsets are relative to the start of `haystack`, not to the buffer it is sliced from,
    /// so callers can hand them straight to `PreviewTextBuilder` alongside the line's text.
    static func occurrences(of needle: [UInt8], in haystack: ArraySlice<UInt8>) -> [Range<Int>] {
        guard !needle.isEmpty, haystack.count >= needle.count else {
            return []
        }

        var ranges: [Range<Int>] = []
        let base = haystack.startIndex
        let lastPossibleStart = haystack.endIndex - needle.count
        var index = base

        while index <= lastPossibleStart {
            guard matches(needle, in: haystack, at: index) else {
                index += 1
                continue
            }

            ranges.append((index - base)..<(index - base + needle.count))
            index += needle.count
        }

        return ranges
    }

    private static func matches(_ needle: [UInt8], in haystack: ArraySlice<UInt8>, at index: Int) -> Bool {
        for offset in 0..<needle.count where haystack[index + offset] != needle[offset] {
            return false
        }
        return true
    }
}
