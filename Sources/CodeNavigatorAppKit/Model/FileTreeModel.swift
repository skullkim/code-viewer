import Foundation
import Observation
import CodeNavigatorContract

/// The file tree's state: which directories are open, what has been read, what is selected.
///
/// Kept apart from `AppModel` because the tree is the one part of the shell that talks to
/// the engine on the user's rhythm rather than the engine's — every other panel reacts to
/// a stream, while this one asks for a directory the moment it is opened (REQ-003 AC-1).
///
/// The model performs; `FileTreePresentation` decides. Nothing here interprets a key.
@MainActor
@Observable
public final class FileTreeModel {

    public private(set) var childrenByPath: [String: [DirectoryEntry]] = [:]
    public private(set) var expandedPaths: Set<String> = []
    public private(set) var loadingPaths: Set<String> = []
    public private(set) var selectedPath: String?
    public private(set) var projectName: String?
    public private(set) var projectRootPath: String?
    public private(set) var currentFileAbsolutePath: String?
    public private(set) var isCurrentFileDirty = false

    private let projectSession: ProjectSession
    private let editorSession: EditorSession

    public init(projectSession: ProjectSession, editorSession: EditorSession) {
        self.projectSession = projectSession
        self.editorSession = editorSession
    }

    public var presentation: FileTreePresentation {
        FileTreePresentation.make(
            projectName: projectName,
            childrenByPath: childrenByPath,
            expandedPaths: expandedPaths,
            loadingPaths: loadingPaths,
            selectedPath: selectedPath,
            currentFileAbsolutePath: currentFileAbsolutePath,
            projectRootPath: projectRootPath,
            isCurrentFileDirty: isCurrentFileDirty
        )
    }

    // MARK: 프로젝트

    /// Points the tree at a project, discarding everything read for the previous one.
    ///
    /// REQ-001 AC-2 asks for the tree to *become* the new project's. Keeping the old
    /// expansion set would leave rows from a repository that is no longer open.
    public func loadProject(name: String?, rootPath: String?) async {
        childrenByPath = [:]
        expandedPaths = []
        loadingPaths = []
        selectedPath = nil
        currentFileAbsolutePath = nil
        isCurrentFileDirty = false
        projectName = name
        projectRootPath = rootPath

        guard rootPath != nil else {
            return
        }
        await loadChildren(of: FileTreePresentation.rootPath)
    }

    /// 보이는 디렉토리를 디스크에서 다시 읽는다 — **펼침·선택은 그대로 둔다.**
    ///
    /// `loadProject` 를 다시 부르는 것이 가장 싼 구현인데, 그건 펼침·선택을 **의도적으로**
    /// 버린다(프로젝트 전환용이다). 인덱싱이 끝날 때마다 트리가 접히면 큰 레포에서
    /// 사용자는 트리를 쓸 수 없다 — **고치려던 결함보다 나쁜 수정**이 된다.
    ///
    /// 접힌 디렉토리는 안 읽는다. 보이지 않으므로 지금 맞출 필요가 없고, 펼칠 때 읽힌다.
    public func refreshVisibleDirectories() async {
        guard projectRootPath != nil else {
            return
        }
        for path in [FileTreePresentation.rootPath] + expandedPaths {
            await reloadChildren(of: path)
        }
    }

    /// 캐시를 무시하고 다시 읽는다.
    ///
    /// 실패해도 **있던 목록을 지우지 않는다** — `loadChildren` 은 못 읽은 디렉토리를 접지만,
    /// 그건 사용자가 방금 펼친 경우의 이야기다. 배경 새로고침이 일시적으로 실패했다고
    /// 보고 있던 트리가 사라지면 그게 더 나쁘다.
    private func reloadChildren(of path: String) async {
        guard let entries = try? await projectSession.directoryEntries(atRelativePath: path) else {
            return
        }
        childrenByPath[path] = entries
    }

    /// Tells the tree which file the edit session is showing (REQ-003 AC-3).
    public func updateCurrentFile(absolutePath: String?, isDirty: Bool) {
        currentFileAbsolutePath = absolutePath
        isCurrentFileDirty = isDirty
    }

    // MARK: 입력

    public func handle(key: FileTreeKey) async {
        let action = FileTreePresentation.action(
            for: key,
            rows: presentation.rows,
            selectedPath: selectedPath
        )
        await perform(action)
    }

    public func perform(_ action: FileTreeAction) async {
        switch action {
        case .select(let path):
            selectedPath = path

        case .expand(let path):
            expandedPaths.insert(path)
            await loadChildren(of: path)

        case .collapse(let path):
            expandedPaths.remove(path)

        case .openFile(let path):
            selectedPath = path
            // The jump list is what ⌃O reads, so a file opened from the tree stays part of
            // the trail back (REQ-005 AC-4 keeps the two directions consistent).
            try? await editorSession.openFile(atRelativePath: path, line: nil, recordJump: true)

        case .none:
            break
        }
    }

    // MARK: 지연 로드

    private func loadChildren(of path: String) async {
        guard childrenByPath[path] == nil else {
            // Already read once. Re-reading on every expand would turn a cheap toggle into
            // engine traffic and make the tree flicker through its loading state.
            return
        }

        loadingPaths.insert(path)
        defer { loadingPaths.remove(path) }

        do {
            childrenByPath[path] = try await projectSession.directoryEntries(atRelativePath: path)
        } catch {
            // One unreadable directory is not a reason to lose the tree (REQ-NF-004). It
            // closes again, and nothing is cached, so opening it again is a retry.
            expandedPaths.remove(path)
        }
    }
}
