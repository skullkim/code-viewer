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

    @Test("REQ-NF-003: 중형 레포에서 엔진이 2초 안에 조작 가능해진다", .timeLimit(.minutes(2)))
    func engineBecomesUsableWithinStartupBudget() async throws {
        let fixture = makeRepository(fileCount: 3_000)
        let engine = CodeNavigatorEngine()

        let start = Date()
        try await engine.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        let elapsed = Date().timeIntervalSince(start)
        defer { Task { await engine.shutDown() } }

        print("[성능] 엔진 기동(인덱싱+편집기 동시) \(String(format: "%.2f", elapsed))초")

        // 기동이 끝난 시점에 실제로 조작 가능해야 한다 — 상태만 connected 인 것으로는 부족하다.
        #expect(await engine.editor.state() == .connected)
        #expect(await engine.project.definitions(named: "Service100").count == 1)
        #expect(elapsed < 2.0)
    }

    @Test("인덱싱과 편집기 기동이 실제로 병렬이다 — 둘의 합보다 빠르다", .timeLimit(.minutes(2)))
    func indexingAndEditorStartConcurrently() async throws {
        let fixture = makeRepository(fileCount: 3_000)

        // 각각 따로 걸리는 시간
        let indexerOnly = ProjectEngine()
        let indexStart = Date()
        try await indexerOnly.openProject(at: fixture.rootURL)
        let indexingSeconds = Date().timeIntervalSince(indexStart)

        let editorOnly = NeovimEditorSession()
        let editorStart = Date()
        try await editorOnly.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        let editorSeconds = Date().timeIntervalSince(editorStart)
        await editorOnly.shutDown()

        // 함께 시작했을 때
        let engine = CodeNavigatorEngine()
        let combinedStart = Date()
        try await engine.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        let combinedSeconds = Date().timeIntervalSince(combinedStart)
        await engine.shutDown()

        print("[성능] 인덱싱 \(String(format: "%.2f", indexingSeconds))초 · 편집기 \(String(format: "%.2f", editorSeconds))초 · 동시 \(String(format: "%.2f", combinedSeconds))초")

        // 순차였다면 합에 가까울 것이다. 병렬이면 느린 쪽에 가깝다.
        #expect(combinedSeconds < indexingSeconds + editorSeconds)
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
