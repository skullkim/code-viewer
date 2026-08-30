import Testing
import Foundation
@testable import CodeNavigatorCore

/// Deterministic reproduction of the intermittent orphan (D-2, reopened).
///
/// In the full suite this looked like a flake — one run in three. Here it is 100%: start several
/// sessions **concurrently**, keep them all alive, then drop them all at once without calling
/// `shutDown()`. Three of four editors are still running fifteen seconds later. Dropping them one
/// at a time does not reproduce it, and CPU load alone does not either; what matters is that
/// several live at once.
///
/// Suspected mechanism, **not yet proven**: notifications buffer without bound, so each arrival
/// enqueues a job on the session actor. While a job is pending the actor cannot be released, so
/// the channel it owns is not released, so `deinit` never terminates Neovim — which keeps sending
/// notifications. It sustains itself, and it only sustains when the queue drains slower than it
/// fills, which is why one session is fine and four are not.
///
/// Disabled so a known defect does not block the gate; delete the trait to enforce it.
@Suite("버려진 세션 회수 — 동시성 재현", .serialized,
       .disabled("D-2 재개봉: 결함이 고쳐질 때까지 게이트를 막지 않도록 꺼 둔다. 켜면 100% 재현한다."))
struct AbandonedSessionReclaimProbeTests {

    private func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

    @Test("여러 세션을 동시에 띄웠다 버려도 전부 회수된다", arguments: [4, 8])
    func abandoningConcurrentSessionsReclaimsAll(sessionCount: Int) async throws {
        var pids: [Int32] = []
        // 전부 동시에 살려 둔 뒤 한꺼번에 놓는다. 순차로 하나씩 버리면 각자 조용한 순간에
        // 회수돼 재현되지 않는다 — 스위트가 만드는 상황은 여럿이 겹쳐 사는 쪽이다.
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
        sessions.removeAll()  // 여기서 전부 버려진다 — shutDown() 없이.

        #expect(pids.count == sessionCount, "전제: 전부 떠 있어야 한다")

        let startedAt = ContinuousClock.now
        let deadline = startedAt + .seconds(15)
        var alive = pids.filter(isAlive)
        while !alive.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            alive = pids.filter(isAlive)
        }
        let elapsed = startedAt.duration(to: .now)
        print("[동시회수] \(sessionCount)개 중 남은 것 \(alive.count) — \(elapsed)")
        for pid in alive { kill(pid, SIGKILL) }
        #expect(alive.isEmpty, "\(sessionCount)개를 버렸는데 \(alive.count)개가 남았다")
    }
}
