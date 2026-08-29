/// One row of the editor grid, as styled runs left to right.
public struct EditorGridLine: Sendable, Hashable {
    public let runs: [EditorTextRun]

    public init(runs: [EditorTextRun]) {
        self.runs = runs
    }

    /// The row's text with styling dropped — useful for tests and accessibility.
    public var plainText: String {
        runs.map(\.text).joined()
    }
}
