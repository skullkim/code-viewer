/// One full-text search hit: a matching line with the match positions inside its preview.
public struct TextSearchItem: Sendable, Hashable, Identifiable {
    public let path: String
    public let line: Int
    public let previewText: String
    public let matchRanges: [MatchRange]

    public var id: String { "\(path):\(line)" }

    public init(path: String, line: Int, previewText: String, matchRanges: [MatchRange]) {
        self.path = path
        self.line = line
        self.previewText = previewText
        self.matchRanges = matchRanges
    }
}
