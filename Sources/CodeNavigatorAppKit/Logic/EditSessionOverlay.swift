import CodeNavigatorContract

/// The one thing the overlay offers to do.
public enum EditSessionOverlayAction: Sendable, Hashable {
    /// Look for Neovim again after the user installs or upgrades it.
    case recheck
    /// Start a fresh Neovim after the old one died.
    case restart
}

/// The card shown over the editor area when there is no usable edit session (design §3 W-8).
///
/// It covers the editor and nothing else. The index does not depend on Neovim, so the tree
/// and the search panels keep working — and the card says so, because a user who reads a
/// dead editor as a dead application will quit instead of carrying on.
public struct EditSessionOverlay: Sendable, Hashable {
    public let title: String
    public let detail: String
    public let reasonText: String?
    public let installCommand: String?
    public let requiredVersionText: String?
    public let searchedPaths: [String]
    public let recoveryNotice: String?
    public let primaryAction: EditSessionOverlayAction?
    public let primaryActionTitle: String?
    /// The editor is dimmed; the tree and panels keep full brightness.
    public let dimsEditorOnly: Bool
    /// Keys aimed at the editor are dropped while this is up, rather than queued into a
    /// session that may never accept them.
    public let blocksKeyInput: Bool
}

extension EditSessionOverlay {

    static let installCommandText = "brew install neovim"
    static let navigationStillWorks = "트리·심볼 검색·참조·전문 검색은 계속 사용할 수 있습니다"
    static let restartRecoveryNotice = "재기동하면 파일은 디스크 내용으로 다시 열립니다"

    /// The overlay for a session state, or nil when the editor is usable.
    public static func make(for state: EditorSessionState) -> EditSessionOverlay? {
        switch state {
        case .connected, .notStarted:
            return nil

        case .connecting:
            return EditSessionOverlay(
                title: "편집 세션 연결 중…",
                detail: "연결 전 키 입력은 전달되지 않습니다 (입력 유실 방지)",
                reasonText: nil,
                installCommand: nil,
                requiredVersionText: nil,
                searchedPaths: [],
                recoveryNotice: nil,
                primaryAction: nil,
                primaryActionTitle: nil,
                dimsEditorOnly: true,
                blocksKeyInput: true
            )

        case .startupFailed(let failure):
            // "Install Neovim" is unhelpful advice to someone who already has it, so a
            // version that is merely too old gets its own wording (REQ-NF-005).
            let isOutdated = failure.foundVersion != nil
            return EditSessionOverlay(
                title: isOutdated ? "Neovim 버전이 너무 낮습니다" : failure.reason,
                detail: navigationStillWorks,
                reasonText: failure.reason,
                installCommand: installCommandText,
                requiredVersionText: versionText(for: failure),
                searchedPaths: failure.searchedPaths,
                recoveryNotice: nil,
                primaryAction: .recheck,
                primaryActionTitle: "다시 확인",
                dimsEditorOnly: true,
                blocksKeyInput: true
            )

        case .disconnected(let reason):
            return EditSessionOverlay(
                title: "편집 세션이 끊겼습니다",
                detail: "키 입력이 전달되지 않습니다. \(navigationStillWorks)",
                reasonText: reason,
                installCommand: nil,
                requiredVersionText: nil,
                searchedPaths: [],
                // Said plainly rather than discovered afterwards: a restart re-opens files
                // from disk, so unsaved buffer contents do not survive it.
                recoveryNotice: restartRecoveryNotice,
                primaryAction: .restart,
                primaryActionTitle: "편집 세션 재기동 ⌃⌘R",
                dimsEditorOnly: true,
                blocksKeyInput: true
            )
        }
    }

    private static func versionText(for failure: EditorStartupFailure) -> String {
        guard let found = failure.foundVersion else {
            return "필요 버전: \(failure.requiredVersion) 이상"
        }
        return "설치된 버전: \(found) · 필요 버전: \(failure.requiredVersion) 이상"
    }
}
