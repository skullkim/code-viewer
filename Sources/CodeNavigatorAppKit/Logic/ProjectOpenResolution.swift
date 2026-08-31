import Foundation

/// Whether opening a path makes a new tab or activates one that is already open.
public enum ProjectOpenResolution: Sendable, Hashable {
    case activateExisting(tabID: String)
    case openNew(identity: String)
}
