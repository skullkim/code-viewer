import Foundation

/// What a tab needs to know about its project's index.
///
/// A separate type from the engine's `IndexState` on purpose: a tab shows a spinner and a
/// tooltip, and nothing else. Passing the engine enum here would let a view reach for
/// progress numbers the design deliberately keeps out of a tab (02b §3 W-11).
public enum IndexStateSnapshot: Sendable, Hashable {
    case ready
    case working(label: String)
}
