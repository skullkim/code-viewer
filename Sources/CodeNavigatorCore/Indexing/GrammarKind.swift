/// Which tree-sitter grammar parses a file.
///
/// This is deliberately separate from `SourceLanguage`: the language is what we report to the
/// user, the grammar is how we parse. JavaScript files are parsed with the TSX grammar, which is
/// a superset of JavaScript — see ADR-0002 for why we do not depend on the JavaScript grammar
/// package.
enum GrammarKind: String, Sendable, Hashable, CaseIterable {
    case kotlin
    case java
    case typescript
    case tsx

    init?(filePath: String) {
        guard let fileExtension = FileExtension.of(filePath: filePath) else { return nil }
        switch fileExtension {
        case "kt", "kts":
            self = .kotlin
        case "java":
            self = .java
        case "ts", "mts", "cts":
            self = .typescript
        case "tsx", "js", "jsx", "mjs", "cjs":
            self = .tsx
        default:
            return nil
        }
    }
}
