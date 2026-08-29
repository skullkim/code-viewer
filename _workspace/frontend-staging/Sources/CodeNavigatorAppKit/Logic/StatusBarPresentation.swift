import CodeNavigatorContract

/// The colour role a status element carries. Design §4.1 names these; mapping to concrete
/// colours happens in the view so the presentation stays testable without SwiftUI.
public enum StatusTone: Sendable, Hashable {
    case success
    case accent
    case purple
    case warning
    case danger
    /// No tone is specified for this state. Used rather than borrowing another state's
    /// colour, because a wrong colour reads as a confident wrong answer.
    case neutral
}

/// A message shown in the centre of the status bar for a short while.
public struct StatusMessage: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case success
        case error
    }

    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// What the centre of the status bar is currently saying.
public enum StatusCenterRole: Sendable, Hashable {
    case hint
    case success
    case error
    /// An error that stays until the condition clears, rather than timing out.
    case persistentError
}

/// The left segment: which key-interpretation layer is active (REQ-010 AC-3).
public struct InputModeSegment: Sendable, Hashable {
    public let primaryLabel: String
    public let secondaryLabel: String
    public let tone: StatusTone
}

/// A right-hand status chip.
public struct StatusChip: Sendable, Hashable {
    public let label: String
    public let tone: StatusTone
    public let tooltip: String?
    public let progress: IndexProgress?
}

/// Everything the status bar draws, derived from engine state.
///
/// The status bar is the only permanent surface for the input mode and the index state,
/// so what it shows is an acceptance criterion rather than styling. Deriving it here keeps
/// design §3 W-7's table in one place that a test can walk.
public struct StatusBarPresentation: Sendable, Hashable {
    public let modeSegment: InputModeSegment
    public let path: String?
    public let showsDirtyIndicator: Bool
    public let centerText: String
    public let centerRole: StatusCenterRole
    public let cursorText: String?
    public let indexChip: StatusChip
    public let sessionChip: StatusChip
    public let maximumPathCharacters: Int
}

extension StatusBarPresentation {

    /// Shown while the edit session is down, for as long as it is down.
    static let lostSessionNotice = "⚠ 편집 세션이 끊겼습니다 — ⌃⌘R로 재기동"

    /// Shown on any index state that is not `ready`, so a stale answer is never presented
    /// as a current one (INV-1).
    static let staleIndexTooltip = "직전 인덱스로 응답 중 — 결과가 잠시 이전 상태일 수 있습니다"

    /// How many characters of path fit before the middle of the bar is crowded out.
    /// Two budgets rather than a measured width: the bar has a fixed height and a known
    /// font, and a threshold keeps this a pure function.
    private static let widePathBudget = 60
    private static let narrowPathBudget = 32

    public static func make(
        sessionState: EditorSessionState,
        editorStatus: EditorStatus?,
        indexState: IndexState,
        inputMode: InputMode,
        message: StatusMessage?,
        projectRoot: String?,
        layout: ShellLayout
    ) -> StatusBarPresentation {
        let pathBudget = layout.showsStatusBarHint ? widePathBudget : narrowPathBudget
        let center = centerRegion(sessionState: sessionState, message: message, inputMode: inputMode, layout: layout)

        return StatusBarPresentation(
            modeSegment: segment(sessionState: sessionState, editorStatus: editorStatus, inputMode: inputMode),
            path: displayPath(for: editorStatus, projectRoot: projectRoot, budget: pathBudget),
            showsDirtyIndicator: editorStatus?.isDirty ?? false,
            centerText: center.text,
            centerRole: center.role,
            cursorText: cursorText(for: editorStatus, layout: layout),
            indexChip: chip(for: indexState),
            sessionChip: chip(for: sessionState),
            maximumPathCharacters: pathBudget
        )
    }

    // MARK: Left

    private static func segment(
        sessionState: EditorSessionState,
        editorStatus: EditorStatus?,
        inputMode: InputMode
    ) -> InputModeSegment {
        // A dead session outranks the mode: which keys you are typing stops mattering when
        // none of them arrive anywhere.
        if case .disconnected = sessionState {
            return InputModeSegment(primaryLabel: "편집 불가", secondaryLabel: "세션 끊김", tone: .danger)
        }

        guard inputMode == .vim else {
            // Standard mode has no sub-modes (REQ-010 AC-2), and the app status bar is the
            // single authority on the mode (design §11 ruling 2), so Neovim's internal
            // mode is deliberately not surfaced here.
            return InputModeSegment(primaryLabel: "표준", secondaryLabel: "맥 기본 편집", tone: .accent)
        }

        let mode = editorStatus?.mode ?? .normal
        return InputModeSegment(
            primaryLabel: label(for: mode),
            secondaryLabel: "Vim",
            tone: tone(for: mode)
        )
    }

    private static func label(for mode: EditorMode) -> String {
        switch mode {
        case .normal: return "NORMAL"
        case .insert: return "INSERT"
        case .visual: return "VISUAL"
        case .replace: return "REPLACE"
        case .commandLine: return "COMMAND"
        case .terminal: return "TERMINAL"
        case .other(let name): return name.uppercased()
        }
    }

    private static func tone(for mode: EditorMode) -> StatusTone {
        switch mode {
        case .normal: return .success
        case .insert: return .accent
        case .visual: return .purple
        case .commandLine: return .warning
        // The design assigns colours to the four modes it names. Anything else keeps a
        // neutral tone rather than borrowing one of those meanings.
        case .replace, .terminal, .other: return .neutral
        }
    }

    // MARK: Centre

    private static func centerRegion(
        sessionState: EditorSessionState,
        message: StatusMessage?,
        inputMode: InputMode,
        layout: ShellLayout
    ) -> (text: String, role: StatusCenterRole) {
        if case .disconnected = sessionState {
            return (lostSessionNotice, .persistentError)
        }
        if let message {
            return (message.text, message.kind == .success ? .success : .error)
        }
        // The hint is the first thing dropped when space runs short; a message never is.
        guard layout.showsStatusBarHint else {
            return ("", .hint)
        }
        return (hint(for: inputMode), .hint)
    }

    private static func hint(for inputMode: InputMode) -> String {
        switch inputMode {
        case .vim: return ":w 저장 · gd 정의 이동 · ⌃O 뒤로"
        case .standard: return "⌘S 저장 · ⌘B 정의 이동 · ⌘[ 뒤로"
        }
    }

    // MARK: Right

    private static func displayPath(for status: EditorStatus?, projectRoot: String?, budget: Int) -> String? {
        guard let absolutePath = status?.filePath else {
            return nil
        }
        guard let root = projectRoot,
              let relative = PathDisplay.relativePath(ofAbsolutePath: absolutePath, projectRoot: root)
        else {
            // Outside the project, the absolute path is still more useful than nothing.
            return PathDisplay.truncatedFromStart(absolutePath, maximumCharacters: budget)
        }
        return PathDisplay.truncatedFromStart(relative, maximumCharacters: budget)
    }

    private static func cursorText(for status: EditorStatus?, layout: ShellLayout) -> String? {
        guard layout.showsCursorPosition, let status else {
            return nil
        }
        return "\(status.cursorLine):\(status.cursorColumn)"
    }

    private static func chip(for state: IndexState) -> StatusChip {
        let tooltip = state == .ready ? nil : staleIndexTooltip
        switch state {
        case .notIndexed:
            return StatusChip(label: "인덱스 없음", tone: .neutral, tooltip: tooltip, progress: nil)
        case .indexing(let progress):
            return StatusChip(
                label: "인덱싱 중 \(progress.completed)/\(progress.total)",
                tone: .accent, tooltip: tooltip, progress: progress
            )
        case .ready:
            return StatusChip(label: "인덱스 최신", tone: .success, tooltip: nil, progress: nil)
        case .updating:
            return StatusChip(label: "갱신 중", tone: .warning, tooltip: tooltip, progress: nil)
        case .rescanning(let progress):
            return StatusChip(
                label: "전체 재스캔 중 \(progress.completed)/\(progress.total)",
                tone: .warning, tooltip: tooltip, progress: progress
            )
        }
    }

    private static func chip(for state: EditorSessionState) -> StatusChip {
        switch state {
        case .notStarted:
            return StatusChip(label: "편집 세션 미기동", tone: .neutral, tooltip: nil, progress: nil)
        case .connecting:
            return StatusChip(label: "편집 세션 연결 중", tone: .warning, tooltip: nil, progress: nil)
        case .connected:
            return StatusChip(label: "편집 세션 연결됨", tone: .success, tooltip: nil, progress: nil)
        case .disconnected(let reason):
            return StatusChip(label: "편집 세션 끊김", tone: .danger, tooltip: reason, progress: nil)
        }
    }
}
