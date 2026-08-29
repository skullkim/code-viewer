/// The languages the symbol extractor understands.
///
/// Files whose extension maps to no language are skipped by the indexer without error,
/// but are still searched by full-text search (REQ-002 AC-3).
public enum SourceLanguage: String, Sendable, Hashable, CaseIterable {
    case kotlin
    case java
    case typescript
    case javascript

    /// The language of a file, by extension, or `nil` when the extension is not supported.
    public init?(filePath: String) {
        guard let fileExtension = FileExtension.of(filePath: filePath) else { return nil }
        switch fileExtension {
        case "kt", "kts":
            self = .kotlin
        case "java":
            self = .java
        case "ts", "mts", "cts", "tsx":
            self = .typescript
        case "js", "jsx", "mjs", "cjs":
            self = .javascript
        default:
            return nil
        }
    }
}
