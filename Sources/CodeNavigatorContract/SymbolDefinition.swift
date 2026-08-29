/// A declaration site: where a symbol is defined.
///
/// `path` is always project-relative, POSIX-separated, with no leading slash.
/// `line` is 1-based. `signature` is the trimmed source line the declaration starts on.
public struct SymbolDefinition: Sendable, Hashable, Codable, Identifiable {
    public let name: String
    public let kind: SymbolKind
    public let path: String
    public let line: Int
    public let signature: String

    public var id: String { "\(path):\(line):\(name)" }

    public init(name: String, kind: SymbolKind, path: String, line: Int, signature: String) {
        self.name = name
        self.kind = kind
        self.path = path
        self.line = line
        self.signature = signature
    }
}
