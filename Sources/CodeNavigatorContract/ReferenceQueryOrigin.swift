/// Where the user was standing when they asked for references.
///
/// Reference search matches names, and a name is not a symbol: measured on a 463-file Java
/// repository, `getId` occurs on 670 lines belonging to 15 unrelated types. Knowing the cursor's
/// file and line lets the search work out which of those the user meant — without it the question
/// "references to what?" has no answer beyond the spelling.
///
/// Optional throughout. A search with no origin behaves exactly as it did before this existed, so
/// callers that genuinely have no cursor (a test, a scripted query) are not forced to invent one.
public struct ReferenceQueryOrigin: Sendable, Hashable {
    /// Project-relative, matching the paths the search returns.
    public let path: String
    /// 1-based, as the editor reports it.
    public let line: Int

    public init(path: String, line: Int) {
        self.path = path
        self.line = line
    }
}
