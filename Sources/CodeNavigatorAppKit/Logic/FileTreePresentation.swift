import CodeNavigatorContract

/// One visible row of the file tree.
///
/// The tree is a hierarchy, but a list is what gets drawn and what the arrow keys walk,
/// so the hierarchy is flattened once here and every later question — what is below this
/// row, what is its parent — is answered by index arithmetic rather than by another walk.
public struct FileTreeRow: Sendable, Hashable, Identifiable {
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let depth: Int
    public let isExpanded: Bool
    public let isLoadingChildren: Bool
    public let isSelected: Bool
    public let isCurrentFile: Bool
    public let isDirty: Bool

    /// `DirectoryEntry.path` is project-relative and unique, which is what the engine
    /// already guarantees for tree rows.
    public var id: String { path }
}

/// A key press the tree interprets itself (design §4.5: 트리는 ↑↓/←→/Enter).
public enum FileTreeKey: Sendable, Hashable, CaseIterable {
    case up
    case down
    case left
    case right
    case enter
}

/// What a key press asks of the tree.
///
/// The presentation decides *what should happen* and the model performs it. Expanding a
/// directory may need a fetch (REQ-003 AC-1), and a pure function cannot fetch — but it
/// can say that a fetch is what this key means.
public enum FileTreeAction: Sendable, Hashable {
    case select(path: String)
    case expand(path: String)
    case collapse(path: String)
    case openFile(path: String)
    case none
}

/// Everything the file tree draws (design §3 W-1, REQ-003).
public struct FileTreePresentation: Sendable {
    public let title: String?
    public let rows: [FileTreeRow]
    public let showsSkeleton: Bool
    public let skeletonRowCount: Int
}

extension FileTreePresentation {

    /// The relative path that names the project root in `directoryEntries(atRelativePath:)`.
    public static let rootPath = ""

    /// Design §3 W-1: the loading tree shows six skeleton rows.
    static let loadingSkeletonRowCount = 6

    /// The inputs the row builder carries through the recursion.
    ///
    /// Passing eight arguments down every level obscures which of them the recursion
    /// actually varies — only the parent path and the depth do.
    private struct RowContext {
        let childrenByPath: [String: [DirectoryEntry]]
        let expandedPaths: Set<String>
        let loadingPaths: Set<String>
        let selectedPath: String?
        let currentFilePath: String?
        let isCurrentFileDirty: Bool
    }

    public static func make(
        projectName: String?,
        childrenByPath: [String: [DirectoryEntry]],
        expandedPaths: Set<String>,
        loadingPaths: Set<String>,
        selectedPath: String?,
        currentFileAbsolutePath: String?,
        projectRootPath: String?,
        isCurrentFileDirty: Bool
    ) -> FileTreePresentation {
        guard !loadingPaths.contains(rootPath) else {
            // While the root is being read there is nothing truthful to list, so the
            // skeleton holds the space instead of an empty tree that reads as "no files".
            return FileTreePresentation(
                title: projectName,
                rows: [],
                showsSkeleton: true,
                skeletonRowCount: loadingSkeletonRowCount
            )
        }

        let context = RowContext(
            childrenByPath: childrenByPath,
            expandedPaths: expandedPaths,
            loadingPaths: loadingPaths,
            selectedPath: selectedPath,
            currentFilePath: relativeCurrentFilePath(
                absolutePath: currentFileAbsolutePath,
                projectRootPath: projectRootPath
            ),
            isCurrentFileDirty: isCurrentFileDirty
        )

        var rows: [FileTreeRow] = []
        appendRows(into: &rows, parentPath: rootPath, depth: 0, context: context)

        return FileTreePresentation(
            title: projectName,
            rows: rows,
            showsSkeleton: false,
            skeletonRowCount: loadingSkeletonRowCount
        )
    }

    /// The next thing to do, given a key and where the selection currently sits.
    public static func action(
        for key: FileTreeKey,
        rows: [FileTreeRow],
        selectedPath: String?
    ) -> FileTreeAction {
        guard let firstRow = rows.first else {
            return .none
        }

        guard let index = rows.firstIndex(where: { $0.path == selectedPath }) else {
            // Either nothing is selected yet, or a collapse took the selected row away.
            // Moving picks up at the top; acting on nothing does nothing.
            switch key {
            case .up, .down:
                return .select(path: firstRow.path)
            case .left, .right, .enter:
                return .none
            }
        }

        let row = rows[index]
        switch key {
        case .up:
            // Deliberately no wrapping. A hierarchy has a top, and jumping from it to the
            // bottom loses the user's place in a way a flat list would not.
            return index > 0 ? .select(path: rows[index - 1].path) : .none

        case .down:
            return index + 1 < rows.count ? .select(path: rows[index + 1].path) : .none

        case .right:
            return rightArrowAction(row: row, rows: rows, index: index)

        case .left:
            return leftArrowAction(row: row, rows: rows, index: index)

        case .enter:
            guard row.isDirectory else {
                return .openFile(path: row.path)
            }
            return row.isExpanded ? .collapse(path: row.path) : .expand(path: row.path)
        }
    }

    // MARK: 행 만들기

    private static func appendRows(
        into rows: inout [FileTreeRow],
        parentPath: String,
        depth: Int,
        context: RowContext
    ) {
        for entry in context.childrenByPath[parentPath] ?? [] {
            let isExpanded = entry.isDirectory && context.expandedPaths.contains(entry.path)
            let hasLoadedChildren = context.childrenByPath[entry.path] != nil
            let isCurrentFile = !entry.isDirectory && entry.path == context.currentFilePath

            rows.append(FileTreeRow(
                name: entry.name,
                path: entry.path,
                isDirectory: entry.isDirectory,
                depth: depth,
                isExpanded: isExpanded,
                // An expanded directory with nothing under it is ambiguous: still loading,
                // or genuinely empty. Saying which is the difference between patience and
                // a wrong conclusion.
                isLoadingChildren: isExpanded && !hasLoadedChildren && context.loadingPaths.contains(entry.path),
                isSelected: entry.path == context.selectedPath,
                isCurrentFile: isCurrentFile,
                // Only one buffer is open, so only its row can be dirty.
                isDirty: isCurrentFile && context.isCurrentFileDirty
            ))

            guard isExpanded else {
                continue
            }
            appendRows(into: &rows, parentPath: entry.path, depth: depth + 1, context: context)
        }
    }

    /// The tree's own form of the path the edit session reports.
    ///
    /// The two sides name the same file differently — absolute against project-relative,
    /// and macOS adds a /private prefix to some of them. Comparing the strings as they
    /// arrive fails silently: the highlight simply never appears (REQ-003 AC-3, 03 §3.1).
    private static func relativeCurrentFilePath(absolutePath: String?, projectRootPath: String?) -> String? {
        guard let absolutePath, let projectRootPath else {
            return nil
        }
        return PathDisplay.relativePath(ofAbsolutePath: absolutePath, projectRoot: projectRootPath)
    }

    // MARK: 좌우 화살표

    private static func rightArrowAction(row: FileTreeRow, rows: [FileTreeRow], index: Int) -> FileTreeAction {
        guard row.isDirectory else {
            return .none
        }
        guard row.isExpanded else {
            return .expand(path: row.path)
        }

        // Already open, so the arrow steps inside. A directory that is empty or still
        // loading has no child row to step into, and the selection stays where it is.
        let childIndex = index + 1
        guard childIndex < rows.count, rows[childIndex].depth == row.depth + 1 else {
            return .none
        }
        return .select(path: rows[childIndex].path)
    }

    private static func leftArrowAction(row: FileTreeRow, rows: [FileTreeRow], index: Int) -> FileTreeAction {
        if row.isDirectory && row.isExpanded {
            return .collapse(path: row.path)
        }
        guard let parentIndex = parentIndex(of: index, in: rows) else {
            return .none
        }
        return .select(path: rows[parentIndex].path)
    }

    /// The nearest row above this one that sits a level shallower.
    private static func parentIndex(of index: Int, in rows: [FileTreeRow]) -> Int? {
        let parentDepth = rows[index].depth - 1
        guard parentDepth >= 0 else {
            return nil
        }
        return rows[..<index].lastIndex { $0.depth == parentDepth }
    }
}
