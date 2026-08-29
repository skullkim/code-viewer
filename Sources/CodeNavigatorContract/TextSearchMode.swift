/// How a full-text query string is interpreted (REQ-008).
public enum TextSearchMode: String, Sendable, Codable, Hashable, CaseIterable {
    /// The query is matched literally; regular-expression metacharacters carry no meaning.
    case literal
    /// The query is a regular expression; an invalid pattern is reported as an error,
    /// never disguised as an empty result set.
    case regularExpression
}
