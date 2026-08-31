import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Two requirements that were reasoned about but never measured: how long the engine takes to
/// become usable, and what a real `git checkout` does to the index.
@Suite("기동 시간과 대량 변경 — 실측", .serialized)
struct StartupAndBulkChangeTests {

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

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test("인덱싱과 편집기 기동의 구간이 실제로 겹친다", .timeLimit(.minutes(2)))
    func indexingAndEditorStartOverlapInTime() async throws {
        let fixture = makeRepository(fileCount: 3_000)
        // URL 로 붙잡는다 — 픽스처 자체를 두 클로저에 보내면 Sendable 이 아니다.
        let root = fixture.rootURL
        let project = ProjectEngine()
        let editor = NeovimEditorSession()

        actor Span {
            var startedAt: ContinuousClock.Instant?
            var endedAt: ContinuousClock.Instant?
            func begin() { startedAt = .now }
            func end() { endedAt = .now }
        }
        let indexingSpan = Span()
        let editorSpan = Span()

        async let indexing: Void = {
            await indexingSpan.begin()
            try await project.openProject(at: root)
            await indexingSpan.end()
        }()
        async let editing: Void = {
            await editorSpan.begin()
            try await editor.start(projectRoot: root, columns: 80, rows: 24)
            await editorSpan.end()
        }()
        try await indexing
        try await editing

        let indexingStart = try #require(await indexingSpan.startedAt)
        let indexingEnd = try #require(await indexingSpan.endedAt)
        let editorStart = try #require(await editorSpan.startedAt)
        let editorEnd = try #require(await editorSpan.endedAt)

        // 겹침 = 늦게 시작한 쪽의 시작이 먼저 끝난 쪽의 끝보다 앞선다.
        let latestStart = max(indexingStart, editorStart)
        let earliestEnd = min(indexingEnd, editorEnd)
        #expect(latestStart < earliestEnd, "두 구간이 겹치지 않았다 — 순차로 돈 것이다")

        await editor.shutDown()
        await project.closeProject()
    }

    @Test("SC-5: 실제 git checkout 으로 수백 파일이 바뀌어도 죽지 않고 INV-1이 성립한다", .timeLimit(.minutes(3)))
    func survivesRealGitCheckout() async throws {
        let fixture = makeRepository(fileCount: 300)
        let root = fixture.rootURL

        #expect(runGit(["init", "--quiet"], in: root) == 0)
        runGit(["config", "user.email", "test@example.com"], in: root)
        runGit(["config", "user.name", "Test"], in: root)
        #expect(runGit(["add", "-A"], in: root) == 0)
        #expect(runGit(["commit", "--quiet", "-m", "initial"], in: root) == 0)

        let indexer = ProjectIndexer()
        try await indexer.openProject(at: root)
        #expect(await indexer.definitions(named: "Service0").count == 1)

        // 전 파일을 바꾸고, 새 파일을 만들고, 하나를 지운다 — 그리고 되돌린다.
        for index in 0..<300 {
            fixture.write("src/module\(index % 40)/Service\(index).kt", contents: """
            package com.example.module\(index % 40)

            class RenamedService\(index) {
                fun handle(request: String): Boolean = false
            }
            """)
        }
        fixture.write("src/Untracked.kt", contents: "class NeverCommitted")
        fixture.remove("src/module0/Service0.kt")

        // git checkout 이 수백 파일을 한꺼번에 되돌린다. 워처가 이벤트 폭주를 만난다.
        #expect(runGit(["checkout", "--", "."], in: root) == 0)

        // 폭주가 가라앉을 때까지 기다린 뒤 상태를 본다.
        try await Task.sleep(for: .milliseconds(1_500))
        await indexer.waitUntilIdle()

        // INV-1: 인덱스가 가리키는 것이 실제 파일과 일치해야 한다.
        // 되돌려졌으므로 원래 이름이 살아 있고, 편집 중 이름은 유령으로 남으면 안 된다.
        let restored = await indexer.definitions(named: "Service0")
        #expect(restored.count == 1)
        #expect(await indexer.definitions(named: "RenamedService0").isEmpty)
        #expect(await indexer.definitions(named: "RenamedService299").isEmpty)

        // 추적되지 않은 파일은 checkout 이 지우지 않으므로 인덱스에 남아 있어야 한다.
        #expect(await indexer.definitions(named: "NeverCommitted").count == 1)

        #expect(await indexer.indexState() == .ready)
    }

    @Test("SC-5 후속: 되돌린 뒤에도 검색이 실제 파일 내용과 일치한다", .timeLimit(.minutes(3)))
    func searchMatchesDiskAfterCheckout() async throws {
        let fixture = makeRepository(fileCount: 120)
        let root = fixture.rootURL

        runGit(["init", "--quiet"], in: root)
        runGit(["config", "user.email", "test@example.com"], in: root)
        runGit(["config", "user.name", "Test"], in: root)
        runGit(["add", "-A"], in: root)
        runGit(["commit", "--quiet", "-m", "initial"], in: root)

        let engine = ProjectEngine()
        try await engine.openProject(at: root)

        for index in 0..<120 {
            fixture.write("src/module\(index % 40)/Service\(index).kt",
                          contents: "class Temporary\(index)\n")
        }
        runGit(["checkout", "--", "."], in: root)
        try await Task.sleep(for: .milliseconds(1_500))
        await engine.waitUntilIndexIsIdle()

        // 인덱스가 유령을 들고 있으면 여기서 드러난다.
        let ghosts = await engine.searchSymbols(matching: "Temporary")
        #expect(ghosts.isEmpty)

        // 전문 검색도 실제 디스크 내용과 일치해야 한다.
        let onDisk = try await engine.searchText("class Temporary", mode: .literal)
        #expect(onDisk.items.isEmpty)
        // 되돌려진 원본 내용이 실제로 검색돼야 한다. `total >= 0` 같은 항진 단언을 쓰면
        // 인덱스가 통째로 비어 있어도 통과한다.
        let restored = try await engine.searchText("class Service0 {", mode: .literal)
        #expect(restored.items.count == 1)
        #expect(restored.items.first?.path == "src/module0/Service0.kt")
    }
}
