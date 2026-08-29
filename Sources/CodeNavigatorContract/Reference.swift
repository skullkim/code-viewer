/// One usage site of a symbol name.
///
/// Reference search is **name-based approximation** — there is no type resolution,
/// so same-named symbols from unrelated types can appear. The UI states this permanently
/// (REQ-006 AC-3). Definition sites are included in the list, flagged by `isDefinition`.
public struct Reference: Sendable, Hashable, Identifiable {
    public let path: String
    public let line: Int
    public let previewText: String
    public let isDefinition: Bool

    public var id: String { "\(path):\(line)" }

    public init(path: String, line: Int, previewText: String, isDefinition: Bool) {
        self.path = path
        self.line = line
        self.previewText = previewText
        self.isDefinition = isDefinition
    }
}
