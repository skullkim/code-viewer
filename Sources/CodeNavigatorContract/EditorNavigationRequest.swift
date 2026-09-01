/// A navigation the user asked for from inside the editor (REQ-015).
///
/// The value carries **no symbol name on purpose**. The application already has a path that
/// answers ⌘B and ⇧⌘B — it reads the word under the cursor, resolves it, and shows candidates
/// when there is more than one. Putting the name in this signal would let a second path grow
/// beside that one, and REQ-015 AC-1/AC-2 ask for the *same* behaviour, not a similar one.
/// An empty signal makes sameness a property of the call graph rather than of anyone's care.
public enum EditorNavigationRequest: String, Sendable, Hashable, Codable, CaseIterable {
    /// `gd` — jump to the definition of the symbol under the cursor.
    case goToDefinition
    /// `gr` — list every use of the symbol under the cursor.
    case findReferences
}
