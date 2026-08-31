import CodeNavigatorContract

/// The sheet shown before a tab with unsaved work closes (02b W-13, REQ-012 AC-3).
///
/// It exists because Neovim itself refuses to discard a modified buffer (`E37: No write
/// since last change`). An application that closes the tab anyway would promise something
/// different from the editor it delegates all editing to — and INV-3 says editing happens
/// only through that editor, so being more permissive than it is incoherent.
public struct TabCloseConfirmation: Sendable, Hashable {

    /// What the sheet is waiting on.
    public enum SaveState: Sendable, Hashable {
        case idle
        case saving
        /// Carries the outcome, because "저장 실패" on its own hides how much survived.
        /// Three dirty files where two were written is a different situation from three
        /// where none were, and the difference decides what the user does next.
        case failed(SaveAllOutcome)
    }

    public enum Action: Sendable, Hashable {
        case cancel
        case closeWithoutSaving
        case saveAndClose
    }

    public struct Button: Sendable, Hashable {
        public let label: String
        public let action: Action
        public let isEnabled: Bool
    }

    public let title: String
    public let body: String
    /// At most five, so the sheet cannot grow past the screen on a tab with many buffers.
    public let fileRows: [String]
    /// The files not listed, as `외 {n}건`. The count is the remainder, never the total.
    public let overflowNote: String?
    public let buttons: [Button]
    public let defaultAction: Action
    public let cancelAction: Action
    public let showsSpinner: Bool
    public let failureNote: String?
    /// The files that were refused, so the sheet can mark them rather than listing every
    /// file under one warning.
    public let failedRows: [String]
    /// Why each one was refused. Two files can fail differently — one read-only, one in a
    /// folder that no longer exists — and a single sentence would hide that.
    public let failureReasons: [String: String]

    /// Design §3 W-13: at most five rows before summarising.
    public static let maximumListedFiles = 5

    /// Says how much survived, not just that something did not.
    ///
    /// A user who reads "저장 실패" has to guess whether any of their work reached disk.
    /// Naming the counts answers that, and the counts are only claimed when some files
    /// actually were written — "2개 중 0개 저장됨" reads like a partial success.
    static func note(for outcome: SaveAllOutcome, dirtyCount: Int) -> String {
        guard !outcome.savedPaths.isEmpty else {
            return "⚠ 파일을 저장하지 못했습니다 — 소스 보기에서 확인하세요"
        }
        return "⚠ \(dirtyCount)개 중 \(outcome.savedPaths.count)개만 저장됐습니다 — 나머지는 소스 보기에서 확인하세요"
    }
}

extension TabCloseConfirmation {

    /// Builds the sheet, or nothing when the tab has no unsaved work.
    ///
    /// Returning nil rather than an empty sheet is the point: friction where there is
    /// nothing to lose teaches people to dismiss the sheet unread, and then it fails the one
    /// time it matters.
    public static func make(
        projectName: String,
        dirtyFiles: [String],
        saveState: SaveState = .idle
    ) -> TabCloseConfirmation? {
        guard !dirtyFiles.isEmpty else {
            return nil
        }

        let listed = Array(dirtyFiles.prefix(maximumListedFiles))
        let remainder = dirtyFiles.count - listed.count
        let isBusy = saveState == .saving

        let outcome: SaveAllOutcome?
        if case .failed(let failed) = saveState {
            outcome = failed
        } else {
            outcome = nil
        }

        return TabCloseConfirmation(
            title: "'\(projectName)' 탭에 저장하지 않은 변경이 있습니다",
            body: "저장하지 않고 닫으면 다음 파일의 변경 사항이 사라집니다.",
            fileRows: listed,
            overflowNote: remainder > 0 ? "외 \(remainder)개" : nil,
            buttons: [
                Button(label: "취소", action: .cancel, isEnabled: !isBusy),
                Button(label: "저장하지 않고 닫기", action: .closeWithoutSaving, isEnabled: !isBusy),
                Button(label: "저장 후 닫기", action: .saveAndClose, isEnabled: !isBusy),
            ],
            // The safe action is the default: Enter must not be the key that discards work.
            defaultAction: .saveAndClose,
            cancelAction: .cancel,
            showsSpinner: isBusy,
            // The sheet stays open on failure. Closing after a failed save is precisely the
            // loss it exists to prevent.
            failureNote: outcome.map { note(for: $0, dirtyCount: dirtyFiles.count) },
            failedRows: outcome?.failures.map(\.path) ?? [],
            failureReasons: Dictionary(
                (outcome?.failures ?? []).map { ($0.path, $0.reason) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }
}
