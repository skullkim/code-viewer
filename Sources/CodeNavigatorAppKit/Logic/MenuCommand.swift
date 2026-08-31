import CodeNavigatorContract

/// Every command reachable from the menu bar (design §3 W-9).
public enum MenuCommand: Sendable, Hashable, CaseIterable {
    // 파일
    case openProject
    case openRecentProject
    case closeProject
    case save
    case closeWindow
    // 편집
    case undo
    case redo
    case cut
    case copy
    case paste
    case selectAll
    case toggleInputMode
    case selectVimMode
    case selectStandardMode
    case restartEditSession
    // 이동
    case symbolSearch
    case textSearch
    case goToDefinition
    case showReferences
    case navigateBack
    case navigateForward
    // 보기
    case toggleFileTree
    case togglePanel
    case toggleFullScreen
}
