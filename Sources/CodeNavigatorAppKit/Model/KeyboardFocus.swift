import Observation

/// The surfaces that can hold the keyboard.
///
/// A closed set on purpose: "who has the keyboard" is answerable only if the answers are
/// enumerable. While each view decided for itself, the set was open and the answers
/// disagreed — the modal took focus, the search panel took none, and the editor took it
/// only when nobody else had it.
public enum KeyboardFocusOwner: Sendable, Hashable, CaseIterable {
    case editor
    case symbolSearchField
    case textSearchField
    case fileTree
}

/// Decides who holds the keyboard, for the whole window.
///
/// The rule the leader set is one sentence — 사용자가 클릭한 곳이 입력을 받는다 — plus one
/// thing that sentence does not cover: where the keyboard goes when a surface *stops*
/// existing. That second half is the defect this type exists for. A modal that takes the
/// keyboard and does not give it back leaves the editor unreachable, and the core flow of
/// this application (⌘P → 심볼 → 점프 → 고친다) ends at "점프".
///
/// So closing returns the keyboard to whoever had it before, not to a hardcoded default:
/// a symbol jumped to from the search panel should leave the caret in the query.
@MainActor
@Observable
public final class KeyboardFocusCoordinator {

    public private(set) var owner: KeyboardFocusOwner = .editor

    /// Where to hand the keyboard back when the surface that borrowed it goes away.
    ///
    /// Held separately from `owner` rather than inferred, because by the time a surface
    /// closes, the previous owner is not derivable from anything on screen.
    private var previousOwner: KeyboardFocusOwner = .editor

    public init() {}

    /// Moves the keyboard because the user acted — a click, or a shortcut that targets a
    /// surface. This is the only way a surface may claim the keyboard while it is up.
    public func userFocused(_ owner: KeyboardFocusOwner) {
        self.owner = owner
    }

    /// A surface appeared and takes the keyboard.
    ///
    /// One entry point for every surface, rather than a method per surface. The pair of
    /// methods that came before had an open path for the modal and none for the search
    /// panel — so the panel's field could never be told it had the keyboard, and typing
    /// into it went to the editor instead. That is the *same* asymmetry this type was
    /// introduced to remove: the modal set `isQueryFocused` on appear and the panel did
    /// not. Moving the decision here without making the interface symmetric moved the
    /// defect up a layer instead of closing it.
    ///
    /// With one generic pair, a new surface cannot be half-wired: there is nothing to
    /// forget to add.
    public func surfaceDidOpen(_ surface: KeyboardFocusOwner) {
        // Guarded: SwiftUI can deliver the same appearance twice, and saving the surface
        // itself as the return point would hand the keyboard back to something that is
        // already gone.
        guard owner != surface else { return }
        previousOwner = owner
        owner = surface
    }

    /// A surface went away and gives the keyboard back to whoever had it.
    ///
    /// Returning to the previous owner rather than to a hardcoded default is what lets a
    /// symbol jumped to from the search panel leave the caret in the query.
    public func surfaceDidClose(_ surface: KeyboardFocusOwner) {
        // A surface that closed cannot be a return point — that is exactly how the editor
        // became unreachable.
        if previousOwner == surface {
            previousOwner = .editor
        }
        if owner == surface {
            owner = previousOwner
            previousOwner = .editor
        }
    }
}
