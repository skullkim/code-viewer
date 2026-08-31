import Foundation

/// Why a local resource the document referred to could not be inlined.
///
/// The reason travels instead of being collapsed into `nil`. A loader that answers "no bytes"
/// makes *not there*, *too big* and *outside the project* the same event, and then the W-15
/// chip cannot say which happened — which removes the only reason the contract carries
/// distinct errors at all.
public enum RenderResourceFailure: Error, Sendable, Hashable {
    /// Larger than the render limit. The one reason the reader can act on.
    case tooLarge(byteSize: Int, limit: Int)
    case notFound
    case notReadable(String)
    /// The engine refused the path — outside the project root (INV-6).
    case invalidPath
}

/// A resource that could not be shown but was **not blocked by us**.
///
/// Kept apart from `BlockedResource` deliberately. W-15's list is a list of things the sandbox
/// refused; a file that is simply missing did not get refused, and putting it there tells the
/// reader we blocked something we did not. Reported, never silently dropped.
public struct UnavailableResource: Sendable, Hashable {
    public let path: String
    public let failure: RenderResourceFailure

    public init(path: String, failure: RenderResourceFailure) {
        self.path = path
        self.failure = failure
    }
}
