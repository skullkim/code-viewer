import CodeNavigatorContract

extension EditorNavigationRequest {
    /// The menu commands this request runs, in order (REQ-015 AC-1, AC-2).
    ///
    /// `gd` and `gr` are required to give **the same result** as the menu, and the cheapest way to
    /// guarantee sameness is to arrive at the same commands rather than at parallel ones. This
    /// property is the entire translation; everything downstream is the path the menu already
    /// uses (ADR-0113).
    ///
    /// `gd` runs two of them. The user's requirement is *"pressing gd should list everywhere the
    /// class is used"*, and the reference panel already carries the definition among the results
    /// with a `정의` badge — so jumping **and** listing answers the whole request in one key,
    /// where either half alone answers part of it.
    ///
    /// The order is load-bearing. `showReferences` reads the word under the cursor, and
    /// `goToDefinition` moves the cursor; listing first means the usages are the ones for the
    /// symbol the user was actually pointing at.
    var menuCommands: [MenuCommand] {
        switch self {
        case .goToDefinition: return [.showReferences, .goToDefinition]
        case .findReferences: return [.showReferences]
        }
    }
}
