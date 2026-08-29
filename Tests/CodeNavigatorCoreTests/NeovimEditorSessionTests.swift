import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Drives a real Neovim through the full `EditorSession` contract.
@Suite("NeovimEditorSession — 계약 통합", .serialized)
struct NeovimEditorSessionTests {

    private func startSession(
        _ fixture: TemporaryProjectFixture
    ) async throws -> NeovimEditorSession {
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        return session
    }

    /// Waits for the first value that satisfies a condition, so tests never depend on a sleep
    /// being long enough on a loaded machine.
    private func firstValue<Value: Sendable>(
        from stream: AsyncStream<Value>,
        timeout: Duration = .seconds(5),
        where predicate: @escaping @Sendable (Value) -> Bool
    ) async -> Value? {
        await withTaskGroup(of: Value?.self) { group in
            group.addTask {
                for await value in stream where predicate(value) {
                    return value
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    @Test("기동하면 연결 상태가 되고 첫 프레임이 도착한다")
    func startsAndDeliversFirstFrame() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class App\n")
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        #expect(await session.state() == .connected)

        let snapshot = await firstValue(from: await session.gridUpdates()) { $0.rows > 0 }
        let frame = try #require(snapshot)
        #expect(frame.columns == 80)
        #expect(frame.rows == 24)
        #expect(frame.lines.count == 24)
    }

    @Test("Neovim이 없으면 명확한 에러와 함께 끊김 상태가 된다 — 무반응 금지")
    func reportsMissingEditorAsDisconnected() async {
        let fixture = TemporaryProjectFixture()
        let session = NeovimEditorSession(
            executableLocator: NeovimExecutableLocator(wellKnownPaths: ["/nonexistent/nvim"]),
            executableOverridePath: "/nonexistent/nvim"
        )

        await #expect(throws: (any Error).self) {
            try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        }
        guard case .disconnected(let reason) = await session.state() else {
            Issue.record("끊김 상태여야 한다")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test("파일을 열고 지정한 라인으로 이동한다")
    func opensFileAtLine() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: (1...20).map { "line \($0)" }.joined(separator: "\n"))
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 12, recordJump: true)

        let status = await firstValue(from: await session.statusUpdates()) { $0.cursorLine == 12 }
        let observed = try #require(status)
        #expect(observed.filePath?.hasSuffix("src/App.kt") == true)
        #expect(observed.cursorLine == 12)
        #expect(observed.isDirty == false)
    }

    @Test("경로 세그먼트에 상위 이동이 있으면 거부한다")
    func rejectsParentDirectorySegments() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        await #expect(throws: NavigatorError.invalidPath("../outside.kt")) {
            try await session.openFile(atRelativePath: "../outside.kt", line: nil, recordJump: false)
        }
    }

    @Test("커서 아래 단어를 읽는다 — 정의 이동의 입력")
    func readsWordUnderCursor() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class SymbolIndexHolder\n")
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await session.sendKeys("w")
        try await Task.sleep(for: .milliseconds(300))

        #expect(try await session.wordUnderCursor() == "SymbolIndexHolder")
    }

    @Test("편집하면 더티가 되고 저장하면 경로가 통지되며 더티가 풀린다")
    func reportsDirtyStateAndSavedPaths() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class App\n")
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        let savedPaths = await session.savedFilePaths()
        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await session.sendKeys("ofun added() {}<Esc>")

        let dirty = await firstValue(from: await session.statusUpdates()) { $0.isDirty }
        #expect(dirty != nil)

        try await session.sendKeys(":write<CR>")
        let savedPath = await firstValue(from: savedPaths) { $0.hasSuffix("App.kt") }
        #expect(savedPath != nil)

        let onDisk = try String(contentsOf: fixture.rootURL.appendingPathComponent("src/App.kt"), encoding: .utf8)
        #expect(onDisk.contains("fun added()"))
    }

    @Test("기동 전에 보낸 키는 큐에 담겼다가 부착 후 실제로 입력된다 — 첫 타이핑을 잃지 않는다")
    func queuesKeysSentBeforeAttach() async throws {
        let fixture = TemporaryProjectFixture()
        let session = NeovimEditorSession()
        defer { Task { await session.shutDown() } }

        // 아직 기동 전이라 채널이 없다. 이 키는 반드시 큐에 담겨야 한다.
        try await session.sendKeys("iqueued text<Esc>")
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)

        // 큐가 흘러간 뒤 버퍼에 실제로 글자가 들어갔는지 확인한다.
        // "상태 알림이 왔다"만 보면 큐잉을 제거해도 통과하므로 버퍼 내용을 직접 본다.
        var bufferLine = ""
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            if let line = try await session.currentLineForTesting(), line.contains("queued text") {
                bufferLine = line
                break
            }
        }
        #expect(bufferLine.contains("queued text"))
    }

    @Test("입력 모드를 바꿔도 편집 내용과 더티 상태가 보존된다")
    func preservesBufferAcrossInputModeChange() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class App\n")
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await session.sendKeys("ochanged line<Esc>")
        _ = await firstValue(from: await session.statusUpdates()) { $0.isDirty }

        #expect(await session.inputMode() == .vim)
        try await session.setInputMode(.standard)
        #expect(await session.inputMode() == .standard)

        // 전환만으로 저장이 일어나면 안 되고, 편집 내용이 남아 있어야 한다.
        let onDisk = try String(contentsOf: fixture.rootURL.appendingPathComponent("src/App.kt"), encoding: .utf8)
        #expect(onDisk.contains("changed line") == false)

        let status = await firstValue(from: await session.statusUpdates()) { _ in true }
        #expect(status?.isDirty == true)
        #expect(status?.inputMode == .standard)

        try await session.setInputMode(.vim)
        #expect(await session.inputMode() == .vim)
    }

    @Test("프로세스가 죽으면 끊김을 알리고 재기동할 수 있다")
    func detectsCrashAndRestarts() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        let states = await session.stateUpdates()
        let channelIdentifier = try #require(await session.processIdentifierForTesting())
        kill(channelIdentifier, SIGKILL)

        let disconnected = await firstValue(from: states) {
            if case .disconnected = $0 { return true }
            return false
        }
        #expect(disconnected != nil)

        try await session.restart()
        #expect(await session.state() == .connected)
    }

    @Test("그리드 크기를 바꾸면 다음 프레임에 반영된다")
    func resizesGrid() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        let frames = await session.gridUpdates()
        try await session.resizeGrid(columns: 100, rows: 30)

        let resized = await firstValue(from: frames) { $0.columns == 100 && $0.rows == 30 }
        #expect(resized != nil)
    }
}
