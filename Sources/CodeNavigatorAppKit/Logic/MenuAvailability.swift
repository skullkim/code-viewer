import CodeNavigatorContract

/// Decides which menu commands are available for the current state.
///
/// The rule that matters is REQ-010 AC-5: the standard text-editing commands are live only
/// in standard mode. In Vim mode `u`, `y` and `p` already do that work, and letting ⌘Z
/// reach the same buffer by a second route splits the undo history — the single-path
/// principle INV-3 states for files, applied to edits.
///
/// The second rule is that a dead edit session must not disable navigation. The index is
/// independent of Neovim (design §2 F-9), and greying out search would tell the user the
/// whole application had died when only editing had.
public struct MenuAvailability: Sendable, Hashable {
    public let inputMode: InputMode
    public let sessionState: EditorSessionState
    public let hasOpenProject: Bool

    public init(inputMode: InputMode, sessionState: EditorSessionState, hasOpenProject: Bool) {
        self.inputMode = inputMode
        self.sessionState = sessionState
        self.hasOpenProject = hasOpenProject
    }

    private var isSessionRunning: Bool {
        sessionState == .connected
    }

    public func isEnabled(_ command: MenuCommand) -> Bool {
        switch command {
        // Always available: the way in, and the window itself.
        case .openProject, .openRecentProject, .closeWindow, .toggleFullScreen:
            return true

        case .closeProject, .toggleFileTree:
            return hasOpenProject

        // Answered from the index, which outlives the edit session.
        case .symbolSearch, .textSearch, .togglePanel:
            return hasOpenProject

        // 렌더는 디스크 사본으로도 그릴 수 있으므로 세션이 죽어도 살아 있다(02b F-9와 같은
        // 이유). **파일이 렌더 가능한지는 여기서 답하지 않는다** — 그 판정에는 현재 파일이
        // 필요하고, 이 타입은 파일을 모른다. 툴바가 `RenderViewState` 와 함께 좁힌다.
        case .toggleRenderView:
            return hasOpenProject

        // Start from the cursor, so they need a live session as well as an index.
        case .goToDefinition, .showReferences, .navigateBack, .navigateForward:
            return hasOpenProject && isSessionRunning

        // Writing is delegated to Neovim's `:w` in both modes (INV-3), so it needs the
        // session but not a particular input mode.
        case .save:
            return isSessionRunning

        // The heart of REQ-010 AC-5.
        case .undo, .redo, .cut, .copy, .paste, .selectAll:
            return isSessionRunning && inputMode == .standard

        case .toggleInputMode, .selectVimMode, .selectStandardMode:
            return isSessionRunning

        case .restartEditSession:
            return !isSessionRunning
        }
    }

    /// Whether the command carries a tick, for the mode items (design §3 W-9).
    public func isChecked(_ command: MenuCommand) -> Bool {
        switch command {
        case .selectVimMode: return inputMode == .vim
        case .selectStandardMode: return inputMode == .standard
        default: return false
        }
    }
}
