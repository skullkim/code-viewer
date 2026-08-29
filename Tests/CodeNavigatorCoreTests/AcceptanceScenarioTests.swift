import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// The acceptance scenarios from the requirements (§8), driven through the engine as the
/// application will drive it — real Neovim, real files, real index.
@Suite("수용 시나리오 — 엔진 종단 검증", .serialized)
struct AcceptanceScenarioTests {

    private func makeProject() -> TemporaryProjectFixture {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/SymbolIndexHolder.kt", contents: """
        package com.example

        class SymbolIndexHolder {
            fun addSymbol(name: String): Boolean {
                return true
            }
        }
        """)
        fixture.write("src/Consumer.kt", contents: """
        package com.example

        class Consumer {
            fun use() {
                val holder = SymbolIndexHolder()
                holder.addSymbol("value")
            }
        }
        """)
        fixture.write("src/first/Duplicate.kt", contents: "package a\nfun duplicated() {}\n")
        fixture.write("src/second/Duplicate.kt", contents: "package b\nfun duplicated() {}\n")
        fixture.write("src/third/Duplicate.kt", contents: "package c\nfun duplicated() {}\n")
        return fixture
    }

    @Test("SC-1: 심볼의 정의 위치로 이동한다")
    func goesToDefinition() async throws {
        let fixture = makeProject()
        let engine = CodeNavigatorEngine()
        try await engine.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await engine.shutDown() } }

        // 사용처를 열고 심볼 위에 커서를 둔다.
        try await engine.editor.openFile(atRelativePath: "src/Consumer.kt", line: 5, recordJump: false)
        // '^' 로 첫 비공백, 'fS' 로 SymbolIndexHolder 의 S 까지. 사이에 공백을 넣으면
        // 'f<space>' 다음 'S'(줄 치환)가 되어 버퍼를 망가뜨린다.
        try await engine.editor.sendKeys("^fS")
        try await Task.sleep(for: .milliseconds(300))

        // 이름을 하드코딩하지 않는다. 커서 위치에서 심볼을 읽어 그것으로 조회해야
        // REQ-005 AC-1 의 "커서 위치 심볼에 대해"가 실제로 검증된다.
        let symbolUnderCursor = try #require(try await engine.editor.wordUnderCursor())
        #expect(symbolUnderCursor == "SymbolIndexHolder")

        let definitions = await engine.project.definitions(named: symbolUnderCursor)
        let target = try #require(definitions.first)
        #expect(target.path == "src/SymbolIndexHolder.kt")
        #expect(target.kind == .class)

        try await engine.editor.openFile(atRelativePath: target.path, line: target.line, recordJump: true)
        let status = try await waitForStatus(engine) { $0.filePath?.hasSuffix("SymbolIndexHolder.kt") == true }
        #expect(status.cursorLine == target.line)
    }

    @Test("SC-2: 동명 정의가 셋이면 후보 셋이 나온다")
    func offersEveryCandidateForDuplicatedNames() async throws {
        let fixture = makeProject()
        let engine = CodeNavigatorEngine()
        try await engine.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await engine.shutDown() } }

        let definitions = await engine.project.definitions(named: "duplicated")
        #expect(definitions.count == 3)
        // 정렬이 결정적이라 후보 목록의 순서가 매번 같다.
        #expect(definitions.map(\.path) == [
            "src/first/Duplicate.kt", "src/second/Duplicate.kt", "src/third/Duplicate.kt",
        ])
    }

    @Test("저장 통지 경로만으로도 재인덱싱된다 — 파일 감시와 독립적으로")
    func savedFileSignalReindexesOnItsOwn() async throws {
        let fixture = makeProject()
        let engine = CodeNavigatorEngine()
        // 편집기는 띄우지 않는다. 파일 감시도 걸리지만, 여기서는 저장 통지 경로를 직접 호출해
        // 그 경로 하나만으로 인덱스가 갱신되는지 확인한다.
        try await engine.project.openProject(at: fixture.rootURL)

        let absolutePath = fixture.rootURL.appendingPathComponent("src/SymbolIndexHolder.kt").path
        try "package com.example\n\nfun savedSignalOnly() {}\n"
            .write(toFile: absolutePath, atomically: true, encoding: .utf8)

        await engine.project.reindexSavedFile(atAbsolutePath: absolutePath)

        #expect(await engine.project.definitions(named: "savedSignalOnly").count == 1)
        #expect(await engine.project.definitions(named: "SymbolIndexHolder").isEmpty)
    }

    @Test("프로젝트 밖 경로의 저장 통지는 무시된다")
    func ignoresSavedPathsOutsideTheProject() async throws {
        let fixture = makeProject()
        let outside = TemporaryProjectFixture()
        outside.write("Stranger.kt", contents: "class Stranger")
        let engine = CodeNavigatorEngine()
        try await engine.project.openProject(at: fixture.rootURL)

        await engine.project.reindexSavedFile(
            atAbsolutePath: outside.rootURL.appendingPathComponent("Stranger.kt").path
        )

        #expect(await engine.project.definitions(named: "Stranger").isEmpty)
    }

    @Test("SC-3: 편집 후 :w 하면 2초 안에 새 심볼이 검색된다")
    func newSymbolIsSearchableAfterSaving() async throws {
        let fixture = makeProject()
        let engine = CodeNavigatorEngine()
        try await engine.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await engine.shutDown() } }

        #expect(await engine.project.definitions(named: "freshlyWrittenFunction").isEmpty)

        try await engine.editor.openFile(atRelativePath: "src/SymbolIndexHolder.kt", line: 3, recordJump: false)
        try await engine.editor.sendKeys("ofun freshlyWrittenFunction() {}<Esc>")
        try await Task.sleep(for: .milliseconds(200))
        try await engine.editor.sendKeys(":write<CR>")

        let deadline = Date().addingTimeInterval(2)
        var found: [SymbolDefinition] = []
        while Date() < deadline {
            found = await engine.project.definitions(named: "freshlyWrittenFunction")
            if !found.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(found.count == 1)
        #expect(found.first?.path == "src/SymbolIndexHolder.kt")
    }

    @Test("SC-6: 잘못된 정규식은 에러다 — 빈 결과로 위장하지 않는다")
    func invalidRegularExpressionIsAnError() async throws {
        let fixture = makeProject()
        let engine = CodeNavigatorEngine()
        try await engine.project.openProject(at: fixture.rootURL)

        await #expect(throws: (any Error).self) {
            try await engine.project.searchText("([unclosed", mode: .regularExpression)
        }

        // 같은 문자열을 리터럴로 찾으면 에러가 아니라 정상적인 빈 결과다.
        let literal = try await engine.project.searchText("([unclosed", mode: .literal)
        #expect(literal.items.isEmpty)
        #expect(literal.truncated == false)
    }

    @Test("참조 목록에 정의가 포함되고 플래그로 구분된다")
    func referencesIncludeFlaggedDefinition() async throws {
        let fixture = makeProject()
        let engine = CodeNavigatorEngine()
        try await engine.project.openProject(at: fixture.rootURL)

        let result = try await engine.project.references(to: "SymbolIndexHolder")
        #expect(result.references.contains { $0.isDefinition })
        #expect(result.references.contains { !$0.isDefinition })
        #expect(result.truncated == false)
    }

    @Test("심볼 퍼지 검색이 관련도순으로 응답한다")
    func fuzzySymbolSearchRanksByRelevance() async throws {
        let fixture = makeProject()
        let engine = CodeNavigatorEngine()
        try await engine.project.openProject(at: fixture.rootURL)

        let results = await engine.project.searchSymbols(matching: "SymIdx")
        #expect(results.first?.definition.name == "SymbolIndexHolder")
        #expect(results.first?.matchRanges.isEmpty == false)
        #expect(results.count <= SymbolSearcher.resultLimit)
    }

    @Test("파일 트리가 한 레벨씩, 디렉토리 우선으로 나온다")
    func fileTreeListsOneLevelDirectoriesFirst() async throws {
        let fixture = makeProject()
        let engine = CodeNavigatorEngine()
        try await engine.project.openProject(at: fixture.rootURL)

        let rootEntries = try await engine.project.directoryEntries(atRelativePath: "")
        #expect(rootEntries.map(\.name) == ["src"])

        let sourceEntries = try await engine.project.directoryEntries(atRelativePath: "src")
        let directoriesFirst = sourceEntries.prefix { $0.isDirectory }.map(\.name)
        #expect(directoriesFirst == ["first", "second", "third"])
        #expect(sourceEntries.contains { $0.name == "Consumer.kt" && !$0.isDirectory })
    }

    @Test("프로젝트를 열지 않은 상태의 조회는 명확한 에러다")
    func queriesWithoutAProjectAreClearErrors() async throws {
        let engine = CodeNavigatorEngine()
        await #expect(throws: NavigatorError.noProjectOpen) {
            try await engine.project.searchText("anything", mode: .literal)
        }
        await #expect(throws: NavigatorError.noProjectOpen) {
            try await engine.project.directoryEntries(atRelativePath: "")
        }
    }

    /// Waits for an editor status matching a condition, so tests do not race the editor.
    private func waitForStatus(
        _ engine: CodeNavigatorEngine,
        where predicate: @escaping @Sendable (EditorStatus) -> Bool
    ) async throws -> EditorStatus {
        let statuses = await engine.editor.statusUpdates()
        return try await withThrowingTaskGroup(of: EditorStatus?.self) { group in
            group.addTask {
                for await status in statuses where predicate(status) {
                    return status
                }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                return nil
            }
            let result = try await group.next() ?? nil
            group.cancelAll()
            guard let result else {
                throw NavigatorError.editorUnavailable(reason: "상태를 기다리다 시간이 초과됐습니다")
            }
            return result
        }
    }
}

@Suite("REQ-001 AC-2 — 프로젝트 전환", .serialized)
struct ProjectSwitchingTests {

    private func makeProject(name: String, symbol: String) -> TemporaryProjectFixture {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/\(name).kt", contents: "package \(name)\n\nclass \(symbol)\n")
        return fixture
    }

    @Test("전환하면 인덱스·검색·트리가 새 프로젝트로 바뀐다")
    func switchingReplacesIndexAndTree() async throws {
        let first = makeProject(name: "First", symbol: "AlphaService")
        let second = makeProject(name: "Second", symbol: "BetaService")
        let engine = CodeNavigatorEngine()
        defer { Task { await engine.shutDown() } }

        try await engine.openProject(at: first.rootURL)
        #expect(await engine.project.definitions(named: "AlphaService").count == 1)

        try await engine.openProject(at: second.rootURL)
        #expect(await engine.project.definitions(named: "BetaService").count == 1)
        #expect(await engine.project.definitions(named: "AlphaService").isEmpty)

        let entries = try await engine.project.directoryEntries(atRelativePath: "src")
        #expect(entries.map(\.name) == ["Second.kt"])
        #expect(await engine.project.currentProject()?.rootPath == second.rootURL)
    }

    @Test("전환하면 편집기도 새 프로젝트를 따라간다 — 트리만 바뀌고 에디터가 남는 일이 없다")
    func switchingMovesTheEditorToo() async throws {
        let first = makeProject(name: "First", symbol: "AlphaService")
        let second = makeProject(name: "Second", symbol: "BetaService")
        let engine = CodeNavigatorEngine()
        defer { Task { await engine.shutDown() } }

        try await engine.start(projectRoot: first.rootURL, columns: 80, rows: 24)
        try await engine.editor.openFile(atRelativePath: "src/First.kt", line: 1, recordJump: false)

        try await engine.openProject(at: second.rootURL)

        // 새 프로젝트의 상대 경로가 열려야 한다. 편집기가 옛 루트를 붙들고 있으면 여기서 실패한다.
        try await engine.editor.openFile(atRelativePath: "src/Second.kt", line: 1, recordJump: false)
        try await Task.sleep(for: .milliseconds(300))

        let line = try await engine.editor.currentLineForTesting()
        #expect(line == "package Second")
    }

    @Test("전환에 실패하면 이전 프로젝트가 그대로 남는다")
    func failedSwitchKeepsPreviousProject() async throws {
        let first = makeProject(name: "First", symbol: "AlphaService")
        let engine = CodeNavigatorEngine()
        defer { Task { await engine.shutDown() } }

        try await engine.openProject(at: first.rootURL)
        await #expect(throws: (any Error).self) {
            try await engine.openProject(at: URL(fileURLWithPath: "/nonexistent/second"))
        }

        #expect(await engine.project.definitions(named: "AlphaService").count == 1)
        #expect(await engine.project.currentProject()?.rootPath == first.rootURL)
    }
}

/// Gaps QA identified: paths that are correct today but had no test holding them in place.
@Suite("회귀 방어 — QA 지적 갭", .serialized)
struct QaIdentifiedGapTests {

    @Test("정의 이동 시 대상 줄이 잠시 강조되고, 스스로 사라진다")
    func jumpTargetIsHighlightedThenClears() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: (1...30).map { "line \($0)" }.joined(separator: "\n"))
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 20, recordJump: true)
        #expect(try await session.jumpHighlightCountForTesting() == 1)

        // 스스로 지워져야 한다. 남으면 선택 영역처럼 보인다.
        var cleared = false
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            if try await session.jumpHighlightCountForTesting() == 0 {
                cleared = true
                break
            }
        }
        #expect(cleared)
    }

    @Test("라인을 지정하지 않은 열기는 강조하지 않는다")
    func openingWithoutALineDoesNotHighlight() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class App\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: nil, recordJump: false)
        #expect(try await session.jumpHighlightCountForTesting() == 0)
    }

    @Test("편집기 재기동 후에도 저장이 인덱스에 반영된다")
    func savesAreStillIndexedAfterEditorRestart() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application\n")
        let engine = CodeNavigatorEngine()
        try await engine.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await engine.shutDown() } }

        // 앱은 계약상 editor.restart() 를 직접 부를 수 있다. 그때 저장 구독이 끊기면
        // 이후 모든 저장이 조용히 인덱스에 반영되지 않는다 — 증상 없는 INV-1 위반이다.
        try await engine.editor.restart()
        #expect(await engine.editor.state() == .connected)

        try await engine.editor.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await engine.editor.sendKeys("ofun addedAfterRestart() {}<Esc>")
        try await Task.sleep(for: .milliseconds(200))
        try await engine.editor.sendKeys(":write<CR>")

        let deadline = Date().addingTimeInterval(3)
        var found: [SymbolDefinition] = []
        while Date() < deadline {
            found = await engine.project.definitions(named: "addedAfterRestart")
            if !found.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(found.count == 1)
    }

    @Test("편집기가 보고한 경로를 루트로 상대화하면 트리 경로와 일치한다")
    func editorPathsRelativizeToTreePaths() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application\n")
        let engine = CodeNavigatorEngine()
        try await engine.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await engine.shutDown() } }

        try await engine.editor.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)

        var editorPath: String?
        for await status in await engine.editor.statusUpdates() {
            if let path = status.filePath {
                editorPath = path
                break
            }
        }
        let absolute = try #require(editorPath)

        // 프론트엔드는 이 상대화로 트리를 강조한다(REQ-003 AC-3). 심링크·/private 접두
        // 같은 정규화 차이가 생기면 매칭이 조용히 실패하므로 여기서 고정한다.
        let root = fixture.rootURL.path.hasSuffix("/") ? fixture.rootURL.path : fixture.rootURL.path + "/"
        #expect(absolute.hasPrefix(root))
        let relative = String(absolute.dropFirst(root.count))
        #expect(relative == "src/App.kt")

        let entries = try await engine.project.directoryEntries(atRelativePath: "src")
        #expect(entries.contains { $0.path == relative })
    }
}

@Suite("currentProject — 실패한 열기 뒤의 권위", .serialized)
struct CurrentProjectAuthorityTests {

    @Test("열기에 실패해도 엔진은 이전 프로젝트를 계속 가리킨다")
    func staysOnThePreviousProjectAfterAFailedOpen() async throws {
        let opened = TemporaryProjectFixture()
        opened.write("src/App.kt", contents: "class Application")
        let engine = ProjectEngine()
        try await engine.openProject(at: opened.rootURL)

        let requested = URL(fileURLWithPath: "/nonexistent/second")
        await #expect(throws: (any Error).self) {
            try await engine.openProject(at: requested)
        }

        // 앱이 "요청한 경로"를 들고 있으면 여기서 갈라진다. 엔진이 답하는 쪽이 진짜다.
        #expect(await engine.currentProject()?.rootPath == opened.rootURL)
        #expect(await engine.definitions(named: "Application").count == 1)
    }

    @Test("프로젝트를 열기 전에는 가리키는 것이 없다")
    func hasNoProjectBeforeOpening() async {
        #expect(await ProjectEngine().currentProject() == nil)
    }

    @Test("이름은 루트 디렉토리 이름이다")
    func namesTheProjectAfterItsRootDirectory() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)

        let project = try #require(await engine.currentProject())
        #expect(project.name == fixture.rootURL.lastPathComponent)
    }
}
