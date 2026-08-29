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

    // 기동 실패와 끊김은 사용자에게 다른 조치를 요구한다 — 하나는 설치·업그레이드, 다른 하나는
    // 재기동이다. 그래서 상태를 나눴고, 기동 실패는 구조화된 정보를 싣는다 (REQ-NF-005).
    @Test("Neovim이 없으면 기동 실패 상태가 되고 안내에 필요한 정보를 싣는다")
    func reportsMissingEditorAsStructuredStartupFailure() async {
        let fixture = TemporaryProjectFixture()
        let session = NeovimEditorSession(
            executableLocator: NeovimExecutableLocator(wellKnownPaths: ["/nonexistent/nvim"]),
            executableOverridePath: "/nonexistent/nvim"
        )

        await #expect(throws: (any Error).self) {
            try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        }
        guard case .startupFailed(let failure) = await session.state() else {
            Issue.record("기동 실패 상태여야 한다")
            return
        }
        #expect(!failure.reason.isEmpty)
        #expect(!failure.searchedPaths.isEmpty)
        #expect(failure.requiredVersion == "0.9.0")
        // 아예 못 찾은 경우와 "설치돼 있지만 낡음"은 다른 문구가 나가야 한다.
        #expect(failure.foundVersion == nil)
    }

    @Test("설치된 Neovim의 버전을 실제로 읽는다")
    func readsInstalledNeovimVersion() throws {
        let locator = NeovimExecutableLocator()
        let executable = try locator.locate()
        let version = try #require(locator.version(of: executable))
        #expect(version >= NeovimVersion.minimumSupported)
    }

    @Test("마우스 클릭을 그리드 셀 좌표로 전달한다 — 표준 모드의 커서 이동")
    func forwardsMouseClicksInGridCoordinates() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: (1...10).map { "line \($0) text" }.joined(separator: "\n"))
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await Task.sleep(for: .milliseconds(200))

        // 4행 6열을 누르면 커서가 그 줄로 가야 한다. 키 표기법으로는 위치를 실을 수 없어
        // 이 경로가 따로 필요하다 (REQ-010 AC-2).
        try await session.sendMouse(
            EditorMouseEvent(button: .left, action: .press, row: 3, column: 6)
        )
        try await Task.sleep(for: .milliseconds(300))

        let line = try await session.currentLineForTesting()
        #expect(line == "line 4 text")
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

        let savedFiles = await session.savedFiles()
        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await session.sendKeys("ofun added() {}<Esc>")

        let dirty = await firstValue(from: await session.statusUpdates()) { $0.isDirty }
        #expect(dirty != nil)

        // 저장을 보내기 전에 버퍼가 실제로 더티인지 확인한다. 부하가 걸린 실행에서는 앞선
        // 키 입력이 아직 반영되지 않은 채 :write 가 나가고, 바꿀 것이 없으면 쓰기도 통지도
        // 일어나지 않는다 — 그러면 "저장 통지가 안 온다"로 보이지만 원인은 그 앞이다.
        try await Task.sleep(for: .milliseconds(200))
        try await session.sendKeys(":write<CR>")
        let saved = await firstValue(from: savedFiles, timeout: .seconds(10)) { (file: SavedFile) in
            file.path.hasSuffix("App.kt")
        }
        let savedFile = try #require(saved)
        // 줄 수·크기는 Neovim 이 저장 시점에 알고 있는 값이다. 앱이 파일을 다시 읽지 않는다.
        #expect(savedFile.lineCount > 0)
        #expect(savedFile.byteSize > 0)

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
