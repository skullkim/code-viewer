import Foundation
import CodeNavigatorContract

/// A close the user has been asked to confirm (W-13).
///
/// Holds the dirty file list captured when the close was requested rather than re-reading
/// it while the sheet is up: the list on screen must be the list the user is deciding
/// about, and a buffer saved elsewhere mid-decision would otherwise change it underneath
/// them.
struct PendingTabClose: Identifiable, Equatable {
    let tabID: ProjectTabIdentifier
    let dirtyFiles: [String]
    let saveState: TabCloseConfirmation.SaveState

    var id: ProjectTabIdentifier { tabID }

    func saving() -> PendingTabClose {
        PendingTabClose(tabID: tabID, dirtyFiles: dirtyFiles, saveState: .saving)
    }

    func failed(_ outcome: SaveAllOutcome) -> PendingTabClose {
        PendingTabClose(tabID: tabID, dirtyFiles: dirtyFiles, saveState: .failed(outcome))
    }
}
