import CodeNavigatorContract

/// One candidate row in the definition popover (design §3 W-4).
public struct DefinitionCandidateRow: Sendable, Hashable, Identifiable {
    public let definition: SymbolDefinition
    public let badge: SymbolKindBadge
    /// Always one line: the popover's rows have a fixed height, so a signature that
    /// wrapped would push the rows below it out of the card.
    public let signature: String
    public let location: String

    public var id: String { definition.id }
}

/// The definition popover shown when a name has more than one definition (REQ-005 AC-2).
public struct DefinitionCandidatePresentation: Sendable, Hashable {
    /// Drawn bold, separately from the rest of the sentence.
    public let symbolName: String
    public let headerDetail: String
    public let rows: [DefinitionCandidateRow]
    public let footerText: String
    public let keyHintText: String
}

extension DefinitionCandidatePresentation {
    public static let referencesFooter = "이 이름의 참조 보기 ⇧⌘B"
    public static let keyHint = "↑↓ 이동 · ⏎ 열기 · esc 취소"

    public static func make(symbolName: String, definitions: [SymbolDefinition]) -> DefinitionCandidatePresentation {
        DefinitionCandidatePresentation(
            symbolName: symbolName,
            headerDetail: "정의 \(definitions.count)건 — 이동할 위치를 선택하세요",
            // The engine sorts by path then line; re-sorting here would silently override
            // a decision that belongs to the index.
            rows: definitions.map(row(for:)),
            footerText: referencesFooter,
            keyHintText: keyHint
        )
    }

    private static func row(for definition: SymbolDefinition) -> DefinitionCandidateRow {
        DefinitionCandidateRow(
            definition: definition,
            badge: SymbolKindBadge.badge(for: definition.kind),
            signature: singleLine(definition.signature),
            location: "\(definition.path):\(definition.line)"
        )
    }

    /// Folds a declaration onto one line.
    ///
    /// A signature that spans lines — a long parameter list, a where clause — would make
    /// its row taller than the rest and push the rows below it out of the card. Whitespace is
    /// collapsed rather than stripped, so the words do not run together.
    private static func singleLine(_ signature: String) -> String {
        signature
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
