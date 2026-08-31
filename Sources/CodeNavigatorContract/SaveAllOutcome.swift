/// The result of saving every unsaved file in one project.
///
/// Saving several files is not one operation that either works or does not: three files can be
/// written while a fourth is refused. Reporting only "saved" would leave the close-confirmation
/// sheet unable to decide whether to stay open, so the per-file split travels in the value.
///
/// This is a **successful answer** even when `failures` is non-empty — the engine did the work
/// and is reporting what happened. A thrown error means something else: the question could not
/// be answered at all (no editor session). Same split as `ReferenceSearchResult.truncated`,
/// which is a value rather than an error.
public struct SaveAllOutcome: Sendable, Hashable {
    public let savedPaths: [String]
    public let failures: [SaveFailure]

    /// Nothing was refused. Having had nothing to save counts as complete — "there was nothing
    /// to do" must not be reported as a failure.
    public var isComplete: Bool { failures.isEmpty }

    public init(savedPaths: [String], failures: [SaveFailure]) {
        self.savedPaths = savedPaths
        self.failures = failures
    }
}
