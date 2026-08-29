/// One usage site of a symbol name.
///
/// Reference search is **name-based approximation** — there is no type resolution,
/// so same-named symbols from unrelated types can appear. The UI states this permanently
/// (REQ-006 AC-3). Definition sites are included in the list, flagged by `isDefinition`.
public struct Reference: Sendable, Hashable, Identifiable {
    public let path: String
    public let line: Int
    public let previewText: String
    /// Where the symbol sits inside `previewText`, in UTF-16 code units.
    ///
    /// Reported rather than left to the caller because the search decides what counts as a whole
    /// identifier, and that rule is not one a view can re-derive. A byte from 0x80 up continues an
    /// identifier here, so `사용자Index` is one name and not a hit on `Index`; a view doing a
    /// plain substring search would highlight text the engine deliberately did not match.
    public let matchRanges: [MatchRange]
    public let isDefinition: Bool

    public var id: String { "\(path):\(line)" }

    public init(
        path: String,
        line: Int,
        previewText: String,
        matchRanges: [MatchRange] = [],
        isDefinition: Bool
    ) {
        self.path = path
        self.line = line
        self.previewText = previewText
        self.matchRanges = matchRanges
        self.isDefinition = isDefinition
    }
}
