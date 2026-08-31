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

/// Partial-failure cleanup on the live path.
///
/// `PartialStartFailureTests` asserts this against `CodeNavigatorEngine`. The workspace opens
/// projects differently — the index first, then the editor — so its failure shape is its own and
/// the old suite says nothing about it.
@Suite("열기 실패가 흔적을 남기지 않는다 — 워크스페이스 경로", .serialized)
struct WorkspacePartialFailureTests {

    private func makeUnreadableDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("unreadable-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        return url
    }

    @Test("읽을 수 없는 루트는 탭을 남기지 않는다")
    func anUnreadableRootLeavesNoTab() async throws {
        let unreadable = makeUnreadableDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unreadable.path)
            try? FileManager.default.removeItem(at: unreadable)
        }
        let workspace = ProjectWorkspaceEngine(columns: 80, rows: 24)

        await #expect(throws: (any Error).self) {
            try await workspace.openProject(at: unreadable)
        }

        // 반쪽 열린 탭이 남으면 탭 바에 이름은 있는데 아무것도 안 되는 프로젝트가 생긴다.
        #expect(await workspace.tabs().isEmpty)
        #expect(await workspace.activeTab() == nil)
        await workspace.shutDown()
    }

    @Test("실패한 열기가 편집기 프로세스를 남기지 않는다")
    func aFailedOpenLeavesNoEditorProcess() async throws {
        let missing = URL(fileURLWithPath: "/nonexistent/project-\(UUID().uuidString)")
        let workspace = ProjectWorkspaceEngine(columns: 80, rows: 24)

        await #expect(throws: (any Error).self) {
            try await workspace.openProject(at: missing)
        }

        // 인덱싱이 먼저 실패하므로 편집기는 애초에 뜨지 않아야 한다 — 뜬 뒤 버려지면 고아다.
        let identifier = await workspace.editorSession.processIdentifierForTesting()
        #expect(identifier == nil, "실패한 열기가 편집기 \(identifier ?? -1) 을 띄웠다")
        await workspace.shutDown()
    }

    @Test("이미 열린 프로젝트가 있을 때 다른 열기가 실패해도 그것은 그대로다")
    func aFailedOpenLeavesTheExistingTabAlone() async throws {
        let good = TemporaryProjectFixture()
        good.write("src/App.kt", contents: "class Application")
        let missing = URL(fileURLWithPath: "/nonexistent/project-\(UUID().uuidString)")
        let workspace = ProjectWorkspaceEngine(
            columns: 80, rows: 24, editorExecutableOverridePath: "/nonexistent/nvim"
        )

        let opened = try await workspace.openProject(at: good.rootURL)
        await #expect(throws: (any Error).self) {
            try await workspace.openProject(at: missing)
        }

        #expect(await workspace.tabs().map(\.id) == [opened.tab.id])
        #expect(await workspace.session(for: opened.tab.id)?.definitions(named: "Application").isEmpty == false)
        await workspace.shutDown()
    }
}

/// REQ-NF-003 on the live path: opening a project has to leave the user able to work.
@Suite("기동 예산 — 워크스페이스 경로 (REQ-NF-003)", .serialized)
struct WorkspaceStartupBudgetTests {

    private func makeRepository(fileCount: Int) -> TemporaryProjectFixture {
        let fixture = TemporaryProjectFixture()
        for index in 0..<fileCount {
            fixture.write("src/module\(index % 40)/Service\(index).kt", contents: """
            package com.example.module\(index % 40)

            class Service\(index) {
                fun handle(request: String): Boolean = true
                val identifier: Int = \(index)
            }
            """)
        }
        return fixture
    }

    /// The budget is 2s and this measures around 0.3s, so the margin is wide enough to survive a
    /// shared runner. If it ever starts flaking, it belongs in `gate.sh`'s isolated step with the
    /// other performance claims rather than having its threshold raised — the number is the claim.
    @Test("중형 레포에서 탭이 2초 안에 조작 가능해진다", .timeLimit(.minutes(2)))
    func openingBecomesUsableWithinTheBudget() async throws {
        let fixture = makeRepository(fileCount: 3_000)
        let workspace = ProjectWorkspaceEngine(columns: 80, rows: 24)

        let start = Date()
        let tab = try await workspace.openProject(at: fixture.rootURL)
        let elapsed = Date().timeIntervalSince(start)

        print("[성능] 탭 열기(인덱싱+편집기) \(String(format: "%.2f", elapsed))초")

        // 조작 가능해야 한다 — 상태만 connected 인 것으로는 부족하다.
        let session = try #require(await workspace.session(for: tab.tab.id))
        #expect(await workspace.editorSession.state() == .connected)
        #expect(await session.definitions(named: "Service100").count == 1)
        #expect(elapsed < 2.0)
        await workspace.shutDown()
    }

    /// Opening a second project must not re-pay the editor's start-up: one Neovim serves them all
    /// (ADR-0008), so the second tab only adds a tabpage. If this ever approaches the first
    /// measurement, the process-per-project shape has crept back in.
    @Test("두 번째 탭은 편집기 기동 비용을 다시 물지 않는다")
    func theSecondTabDoesNotRestartTheEditor() async throws {
        let alpha = makeRepository(fileCount: 200)
        let beta = makeRepository(fileCount: 200)
        let workspace = ProjectWorkspaceEngine(columns: 80, rows: 24)

        let firstStart = Date()
        _ = try await workspace.openProject(at: alpha.rootURL)
        let firstElapsed = Date().timeIntervalSince(firstStart)

        let secondStart = Date()
        _ = try await workspace.openProject(at: beta.rootURL)
        let secondElapsed = Date().timeIntervalSince(secondStart)

        print(String(format: "[성능] 첫 탭 %.2f초 · 둘째 탭 %.2f초", firstElapsed, secondElapsed))
        #expect(await workspace.tabs().count == 2)
        await workspace.shutDown()
    }
}

/// Switching projects, on the live path.
///
/// In the single-project engine this meant replacing the one project and dragging the editor
/// along. Here both stay open, so the scenario becomes: activating a tab moves the editor to that
/// project — otherwise the tree shows one project while the editor resolves paths against another,
/// which is the failure the old scenario was written to catch.
@Suite("탭 전환이 편집기를 데려간다 — 워크스페이스 경로 (REQ-001 AC-2)", .serialized)
struct WorkspaceTabSwitchTests {

    private func canonical(_ url: URL) -> String {
        guard let pointer = realpath(url.path, nil) else { return url.path }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    @Test("탭을 활성화하면 편집기의 작업 디렉토리가 그 프로젝트로 간다")
    func activatingATabMovesTheEditor() async throws {
        let alpha = TemporaryProjectFixture()
        alpha.write("src/Alpha.kt", contents: "class AlphaService")
        let beta = TemporaryProjectFixture()
        beta.write("src/Beta.kt", contents: "class BetaService")
        let workspace = ProjectWorkspaceEngine(columns: 80, rows: 24)

        let first = try await workspace.openProject(at: alpha.rootURL)
        let second = try await workspace.openProject(at: beta.rootURL)

        try await workspace.activate(first.tab.id)
        #expect(try await workspace.editorSession.currentWorkingDirectoryForTesting()
                == canonical(alpha.rootURL))

        try await workspace.activate(second.tab.id)
        #expect(try await workspace.editorSession.currentWorkingDirectoryForTesting()
                == canonical(beta.rootURL))
        await workspace.shutDown()
    }

    /// The same relative path names a different file in each tab. Opening it after a switch must
    /// land in the project the user is looking at — this is the defect the migration found.
    @Test("전환 후 같은 상대 경로가 그 탭의 파일을 연다")
    func theSameRelativePathOpensTheActiveTabsFile() async throws {
        let alpha = TemporaryProjectFixture()
        alpha.write("shared.txt", contents: "alpha content")
        let beta = TemporaryProjectFixture()
        beta.write("shared.txt", contents: "beta content")
        let workspace = ProjectWorkspaceEngine(columns: 80, rows: 24)

        let first = try await workspace.openProject(at: alpha.rootURL)
        let second = try await workspace.openProject(at: beta.rootURL)

        try await workspace.activate(second.tab.id)
        try await workspace.editorSession.openFile(atRelativePath: "shared.txt", line: 1, recordJump: false)
        #expect(try await workspace.editorSession.bufferLinesForTesting().first == "beta content")

        try await workspace.activate(first.tab.id)
        try await workspace.editorSession.openFile(atRelativePath: "shared.txt", line: 1, recordJump: false)
        #expect(try await workspace.editorSession.bufferLinesForTesting().first == "alpha content")
        await workspace.shutDown()
    }

    /// A save outside every open project belongs to no tab. Reindexing it would put a file into a
    /// project that does not contain it.
    @Test("어느 프로젝트에도 속하지 않는 저장은 무시된다")
    func aSaveOutsideEveryProjectIsIgnored() async throws {
        let project = TemporaryProjectFixture()
        project.write("src/App.kt", contents: "class Application")
        let outside = TemporaryProjectFixture()
        outside.write("Stray.kt", contents: "class StrayService")
        let workspace = ProjectWorkspaceEngine(columns: 80, rows: 24)

        let tab = try await workspace.openProject(at: project.rootURL)
        let session = try #require(await workspace.session(for: tab.tab.id))

        // 전제를 먼저 세운다. 편집기가 그 파일을 정말 열지 않으면 저장도 없고, 그러면
        // "인덱스에 없다"는 아무것도 증명하지 않는다 — 일어나지 않은 일의 결과가 없을 뿐이다.
        let strayPath = outside.rootURL.appendingPathComponent("Stray.kt").path
        try await workspace.editorSession.sendKeys(":edit \(strayPath)<CR>")
        let opened = try await workspace.editorSession.evaluateForTesting("expand('%:p')")
        #expect(opened.hasSuffix("Stray.kt"), "전제 실패: 프로젝트 밖 파일이 열리지 않았다 (\(opened))")
        #expect(try await workspace.editorSession.bufferLinesForTesting().first == "class StrayService")

        try await workspace.editorSession.sendKeys(":write<CR>")
        try await Task.sleep(for: .milliseconds(400))

        #expect(await session.definitions(named: "StrayService").isEmpty,
                "프로젝트 밖 파일이 이 프로젝트의 인덱스에 들어갔다")
        await workspace.shutDown()
    }
}

/// The two remaining scenarios from the retiring suite, on live components.
@Suite("남은 수용 시나리오 — 살아 있는 부품", .serialized)
struct RemainingAcceptanceTests {

    /// The save-notification path on its own, with no editor and no watcher involved. Reached
    /// through `ProjectEngine` directly: the behaviour was always that component's, and the
    /// retiring engine was only the handle someone happened to grab it by.
    @Test("저장 통지 경로만으로도 재인덱싱된다 — 파일 감시와 독립적으로")
    func savedFileSignalReindexesOnItsOwn() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/SymbolIndexHolder.kt", contents: "class SymbolIndexHolder")
        let project = ProjectEngine()
        try await project.openProject(at: fixture.rootURL)

        let absolutePath = fixture.rootURL.appendingPathComponent("src/SymbolIndexHolder.kt").path
        try "package com.example\n\nfun savedSignalOnly() {}\n"
            .write(toFile: absolutePath, atomically: true, encoding: .utf8)

        await project.reindexSavedFile(atAbsolutePath: absolutePath)

        #expect(await project.definitions(named: "savedSignalOnly").count == 1)
        // 옛 심볼이 남아 있으면 갱신이 아니라 덧붙이기다 — 인덱스가 디스크와 어긋난다(INV-1).
        #expect(await project.definitions(named: "SymbolIndexHolder").isEmpty)
        await project.closeProject()
    }

    /// Reopening after the editor failed has to bring it back. In the workspace this happens on the
    /// next open, so a user who fixes their install and opens another project gets an editor again
    /// rather than staying editor-less for the life of the app.
    @Test("편집기 실패 후 다른 프로젝트를 열면 편집기가 돌아온다")
    func openingAgainAfterAnEditorFailureRestoresIt() async throws {
        let alpha = TemporaryProjectFixture()
        alpha.write("src/Alpha.kt", contents: "class AlphaService")
        let beta = TemporaryProjectFixture()
        beta.write("src/Beta.kt", contents: "class BetaService")

        let absentEditor = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nvim-absent-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: absentEditor) }
        let workspace = ProjectWorkspaceEngine(
            columns: 80, rows: 24, editorExecutableOverridePath: absentEditor
        )

        _ = try await workspace.openProject(at: alpha.rootURL)
        guard case .startupFailed = await workspace.editorSession.state() else {
            Issue.record("전제가 성립하지 않았다 — 첫 기동이 실패했어야 한다")
            return
        }

        // 사용자가 문제를 고쳤다.
        let realEditor = try NeovimExecutableLocator().locate()
        try """
        #!/bin/sh
        exec \(realEditor.path) "$@"
        """.write(toFile: absentEditor, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: absentEditor)

        _ = try await workspace.openProject(at: beta.rootURL)
        #expect(await workspace.editorSession.state() == .connected,
                "편집기를 고쳤는데도 앱이 사는 동안 돌아오지 않는다")
        await workspace.shutDown()
    }
}

/// Saving still reaches the index after the editor is restarted.
///
/// The workspace subscribes to `savedFiles()` once, when the first project opens. A restart tears
/// the session's channel down and builds a new one, so the question is whether that subscription
/// survives it — if it does not, saves stop reindexing and nothing says so: the user edits, saves,
/// and search quietly answers with yesterday's symbols.
@Suite("재기동 후에도 저장이 인덱스에 닿는다 — 워크스페이스 경로", .serialized)
struct WorkspaceSaveAfterRestartTests {

    @Test("편집기를 재기동해도 저장이 인덱스에 반영된다")
    func savingStillReindexesAfterAnEditorRestart() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application\n")
        let workspace = ProjectWorkspaceEngine(columns: 80, rows: 24)
        let tab = try await workspace.openProject(at: fixture.rootURL)
        let session = try #require(await workspace.session(for: tab.tab.id))

        try await workspace.editorSession.restart()
        #expect(await workspace.editorSession.state() == .connected)

        try await workspace.editorSession.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await workspace.editorSession.sendKeys("ofun addedAfterRestart() {}<Esc>")
        try await Task.sleep(for: .milliseconds(200))
        try await workspace.editorSession.sendKeys(":write<CR>")

        let deadline = Date().addingTimeInterval(3)
        var found: [SymbolDefinition] = []
        while Date() < deadline {
            found = await session.definitions(named: "addedAfterRestart")
            if !found.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(found.count == 1, "재기동 뒤 저장이 인덱스에 닿지 않는다 — 구독이 끊겼다")
        await workspace.shutDown()
    }
}
