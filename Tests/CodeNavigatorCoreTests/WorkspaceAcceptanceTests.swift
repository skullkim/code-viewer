import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// The acceptance scenarios, run against the engine the application actually uses.
///
/// `AcceptanceScenarioTests` exercises `CodeNavigatorEngine`, which has **no source callers left**
/// — the application moved to `ProjectWorkspaceEngine` when multiple projects arrived. So those
/// scenarios were green about a path nothing ships. A save-to-reindex wiring bug in the workspace
/// would not have failed a single one of them.
///
/// These are deliberately the same scenarios, not new ones: the point is to prove the behaviour on
/// the live path, and re-deriving them would quietly change what is being claimed.
@Suite("수용 시나리오 — 앱이 실제로 쓰는 경로에서", .serialized)
struct WorkspaceAcceptanceTests {

    private func makeProject() -> TemporaryProjectFixture {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/SymbolIndexHolder.kt", contents: """
        class SymbolIndexHolder {
            fun existingFunction() {}
        }
        """)
        return fixture
    }

    /// SC-3 on the live path. The workspace does its own save routing — one Neovim serves every
    /// project, so the saved path decides which project's index to update — and that routing is
    /// code the old engine never had.
    @Test("SC-3: 편집 후 :w 하면 새 심볼이 검색된다 — 워크스페이스 경로")
    func newSymbolIsSearchableAfterSavingThroughTheWorkspace() async throws {
        let fixture = makeProject()
        let workspace = ProjectWorkspaceEngine(columns: 80, rows: 24)
        let tab = try await workspace.openProject(at: fixture.rootURL)
        let session = try #require(await workspace.session(for: tab.tab.id))

        #expect(await session.definitions(named: "freshlyWrittenFunction").isEmpty)

        let editor = await workspace.editorSession
        try await editor.openFile(atRelativePath: "src/SymbolIndexHolder.kt", line: 3, recordJump: false)
        try await editor.sendKeys("ofun freshlyWrittenFunction() {}<Esc>")
        try await Task.sleep(for: .milliseconds(200))
        try await editor.sendKeys(":write<CR>")

        let deadline = Date().addingTimeInterval(3)
        var found: [SymbolDefinition] = []
        while Date() < deadline {
            found = await session.definitions(named: "freshlyWrittenFunction")
            if !found.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(found.count == 1, "저장이 워크스페이스의 인덱스에 반영되지 않았다")
        #expect(found.first?.path == "src/SymbolIndexHolder.kt")
        await workspace.shutDown()
    }

    /// The routing itself: a save in one project must not touch another's index. The old engine
    /// could not get this wrong because it only ever held one project.
    @Test("한 프로젝트의 저장이 다른 프로젝트의 인덱스를 건드리지 않는다")
    func savingInOneProjectLeavesTheOtherAlone() async throws {
        let alpha = makeProject()
        let beta = makeProject()
        let workspace = ProjectWorkspaceEngine(columns: 80, rows: 24)
        let first = try await workspace.openProject(at: alpha.rootURL)
        let second = try await workspace.openProject(at: beta.rootURL)
        let alphaSession = try #require(await workspace.session(for: first.tab.id))
        let betaSession = try #require(await workspace.session(for: second.tab.id))

        let editor = await workspace.editorSession
        try await editor.openFile(atRelativePath: "src/SymbolIndexHolder.kt", line: 3, recordJump: false)
        try await editor.sendKeys("ofun onlyInBeta() {}<Esc>")
        try await Task.sleep(for: .milliseconds(200))
        try await editor.sendKeys(":write<CR>")

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, await betaSession.definitions(named: "onlyInBeta").isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(await betaSession.definitions(named: "onlyInBeta").isEmpty == false,
                "활성 탭(beta)의 인덱스에 반영되지 않았다")
        #expect(await alphaSession.definitions(named: "onlyInBeta").isEmpty,
                "다른 프로젝트의 인덱스에 새 심볼이 들어갔다 — 경로 라우팅이 틀렸다")
        await workspace.shutDown()
    }
}

/// W-8's promise, on the live path.
///
/// `EditorFailureKeepsIndexTests` asserts this against `CodeNavigatorEngine`, which the app no
/// longer uses — so the promise the overlay makes to the user ("트리·심볼 검색·참조·전문 검색은
/// 계속 사용할 수 있습니다") is unguarded where it actually runs.
@Suite("편집기 없이도 프로젝트가 열린다 — 워크스페이스 경로 (W-8)", .serialized)
struct WorkspaceEditorFailureTests {

    @Test("편집기가 없어도 탭이 열리고 심볼이 검색된다")
    func aMissingEditorStillOpensASearchableTab() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        let workspace = ProjectWorkspaceEngine(
            columns: 80, rows: 24, editorExecutableOverridePath: "/nonexistent/nvim"
        )

        // 편집기 실패가 열기를 실패시키면 앱이 성공한 인덱스를 통째로 버린다.
        let tab = try await workspace.openProject(at: fixture.rootURL)
        let session = try #require(await workspace.session(for: tab.tab.id))

        #expect(await session.definitions(named: "Application").isEmpty == false)
        #expect(await workspace.tabs().count == 1)

        // 실패는 사라지지 않는다 — 편집기 상태가 들고 있고 W-8 오버레이가 그것을 읽는다.
        guard case .startupFailed = await workspace.editorSession.state() else {
            Issue.record("편집기 실패가 상태에 없다: \(await workspace.editorSession.state())")
            return
        }
        await workspace.shutDown()
    }

    @Test("편집기가 없어도 두 번째 프로젝트가 열린다")
    func aSecondProjectOpensWithoutAnEditor() async throws {
        let alpha = TemporaryProjectFixture()
        alpha.write("src/Alpha.kt", contents: "class AlphaService")
        let beta = TemporaryProjectFixture()
        beta.write("src/Beta.kt", contents: "class BetaService")
        let workspace = ProjectWorkspaceEngine(
            columns: 80, rows: 24, editorExecutableOverridePath: "/nonexistent/nvim"
        )

        let first = try await workspace.openProject(at: alpha.rootURL)
        let second = try await workspace.openProject(at: beta.rootURL)

        #expect(await workspace.tabs().count == 2)
        #expect(await workspace.session(for: first.tab.id)?.definitions(named: "AlphaService").isEmpty == false)
        #expect(await workspace.session(for: second.tab.id)?.definitions(named: "BetaService").isEmpty == false)
        await workspace.shutDown()
    }
}
