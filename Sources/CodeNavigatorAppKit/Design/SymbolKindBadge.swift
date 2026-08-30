import CodeNavigatorContract

/// The 18×18 badge that marks a symbol's kind (design §4.1).
///
/// The letter is not decoration. §4.5 forbids colour as the only signal, so the four badge
/// colours have to carry seven kinds between them — the letter is what actually tells `E`
/// from `F` when both are purple, and the accessibility label is what tells them apart
/// when neither is visible.
public struct SymbolKindBadge: Sendable, Hashable {
    public let letter: String
    public let token: ColorToken
    public let accessibilityLabel: String
}

extension SymbolKindBadge {
    public static func badge(for kind: SymbolKind) -> SymbolKindBadge {
        switch kind {
        case .class:
            return SymbolKindBadge(letter: "C", token: DesignTokens.accentText, accessibilityLabel: "클래스")
        case .object:
            return SymbolKindBadge(letter: "O", token: DesignTokens.accentText, accessibilityLabel: "오브젝트")
        case .interface:
            return SymbolKindBadge(letter: "I", token: DesignTokens.teal, accessibilityLabel: "인터페이스")
        case .typeAlias:
            return SymbolKindBadge(letter: "T", token: DesignTokens.teal, accessibilityLabel: "타입 별칭")
        case .enum:
            return SymbolKindBadge(letter: "E", token: DesignTokens.purple, accessibilityLabel: "열거형")
        case .function:
            return SymbolKindBadge(letter: "F", token: DesignTokens.purple, accessibilityLabel: "함수")
        case .property:
            return SymbolKindBadge(letter: "P", token: DesignTokens.warning, accessibilityLabel: "프로퍼티")
        }
    }
}
