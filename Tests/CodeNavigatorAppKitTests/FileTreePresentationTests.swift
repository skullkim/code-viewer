import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// REQ-003. Three acceptance criteria, and the one that fails quietly is AC-3: the edit
/// session reports absolute paths while the tree reports project-relative ones, so a
/// highlight that never appears looks like a styling omission rather than a path bug.
/// Those cases are tested here rather than left to the view.
@Suite("FileTreePresentation — 파일 트리 (REQ-003)")
struct FileTreePresentationTests {

    private let root = "/Users/dev/repo"

    private func directory(_ name: String, _ path: String) -> DirectoryEntry {
        DirectoryEntry(name: name, path: path, isDirectory: true)
    }

    private func file(_ name: String, _ path: String) -> DirectoryEntry {
        DirectoryEntry(name: name, path: path, isDirectory: false)
    }

    /// The shape used by most cases: Sources/ holding two files, plus a top-level file.
    private var sampleChildren: [String: [DirectoryEntry]] {
        [
            "": [directory("Sources", "Sources"), file("Package.swift", "Package.swift")],
            "Sources": [file("App.swift", "Sources/App.swift"), file("Parser.swift", "Sources/Parser.swift")],
        ]
    }

    private func make(
        children: [String: [DirectoryEntry]]? = nil,
        expanded: Set<String> = [],
        loading: Set<String> = [],
        selected: String? = nil,
        currentFile: String? = nil,
        projectRoot: String? = nil,
        isDirty: Bool = false
    ) -> FileTreePresentation {
        FileTreePresentation.make(
            projectName: "repo",
            childrenByPath: children ?? sampleChildren,
            expandedPaths: expanded,
            loadingPaths: loading,
            selectedPath: selected,
            currentFileAbsolutePath: currentFile,
            projectRootPath: projectRoot ?? root,
            isCurrentFileDirty: isDirty
        )
    }

    // MARK: 구조와 지연 로드 (AC-1)

    @Test("루트를 읽는 동안에는 스켈레톤만 보인다")
    func theRootLoadingStateShowsSkeletonRows() {
        // 02 §3 W-1: 트리 로딩 = 스켈레톤 행 6개.
        let tree = make(children: [:], loading: [FileTreePresentation.rootPath])

        #expect(tree.showsSkeleton)
        #expect(tree.skeletonRowCount == 6)
        #expect(tree.rows.isEmpty)
    }

    @Test("루트 항목은 깊이 0으로 나온다")
    func rootEntriesAreListedAtDepthZero() {
        let tree = make()

        #expect(tree.rows.map(\.path) == ["Sources", "Package.swift"])
        #expect(tree.rows.allSatisfy { $0.depth == 0 })
        #expect(!tree.showsSkeleton)
    }

    @Test("접힌 디렉토리의 자식은 이미 받아 뒀어도 보이지 않는다")
    func aCollapsedDirectoryHidesChildrenItAlreadyHas() {
        // AC-1의 지연 로드는 화면에도 지연이어야 한다. 캐시가 있다고 펼쳐 버리면
        // 사용자가 접은 것이 다시 열린다.
        let tree = make(expanded: [])

        #expect(tree.rows.count == 2)
        #expect(!tree.rows[0].isExpanded)
    }

    @Test("펼친 디렉토리의 자식이 바로 아래에 한 단계 들여쓰여 붙는다")
    func anExpandedDirectoryInlinesItsChildren() {
        let tree = make(expanded: ["Sources"])

        #expect(tree.rows.map(\.path) == ["Sources", "Sources/App.swift", "Sources/Parser.swift", "Package.swift"])
        #expect(tree.rows.map(\.depth) == [0, 1, 1, 0])
        #expect(tree.rows[0].isExpanded)
    }

    @Test("아직 자식을 못 받은 펼친 디렉토리는 로딩 중으로 표시된다")
    func anExpandedDirectoryAwaitingChildrenSaysSo() {
        // 지연 로드가 도는 동안 아무 표시가 없으면 "빈 디렉토리"와 구별되지 않는다.
        let tree = make(
            children: ["": [directory("Sources", "Sources")]],
            expanded: ["Sources"],
            loading: ["Sources"]
        )

        #expect(tree.rows.count == 1)
        #expect(tree.rows[0].isLoadingChildren)
    }

    @Test("빈 루트는 행 없이 그린다")
    func anEmptyRootProducesNoRows() {
        // 02 §3 W-1에 "프로젝트는 열렸는데 항목 0건" 상태 문구가 없다. 지어내지 않고
        // 행 0개로 둔다 — 문구가 정해지면 여기에 기대값을 추가한다.
        let tree = make(children: ["": []])

        #expect(tree.rows.isEmpty)
        #expect(!tree.showsSkeleton)
    }

    @Test("트리 제목은 프로젝트 이름이다")
    func theTitleIsTheProjectName() {
        #expect(make().title == "repo")
    }

    // MARK: 현재 파일 강조 (AC-3)

    @Test("현재 편집 중인 파일이 강조된다")
    func theFileBeingEditedIsHighlighted() {
        let tree = make(expanded: ["Sources"], currentFile: "/Users/dev/repo/Sources/App.swift")

        let highlighted = tree.rows.filter(\.isCurrentFile).map(\.path)
        #expect(highlighted == ["Sources/App.swift"])
    }

    @Test("/private 접두가 붙어도 강조가 살아난다")
    func theHighlightSurvivesThePrivatePrefix() {
        // macOS는 같은 파일을 /var 와 /private/var 두 이름으로 보고한다. 문자열 비교만
        // 하면 강조가 조용히 사라지고, 그 실패는 에러를 남기지 않는다 (03 §3.1).
        let tree = FileTreePresentation.make(
            projectName: "repo",
            childrenByPath: ["": [file("App.swift", "App.swift")]],
            expandedPaths: [],
            loadingPaths: [],
            selectedPath: nil,
            currentFileAbsolutePath: "/private/var/repo/App.swift",
            projectRootPath: "/var/repo",
            isCurrentFileDirty: false
        )

        #expect(tree.rows[0].isCurrentFile)
    }

    @Test("프로젝트 밖 파일을 편집 중이면 아무 행도 강조하지 않는다")
    func aFileOutsideTheProjectHighlightsNothing() {
        let tree = make(expanded: ["Sources"], currentFile: "/etc/hosts")

        // 행이 있는지 먼저 묻는다. `allSatisfy` 는 **빈 집합에서 참**이라, 트리가 아예
        // 비어 있으면 "아무 행도 강조 안 한다"가 저절로 통과한다 — 그건 이 테스트가
        // 재려던 것이 아니다.
        #expect(!tree.rows.isEmpty, "강조할 행이 없으면 이 단언은 아무것도 재지 않는다")
        #expect(tree.rows.allSatisfy { !$0.isCurrentFile })
    }

    @Test("더티 표시는 현재 파일 행에만 붙는다")
    func theDirtyIndicatorMarksOnlyTheCurrentFile() {
        let tree = make(
            expanded: ["Sources"],
            currentFile: "/Users/dev/repo/Sources/App.swift",
            isDirty: true
        )

        #expect(tree.rows.filter(\.isDirty).map(\.path) == ["Sources/App.swift"])
    }

    @Test("깨끗한 버퍼는 더티 표시를 만들지 않는다")
    func aCleanBufferShowsNoDirtyIndicator() {
        let tree = make(
            expanded: ["Sources"],
            currentFile: "/Users/dev/repo/Sources/App.swift",
            isDirty: false
        )

        #expect(!tree.rows.isEmpty, "행이 없으면 '더티 표시가 없다'가 저절로 참이 된다")
        #expect(tree.rows.allSatisfy { !$0.isDirty })
    }

    @Test("선택된 행만 선택 표시를 갖는다")
    func onlyTheSelectedRowIsMarkedSelected() {
        let tree = make(expanded: ["Sources"], selected: "Sources/Parser.swift")

        #expect(tree.rows.filter(\.isSelected).map(\.path) == ["Sources/Parser.swift"])
    }

    // MARK: 키보드 조작 (02 §4.5 — 트리는 ↑↓←→Enter)

    private func expandedRows() -> [FileTreeRow] {
        make(expanded: ["Sources"]).rows
    }

    @Test("아래 화살표는 다음 보이는 행으로 내려간다")
    func theDownArrowMovesToTheNextVisibleRow() {
        let action = FileTreePresentation.action(for: .down, rows: expandedRows(), selectedPath: "Sources")
        #expect(action == .select(path: "Sources/App.swift"))
    }

    @Test("마지막 행에서 아래로 더 가지 않는다")
    func theSelectionDoesNotWrapPastTheLastRow() {
        // 파일 트리는 목록이 아니라 계층이다. 끝에서 처음으로 튀면 어디에 있었는지를 잃는다.
        let action = FileTreePresentation.action(for: .down, rows: expandedRows(), selectedPath: "Package.swift")
        #expect(action == .none)
    }

    @Test("위 화살표는 이전 행으로 올라가고 첫 행에서 멈춘다")
    func theUpArrowMovesBackAndStopsAtTheTop() {
        let rows = expandedRows()
        #expect(FileTreePresentation.action(for: .up, rows: rows, selectedPath: "Package.swift")
            == .select(path: "Sources/Parser.swift"))
        #expect(FileTreePresentation.action(for: .up, rows: rows, selectedPath: "Sources") == .none)
    }

    @Test("선택이 없으면 방향키가 첫 행을 고른다")
    func anArrowKeyWithNoSelectionPicksTheFirstRow() {
        let rows = expandedRows()
        #expect(FileTreePresentation.action(for: .down, rows: rows, selectedPath: nil) == .select(path: "Sources"))
        #expect(FileTreePresentation.action(for: .up, rows: rows, selectedPath: nil) == .select(path: "Sources"))
    }

    @Test("오른쪽 화살표는 접힌 디렉토리를 펼친다")
    func theRightArrowExpandsACollapsedDirectory() {
        let rows = make(expanded: []).rows
        #expect(FileTreePresentation.action(for: .right, rows: rows, selectedPath: "Sources") == .expand(path: "Sources"))
    }

    @Test("이미 펼친 디렉토리에서 오른쪽은 첫 자식으로 들어간다")
    func theRightArrowEntersAnExpandedDirectory() {
        let action = FileTreePresentation.action(for: .right, rows: expandedRows(), selectedPath: "Sources")
        #expect(action == .select(path: "Sources/App.swift"))
    }

    @Test("파일에서 오른쪽은 아무 일도 하지 않는다")
    func theRightArrowDoesNothingOnAFile() {
        let action = FileTreePresentation.action(for: .right, rows: expandedRows(), selectedPath: "Package.swift")
        #expect(action == .none)
    }

    @Test("왼쪽 화살표는 펼친 디렉토리를 접는다")
    func theLeftArrowCollapsesAnExpandedDirectory() {
        let action = FileTreePresentation.action(for: .left, rows: expandedRows(), selectedPath: "Sources")
        #expect(action == .collapse(path: "Sources"))
    }

    @Test("자식에서 왼쪽은 부모로 올라간다")
    func theLeftArrowMovesToTheParent() {
        let action = FileTreePresentation.action(for: .left, rows: expandedRows(), selectedPath: "Sources/Parser.swift")
        #expect(action == .select(path: "Sources"))
    }

    @Test("최상위에서 왼쪽은 아무 일도 하지 않는다")
    func theLeftArrowStopsAtTheTopLevel() {
        let action = FileTreePresentation.action(for: .left, rows: expandedRows(), selectedPath: "Package.swift")
        #expect(action == .none)
    }

    @Test("엔터는 파일을 연다")
    func enterOpensAFile() {
        // AC-1의 "파일을 선택하면 에디터에 열린다".
        let action = FileTreePresentation.action(for: .enter, rows: expandedRows(), selectedPath: "Package.swift")
        #expect(action == .openFile(path: "Package.swift"))
    }

    @Test("엔터는 디렉토리를 토글한다")
    func enterTogglesADirectory() {
        #expect(FileTreePresentation.action(for: .enter, rows: make(expanded: []).rows, selectedPath: "Sources")
            == .expand(path: "Sources"))
        #expect(FileTreePresentation.action(for: .enter, rows: expandedRows(), selectedPath: "Sources")
            == .collapse(path: "Sources"))
    }

    @Test("행이 없으면 어떤 키도 아무 일을 하지 않는다")
    func noRowsMeansNoAction() {
        for key in FileTreeKey.allCases {
            #expect(FileTreePresentation.action(for: key, rows: [], selectedPath: nil) == .none, "\(key)")
        }
    }
}
