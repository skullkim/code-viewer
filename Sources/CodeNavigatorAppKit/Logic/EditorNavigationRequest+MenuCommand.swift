import CodeNavigatorContract

extension EditorNavigationRequest {
    /// The menu command this request means (REQ-015 AC-1, AC-2).
    ///
    /// `gd` and `gr` are required to give **the same result** as ⌘B and ⇧⌘B, and the cheapest way
    /// to guarantee sameness is to arrive at the same command rather than at a parallel one. This
    /// property is the entire translation; everything downstream is the path the menu already
    /// uses (ADR-0113).
    var menuCommand: MenuCommand {
        switch self {
        case .goToDefinition: return .goToDefinition
        case .findReferences: return .showReferences
        }
    }
}
