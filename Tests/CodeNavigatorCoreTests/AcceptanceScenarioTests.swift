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
        try await engine.editor.sendKeys("^f S")
        try await Task.sleep(for: .milliseconds(300))

        let definitions = await engine.project.definitions(named: "SymbolIndexHolder")
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
