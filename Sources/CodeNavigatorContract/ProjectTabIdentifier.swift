import Foundation

/// Identifies one open project tab.
///
/// An identifier rather than the root path, because the same project can be closed and opened
/// again. If a path were the identity, a stale reference held across that would silently address
/// the new tab as though nothing had happened.
public struct ProjectTabIdentifier: Sendable, Hashable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
