import CodeNavigatorContract

/// What ⌘B should do, given what the index found.
public enum DefinitionOutcome: Sendable, Hashable {
    /// Exactly one definition: go there without asking.
    case navigate(path: String, line: Int)
    /// Several definitions share the name; the user chooses (REQ-005 AC-2).
    case presentCandidates([SymbolDefinition])
    /// The name is not in the index (REQ-005 AC-3).
    case reportNotFound(message: String)
    /// The cursor is not on an identifier at all.
    case reportNoSymbolUnderCursor(message: String)
}

/// Decides what go-to-definition does.
///
/// Kept apart from the view because the branch the design cares about most is the empty
/// one: REQ-005 AC-3 forbids a silent no-op, and silence is exactly what a forgotten else
/// branch produces.
public enum DefinitionRouting {
    public static func route(symbolName: String, definitions: [SymbolDefinition]) -> DefinitionOutcome {
        let name = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return .reportNoSymbolUnderCursor(message: "✕ 커서 위치에 심볼이 없습니다")
        }
        guard let only = definitions.first else {
            return .reportNotFound(message: "✕ '\(name)' 정의를 찾을 수 없습니다")
        }
        guard definitions.count > 1 else {
            return .navigate(path: only.path, line: only.line)
        }
        return .presentCandidates(definitions)
    }
}
