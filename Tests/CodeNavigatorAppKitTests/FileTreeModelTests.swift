import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// REQ-003 AC-1 is a statement about engine traffic, not about pixels: a directory's
/// children are fetched when it opens and not before. That can only be checked by counting
/// what the engine was asked, so the model is driven directly here.
@MainActor
@Suite("FileTreeModel — 지연 로드와 파일 열기 (REQ-003·001)")
struct FileTreeModelTests {

    private let root = "/Users/dev/repo"

    private func makeModel() -> (FileTreeModel, RecordingProjectSession, FakeEditorSession) {
        let project = RecordingProjectSession()
        project.directoryEntriesByPath = [
            "": [
                DirectoryEntry(name: "Sources", path: "Sources", isDirectory: true),
                DirectoryEntry(name: "Package.swift", path: "Package.swift", isDirectory: false),
            ],
            "Sources": [
                DirectoryEntry(name: "App.swift", path: "Sources/App.swift", isDirectory: false),
            ],
        ]
        let editor = FakeEditorSession()
        return (FileTreeModel(projectSession: project, editorSession: editor), project, editor)
    }

    private func loadedModel() async -> (FileTreeModel, RecordingProjectSession, FakeEditorSession) {
        let (model, project, editor) = makeModel()
        await model.loadProject(name: "repo", rootPath: root)
        return (model, project, editor)
    }

    // MARK: 지연 로드 (AC-1)

    @Test("프로젝트를 열면 루트만 읽는다")
    func openingAProjectReadsOnlyTheRoot() async {
        let (model, project, _) = makeModel()

        await model.loadProject(name: "repo", rootPath: root)

        #expect(project.requestedDirectoryPaths == [FileTreePresentation.rootPath])
        #expect(model.presentation.rows.map(\.path) == ["Sources", "Package.swift"])
    }

    @Test("디렉토리를 펼칠 때 비로소 그 자식을 읽는다")
    func childrenAreReadOnlyWhenTheDirectoryOpens() async {
        let (model, project, _) = await loadedModel()
        #expect(project.directoryRequestCount(for: "Sources") == 0)

        await model.perform(.expand(path: "Sources"))

        #expect(project.directoryRequestCount(for: "Sources") == 1)
        #expect(model.presentation.rows.map(\.path) == ["Sources", "Sources/App.swift", "Package.swift"])
    }

    @Test("접었다 다시 펼쳐도 엔진을 다시 부르지 않는다")
    func reopeningADirectoryUsesWhatWasAlreadyRead() async {
        let (model, project, _) = await loadedModel()

        await model.perform(.expand(path: "Sources"))
        await model.perform(.collapse(path: "Sources"))
        await model.perform(.expand(path: "Sources"))

        #expect(project.directoryRequestCount(for: "Sources") == 1)
    }

    @Test("한 디렉토리를 못 읽어도 트리는 남는다")
    func aFailedListingLeavesTheRestOfTheTree() async {
        // REQ-NF-004의 정신: 한 곳의 실패가 화면 전체를 가져가지 않는다. 실패한
        // 디렉토리는 다시 접히므로, 다음 시도가 재시도가 된다.
        let (model, project, _) = await loadedModel()
        project.failingDirectoryPaths = ["Sources"]

        await model.perform(.expand(path: "Sources"))

        #expect(model.presentation.rows.map(\.path) == ["Sources", "Package.swift"])
        #expect(!model.presentation.rows[0].isExpanded)
    }

    // MARK: 선택과 열기

    @Test("파일을 열면 에디터에 상대 경로가 전달된다")
    func openingAFileHandsTheEditorTheRelativePath() async {
        let (model, _, editor) = await loadedModel()

        await model.perform(.openFile(path: "Package.swift"))

        #expect(editor.openedFiles.map(\.path) == ["Package.swift"])
        #expect(model.selectedPath == "Package.swift")
    }

    @Test("트리에서 연 파일도 점프 목록에 남는다")
    func openingFromTheTreeRecordsAJump() async {
        // ⌃O로 직전 위치에 돌아갈 수 있어야 한다 — 트리 클릭이 되돌아갈 길을 지운다면
        // 그건 편집 흐름을 끊는 것이다.
        let (model, _, editor) = await loadedModel()

        await model.perform(.openFile(path: "Package.swift"))

        #expect(editor.openedFiles.first?.recordJump == true)
    }

    @Test("디렉토리를 펼쳐도 파일이 열리지 않는다")
    func expandingADirectoryOpensNothing() async {
        let (model, _, editor) = await loadedModel()

        await model.perform(.expand(path: "Sources"))

        #expect(editor.openedFiles.isEmpty)
    }

    // MARK: 키보드 (AC-1 + 02 §4.5)

    @Test("아래 화살표가 선택을 옮긴다")
    func theDownArrowMovesTheSelection() async {
        let (model, _, _) = await loadedModel()

        await model.handle(key: .down)

        #expect(model.selectedPath == "Sources")
    }

    @Test("엔터가 디렉토리를 펼치고 자식을 읽어 온다")
    func enterExpandsAndLoads() async {
        let (model, project, _) = await loadedModel()

        await model.handle(key: .down)
        await model.handle(key: .enter)

        #expect(project.directoryRequestCount(for: "Sources") == 1)
        #expect(model.presentation.rows.count == 3)
    }

    @Test("엔터가 선택된 파일을 연다")
    func enterOpensTheSelectedFile() async {
        let (model, _, editor) = await loadedModel()

        await model.handle(key: .down)
        await model.handle(key: .down)
        await model.handle(key: .enter)

        #expect(editor.openedFiles.map(\.path) == ["Package.swift"])
    }

    // MARK: 프로젝트 전환 (REQ-001 AC-2)

    @Test("프로젝트를 바꾸면 이전 트리가 남지 않는다")
    func switchingProjectsReplacesTheTree() async {
        let (model, project, _) = await loadedModel()
        await model.perform(.expand(path: "Sources"))
        await model.perform(.openFile(path: "Package.swift"))

        project.directoryEntriesByPath = ["": [DirectoryEntry(name: "src", path: "src", isDirectory: true)]]
        await model.loadProject(name: "other", rootPath: "/Users/dev/other")

        #expect(model.presentation.title == "other")
        #expect(model.presentation.rows.map(\.path) == ["src"])
        #expect(model.selectedPath == nil)
    }

    // MARK: 현재 파일 강조 (AC-3)

    @Test("에디터가 보고한 파일이 트리에서 강조된다")
    func theEditorsFileIsHighlightedInTheTree() async {
        let (model, _, _) = await loadedModel()
        await model.perform(.expand(path: "Sources"))

        model.updateCurrentFile(absolutePath: "\(root)/Sources/App.swift", isDirty: true)

        let highlighted = model.presentation.rows.filter(\.isCurrentFile)
        #expect(highlighted.map(\.path) == ["Sources/App.swift"])
        #expect(highlighted.first?.isDirty == true)
    }
}
