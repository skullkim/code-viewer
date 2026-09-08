import CodeNavigatorContract
import AppKit

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
    public let appearance: AppearancePreference
    public let debugConnection: DebugConnection
    public let exceptionRule: ExceptionBreakpointRule
    public let capabilities: DebugCapabilities
    /// 지금 무언가 돌고 있는지. 정지를 켜 둘지 정한다.
    public let isRunning: Bool
    /// 지금 고른 실행 설정을 디버그로 띄울 수 있는지.
    ///
    /// `npm run dev` 같은 명령에는 JDWP 로 못 붙는다. 버튼을 켜 두면 사용자는 눌러서
    /// 30초를 기다린 뒤 "붙지 못했습니다" 만 본다 — 이유는 화면 어디에도 없다.
    public let canDebugSelected: Bool

    public init(
        inputMode: InputMode,
        sessionState: EditorSessionState,
        hasOpenProject: Bool,
        appearance: AppearancePreference = .system,
        debugConnection: DebugConnection = .detached,
        exceptionRule: ExceptionBreakpointRule = .off,
        capabilities: DebugCapabilities = .none,
        isRunning: Bool = false,
        canDebugSelected: Bool = true
    ) {
        self.inputMode = inputMode
        self.sessionState = sessionState
        self.hasOpenProject = hasOpenProject
        self.appearance = appearance
        self.debugConnection = debugConnection
        self.exceptionRule = exceptionRule
        self.capabilities = capabilities
        self.isRunning = isRunning
        self.canDebugSelected = canDebugSelected
    }

    private var isSessionRunning: Bool {
        sessionState == .connected
    }

    public func isEnabled(_ command: MenuCommand) -> Bool {
        switch command {
        // Always available: the way in, the window itself, and how it is lit. 화면을 못
        // 읽겠다는 것은 프로젝트가 열렸는지와 무관한 문제다 — 빈 창에서도 바꿀 수 있어야 한다.
        case .openProject, .openRecentProject, .closeWindow, .toggleFullScreen,
             .selectAppearanceSystem, .selectAppearanceLight, .selectAppearanceDark:
            return true

        // 디버그 패널은 붙어 있지 않을 때도 열 수 있다 — 어떻게 붙는지 거기 적혀 있다.
        case .toggleDebugPanel:
            return hasOpenProject

        // 붙어 있어야 예외 규칙을 걸 수 있다 — JVM 이 없으면 걸 곳이 없다.
        case .toggleBreakOnUncaughtException, .toggleBreakOnCaughtException:
            return debugConnection.isAttached

        // 실행은 프로젝트가 있어야 한다 — 어디서 돌릴지가 없으면 돌릴 수 없다.
        case .runSelected, .openTerminal, .editRunConfigurations:
            return hasOpenProject

        case .debugSelected:
            return hasOpenProject && canDebugSelected

        case .stopRun:
            return isRunning

        case .attachDebugger:
            return hasOpenProject && !debugConnection.isAttached

        case .detachDebugger:
            return debugConnection.isAttached

        // 브레이크포인트는 붙어 있어야 걸 수 있다. JVM 이 없으면 걸 곳이 없다.
        case .toggleBreakpoint, .editBreakpointCondition, .toggleFieldWatch:
            return debugConnection.isAttached && isSessionRunning

        // 멈춰 있을 때만 풀 수 있다. 달리는 중에 눌러도 아무 일이 없는 항목은 켜 두지 않는다.
        // 멈춰 있을 때만 걸을 수 있다. 달리는 중에 눌러도 아무 일이 없는 항목은 켜 두지 않는다.
        // 멈춰 있을 때만 걸을 수 있고, 물어볼 수 있다.
        case .resumeDebuggee, .stepOver, .stepInto, .stepOut, .evaluateExpression, .addWatch:
            return debugConnection.isStopped

        // 이 JVM 이 핫스왑을 안 받으면 켜 두지 않는다 — 눌러 보고 알 수 없는 오류를 보느니
        // 회색으로 있는 편이 낫다.
        case .hotSwapCurrentFile:
            return debugConnection.isAttached && capabilities.canRedefineClasses

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
        case .selectAppearanceSystem: return appearance == .system
        case .selectAppearanceLight: return appearance == .light
        case .selectAppearanceDark: return appearance == .dark
        case .toggleBreakOnUncaughtException: return exceptionRule.breakOnUncaught
        case .toggleBreakOnCaughtException: return exceptionRule.breakOnCaught
        default: return false
        }
    }
}
