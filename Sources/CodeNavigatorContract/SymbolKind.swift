/// The kind of a declaration, as defined in the requirements glossary (§3).
public enum SymbolKind: String, Sendable, Codable, Hashable, CaseIterable {
    case `class`
    case interface
    case `enum`
    case object
    case function
    case property
    case typeAlias
}
