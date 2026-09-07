import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// 앱 안의 터미널. 실제 nvim 을 띄워 실제 셸을 돌린다 — 여기서 가짜를 쓰면 재는 것이 없다.
@Suite("터미널 세션", .serialized)
struct NeovimTerminalSessionTests {

    private func textOf(_ snapshot: EditorGridSnapshot) -> String {
        snapshot.lines
            .map { $0.runs.map(\.text).joined() }
            .joined(separator: "\n")
    }

    /// 스냅샷이 조건을 만족할 때까지 기다린다. 잠으로 기다리면 느리거나 흔들린다.
    private func waitForOutput(
        _ session: NeovimTerminalSession, containing needle: String, seconds: Double = 20
    ) async -> String? {
        let stream = await session.gridUpdates()
        let deadline = Date().addingTimeInterval(seconds)
        for await snapshot in stream {
            let text = textOf(snapshot)
            if text.contains(needle) { return text }
            if Date() > deadline { return nil }
        }
        return nil
    }

    @Test("명령을 돌리고 그 출력을 그린다")
    func runsACommandAndShowsItsOutput() async throws {
        let session = NeovimTerminalSession()
        defer { Task { await session.stop() } }

        try await session.start(
            command: "echo TERMINAL-WORKS-42",
            workingDirectory: NSTemporaryDirectory(),
            environment: ProcessInfo.processInfo.environment,
            columns: 80, rows: 10
        )

        let text = await waitForOutput(session, containing: "TERMINAL-WORKS-42")
        #expect(text != nil, "명령 출력이 화면에 안 나왔다")
    }

    /// **환경변수가 실제로 자식 프로세스에 닿아야 한다.** 안 닿으면 서버가 잘못된 프로파일로
    /// 뜨고, 그 실패는 앱이 아니라 서버 쪽 문제로 보인다.
    @Test("환경변수가 돌아가는 명령에 닿는다")
    func passesTheEnvironmentThrough() async throws {
        let session = NeovimTerminalSession()
        defer { Task { await session.stop() } }

        var environment = ProcessInfo.processInfo.environment
        environment["CODE_NAVIGATOR_PROBE"] = "PROBE-VALUE-7"

        try await session.start(
            command: "printf '%s\\n' \"$CODE_NAVIGATOR_PROBE\"",
            workingDirectory: NSTemporaryDirectory(),
            environment: environment,
            columns: 80, rows: 10
        )

        let text = await waitForOutput(session, containing: "PROBE-VALUE-7")
        #expect(text != nil, "환경변수가 명령에 안 닿았다")
    }

    /// 작업 디렉터리가 틀리면 `./gradlew` 를 못 찾는다 — 그 실패는 "명령 없음" 으로만 보인다.
    @Test("작업 디렉터리에서 돈다")
    func runsInTheWorkingDirectory() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("terminal-cwd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "".write(to: root.appendingPathComponent("MARKER-FILE"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = NeovimTerminalSession()
        defer { Task { await session.stop() } }

        try await session.start(
            command: "ls",
            workingDirectory: root.path,
            environment: ProcessInfo.processInfo.environment,
            columns: 80, rows: 10
        )

        let text = await waitForOutput(session, containing: "MARKER-FILE")
        #expect(text != nil, "작업 디렉터리가 반영되지 않았다")
    }

    @Test("입력한 키가 셸에 들어간다")
    func sendsKeysToTheShell() async throws {
        let session = NeovimTerminalSession()
        defer { Task { await session.stop() } }

        // 명령 없이 셸만 띄운 뒤 직접 친다.
        try await session.start(
            command: "",
            workingDirectory: NSTemporaryDirectory(),
            environment: ProcessInfo.processInfo.environment,
            columns: 80, rows: 10
        )
        // 셸이 프롬프트를 낼 때까지 기다린 뒤 친다. 바로 치면 셸이 아직 안 떠서 글자가 사라진다.
        try await Task.sleep(for: .milliseconds(1500))
        await session.send(keys: "echo TYPED-INPUT-9\r")

        let text = await waitForOutput(session, containing: "TYPED-INPUT-9")
        #expect(text != nil, "친 글자가 셸에 안 들어갔다")
    }
}
