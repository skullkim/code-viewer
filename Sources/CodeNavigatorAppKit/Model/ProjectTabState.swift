import Foundation
import Observation
import CodeNavigatorContract

/// The application's state for one open tab (ADR-0107, INV-5).
///
/// Named for what it holds rather than for the tab itself, because the engine now has its
/// own `ProjectTab` and the two are different things. The engine's is the *identity* of an
/// open project — canonical root, display name, disambiguator — and it owns that, including
/// the normalisation that decides when two paths are one project. This one holds what only
/// the application knows: the tree the user expanded, the searches they ran, the index
/// state as the tab bar draws it.
///
/// Keeping both under one name would have made "which project is this" answerable two ways,
/// which is the shape of defect this build has closed repeatedly.
///
/// The tab owns its tree and its index rather than reaching into a shared store keyed by
/// project. That is what makes INV-5 ("한 탭에서의 조작은 다른 탭의 상태를 바꾸지 않는다") a
/// property of the shape of the code instead of a rule someone has to remember: there is no
/// path from one tab to another's state to misuse.
///
/// What is *not* here matters as much. Input mode, theme, window size and split ratios are
/// window- or application-wide (02b §1.1), so they stay on `AppModel`. Copying them per tab
/// would leave no answer to "which copy is the real one" when tabs disagree.
@MainActor
@Observable
public final class ProjectTabState: Identifiable {

    /// The canonical identity from `ProjectIdentity.canonical(for:isCaseSensitiveVolume:)`.
    ///
    /// Two paths that name one directory share this, which is what makes REQ-012 AC-5
    /// ("이미 열린 프로젝트를 다시 열면 기존 탭 활성화") decidable without guessing.
    public let id: String

    /// The path as the user chose it — for display, and for reopening after a restart.
    public let rootPath: String
    public let name: String

    /// This tab's tree. A separate instance per tab: sharing one would make a folder
    /// expanded in one project appear expanded in another.
    public let fileTree: FileTreeModel

    public private(set) var indexState: IndexState = .notIndexed
    public private(set) var indexStatistics: IndexStatistics?

    /// Unsaved buffers in this project, for the tab's dirty glyph and the close sheet (W-13).
    public private(set) var dirtyBufferCount = 0

    public init(
        id: String,
        rootPath: String,
        name: String,
        projectSession: ProjectSession,
        editorSession: EditorSession
    ) {
        self.id = id
        self.rootPath = rootPath
        self.name = name
        self.fileTree = FileTreeModel(projectSession: projectSession, editorSession: editorSession)
    }

    public func setIndexState(_ state: IndexState) {
        indexState = state
    }

    public func setIndexStatistics(_ statistics: IndexStatistics?) {
        indexStatistics = statistics
    }

    public func setDirtyBufferCount(_ count: Int) {
        dirtyBufferCount = max(0, count)
    }

    /// What the tab bar draws this tab from (02b §3 W-11).
    public var descriptor: ProjectTabDescriptor {
        ProjectTabDescriptor(
            id: id,
            rootPath: rootPath,
            name: name,
            dirtyBufferCount: dirtyBufferCount,
            indexState: indexState.isWorking
                ? .working(label: indexState.tabProgressLabel)
                : .ready
        )
    }
}

private extension IndexState {
    /// The one line a tab's tooltip shows while indexing.
    ///
    /// Deliberately coarse: the design keeps progress numbers out of a tab and in the
    /// status bar chip (02b §3 W-11), because a row 112pt wide cannot carry them and a
    /// second place showing the same numbers is a second place to drift.
    var tabProgressLabel: String {
        switch self {
        case .indexing, .rescanning:
            return "인덱싱 중"
        case .updating:
            return "인덱스 갱신 중"
        case .notIndexed, .ready:
            return "인덱싱 중"
        }
    }
}
