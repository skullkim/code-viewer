import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Mode reaches the interface by a different route from the rest of the editor status: it rides
/// the redraw stream, while path, dirty flag and cursor come from autocommands. The two must meet,
/// or a selection can leave the indicator saying "normal" — which is what happened once already.
@Suite("모드 전파 — redraw 와 상태 스트림의 합류", .serialized)
struct ModePropagationTests {

    /// Collects modes from the status stream until one satisfies the predicate, or time runs out.
    /// Scans the whole stream rather than taking the first value: the broadcaster replays the last
    /// published status to a new subscriber, so the first value is the state *before* the action.
    private func modesUntil(
        _ statuses: AsyncStream<EditorStatus>,
        satisfies predicate: @escaping @Sendable (EditorMode) -> Bool,
        timeout: Duration = .seconds(5)
    ) async -> [EditorMode] {
        await withTaskGroup(of: [EditorMode]?.self) { group in
            group.addTask {
                var seen: [EditorMode] = []
                for await status in statuses {
                    seen.append(status.mode)
                    if predicate(status.mode) { return seen }
                }
                return seen
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result ?? []
        }
    }

    private func startedSession(_ fixture: TemporaryProjectFixture) async throws -> NeovimEditorSession {
        fixture.write(
            "src/App.kt",
            contents: (1...20).map { "line \($0) text" }.joined(separator: "\n") + "\n"
        )
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        return session
    }

    /// Drags until a drag actually produces a selection, then returns to normal.
    ///
    /// Neovim ignores drags for a short window after start-up, and the window stretches under
    /// load — a fixed sleep passes alone and fails in a full run. The probe uses **the same
    /// coordinates the assertion will use**, because readiness at one place on the grid is not
    /// evidence of readiness at another; a probe that drags elsewhere can report ready while the
    /// real drag still does nothing.
    private func waitUntilDragSelects(_ session: NeovimEditorSession) async throws {
        for _ in 0..<80 {
            try await dragAcrossProbeArea(session)
            try await Task.sleep(for: .milliseconds(50))
            if try await session.currentNeovimMode()?.hasPrefix("v") == true {
                try await session.sendKeys("<Esc>")
                // 노멀로 실제 돌아왔는지 확인한다 — 비주얼로 남으면 이어지는 드래그가 모드를
                // 바꾸지 않아 스트림에 아무것도 실리지 않는다.
                for _ in 0..<20 {
                    try await Task.sleep(for: .milliseconds(25))
                    if try await session.currentNeovimMode() == "n" { return }
                }
                return
            }
        }
        Issue.record("드래그가 선택을 만들지 못했다 — 마우스 준비를 확인할 수 없다")
    }

    private func dragAcrossProbeArea(_ session: NeovimEditorSession) async throws {
        try await session.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 0, column: 0))

        // 누름이 실제로 처리된 뒤에 끌기를 보낸다.
        //
        // `nvim_input_mouse` 는 입력을 **큐에 넣고** 곧바로 돌아온다. 누름과 끌기를 연달아 밀어
        // 넣으면 한가한 기계에서는 대개 순서대로 소화되지만, 스위트 전체가 도는 동안에는 둘이
        // 한 번의 클릭으로 뭉개져 비주얼 모드가 아예 생기지 않는다. 왕복 요청 하나가 "여기까지
        // 처리됐다"는 확인이 된다 — 시간을 추측하는 게 아니라 순서를 강제하는 것이다.
        //
        // 놓은 **뒤에** 기다리는 것으로는 못 고친다. 5초를 기다려도 낫지 않았다(실측). 이미
        // 클릭으로 확정된 것을 나중에 기다린다고 드래그가 되지는 않는다.
        _ = try await session.currentNeovimMode()

        try await session.sendMouse(EditorMouseEvent(button: .left, action: .drag, row: 2, column: 5))

        // 사람은 선택이 생긴 것을 보고 손을 뗀다.
        _ = try await waitForCondition(timeout: .seconds(5)) {
            try await session.currentNeovimMode()?.hasPrefix("v") == true
        }

        try await session.sendMouse(EditorMouseEvent(button: .left, action: .release, row: 2, column: 5))
    }

    /// Polls instead of sleeping a guessed interval: returns as soon as it holds, and a real
    /// failure still fails — it just takes the deadline to say so.
    private func waitForCondition(
        timeout: Duration,
        _ condition: () async throws -> Bool
    ) async rethrows -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if try await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return try await condition()
    }

    @Test("드래그로 들어간 비주얼 모드가 상태 스트림까지 도달한다")
    func dragSelectionReachesTheStatusStream() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startedSession(fixture)
        defer { Task { await session.shutDown() } }

        try await waitUntilDragSelects(session)

        // 워밍업의 클릭과 본 드래그의 클릭이 같은 자리에서 연달아 일어나면 Neovim 이 더블클릭으로
        // 해석한다(`mousetime`, 기본 500ms). 그 창을 넘겨 보내야 드래그가 드래그로 읽힌다.
        try await Task.sleep(for: .milliseconds(600))

        let statuses = await session.statusUpdates()
        try await dragAcrossProbeArea(session)

        // Neovim 자신이 비주얼이어야 하고 — 그건 마우스 경로의 문제다.
        #expect(try await session.currentNeovimMode()?.hasPrefix("v") == true)

        // 그리고 그 사실이 상태 스트림에 실려야 한다 — 그건 전파 경로의 문제다. 둘은 다른 결함이라
        // 따로 단언한다. 하나만 보면 어느 쪽이 깨졌는지 알 수 없다.
        let modes = await modesUntil(statuses) { $0 == .visual }
        #expect(modes.contains(.visual), "상태 스트림이 실어나른 모드: \(modes)")
    }

    @Test("키 입력으로 들어간 삽입 모드도 상태 스트림까지 도달한다")
    func insertModeReachesTheStatusStream() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startedSession(fixture)
        defer { Task { await session.shutDown() } }

        let statuses = await session.statusUpdates()
        try await Task.sleep(for: .milliseconds(300))
        try await session.sendKeys("i")

        let modes = await modesUntil(statuses) { $0 == .insert }
        #expect(modes.contains(.insert), "상태 스트림이 실어나른 모드: \(modes)")
    }

    @Test("모드가 되돌아온 것도 실린다 — 표시가 한 방향으로만 움직이지 않는다")
    func returningToNormalAlsoReachesTheStream() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startedSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.sendKeys("i")
        _ = await modesUntil(await session.statusUpdates()) { $0 == .insert }

        let statuses = await session.statusUpdates()
        try await session.sendKeys("<Esc>")

        let modes = await modesUntil(statuses) { $0 == .normal }
        #expect(modes.contains(.normal), "상태 스트림이 실어나른 모드: \(modes)")
    }

    @Test("상태 스트림은 구독 시점의 모드를 먼저 재생한다 — 늦게 붙어도 비어 있지 않다")
    func streamReplaysTheModeAtSubscriptionTime() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startedSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.sendKeys("i")
        _ = await modesUntil(await session.statusUpdates()) { $0 == .insert }

        // 지금 붙는 구독자도 현재 모드를 즉시 받아야 한다.
        var replayed: EditorMode?
        for await status in await session.statusUpdates() {
            replayed = status.mode
            break
        }
        #expect(replayed == .insert)
    }
}
