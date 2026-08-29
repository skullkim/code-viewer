/// One row of the editor grid, as styled runs left to right.
public struct EditorGridLine: Sendable, Hashable {
    public let runs: [EditorTextRun]

    public init(runs: [EditorTextRun]) {
        self.runs = runs
    }

    /// The row's text with styling dropped — useful for tests and accessibility.
    ///
    /// **Not usable for column arithmetic.** Joining runs drops the empty cells Neovim sends
    /// after double-width characters, so a character offset into this string does not correspond
    /// to a grid column. Use `EditorTextRun.startColumn` for positioning.
    public var plainText: String {
        runs.map(\.text).joined()
    }
}
