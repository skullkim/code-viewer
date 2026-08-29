import CodeNavigatorContract

/// One line that matched, before the index has been asked whether it is a definition site.
struct MatchedLine {
    let path: String
    let line: Int
    let previewText: String
    /// Where the whole-token hits landed, already converted to the preview's UTF-16 offsets.
    let matchRanges: [MatchRange]
}
