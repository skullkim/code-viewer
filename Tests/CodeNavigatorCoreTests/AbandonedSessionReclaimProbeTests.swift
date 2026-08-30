import Testing
import Foundation
@testable import CodeNavigatorCore

/// Abandoning sessions must not leave editors running.
///
/// In the full suite this looked like a flake — one run in three, a different test each time. It
/// is not random: start several sessions **concurrently**, keep them all alive, then drop them all
/// at once without `shutDown()`. Before the fix, three of four editors were still running fifteen
/// seconds later. Dropping them one at a time does not reproduce it, and CPU load alone does not
/// either; what matters is that several live at once.
///
/// What made it hard to see is that every wrong answer looked like a right one. The sessions and
/// channels all deallocated and `deinit` ran, so it was not a retain cycle. The survivors were in
/// state `S`, not `Z`, so they were not unreaped zombies. And SIGTERM did nothing at all — twenty
/// seconds, every process still alive — which is why the teardown now escalates.
@Suite("버려진 세션은 편집기를 남기지 않는다 (D-2)", .serialized)
struct AbandonedSessionReclaimProbeTests {

    private func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

    @Test("여러 세션을 동시에 띄웠다 한꺼번에 버려도 전부 회수된다", arguments: [4, 8])
    func abandoningConcurrentSessionsReclaimsAll(sessionCount: Int) async throws {
        var pids: [Int32] = []
        // 전부 동시에 살려 둔 뒤 한꺼번에 놓는다. 순차로 하나씩 버리면 각자 조용한 순간에
        // 회수돼 재현되지 않는다 — 결함이 나타나는 상황은 여럿이 겹쳐 사는 쪽이다.
        var sessions: [NeovimEditorSession] = []
        try await withThrowingTaskGroup(of: NeovimEditorSession.self) { group in
            for _ in 0..<sessionCount {
                group.addTask {
                    let fixture = TemporaryProjectFixture()
                    fixture.write("src/App.kt", contents: "class Application")
                    let session = NeovimEditorSession()
                    try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
                    return session
                }
            }
            for try await session in group { sessions.append(session) }
        }
        for session in sessions {
            if let pid = await session.processIdentifierForTesting() { pids.append(pid) }
        }

        #expect(pids.count == sessionCount, "전제: 전부 떠 있어야 한다")
        sessions.removeAll()  // 여기서 전부 버려진다 — shutDown() 없이.

        let startedAt = ContinuousClock.now
        let deadline = startedAt + .seconds(15)
        var alive = pids.filter(isAlive)
        while !alive.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            alive = pids.filter(isAlive)
        }
        let elapsed = startedAt.duration(to: .now)
        print("[동시회수] \(sessionCount)개 중 남은 것 \(alive.count) — \(elapsed)")

        // 남았다면 이 검사가 치운다. 안 그러면 실패가 다음 실행의 부하가 된다.
        for pid in alive { kill(pid, SIGKILL) }
        #expect(alive.isEmpty, "\(sessionCount)개를 버렸는데 \(alive.count)개가 남았다")
    }
}
