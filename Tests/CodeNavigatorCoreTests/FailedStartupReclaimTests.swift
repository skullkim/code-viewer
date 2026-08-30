import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// A start-up that fails must not leave its process behind — and retrying must not stack them up.
///
/// Timeout is the dangerous shape here: nothing "threw" from the process's point of view, it
/// simply never answered. A cleanup path that only runs on an exception misses it entirely, and
/// because the user's response to a timeout is to press retry, the leak multiplies exactly when
/// it is most likely to happen.
@Suite("실패한 기동은 프로세스를 남기지 않는다", .serialized)
struct FailedStartupReclaimTests {

    /// A fake editor that answers `--version` but never speaks msgpack, and records its own pid
    /// so the test can check for it after the session gives up.
    private func makeMuteEditor(_ fixture: TemporaryProjectFixture, pidFile: String) throws -> String {
        let script = fixture.write("mute-nvim", contents: """
        #!/bin/sh
        case "$1" in
          --version) echo "NVIM v0.12.5"; exit 0 ;;
        esac
        echo $$ >> \(pidFile)
        sleep 120
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    private func recordedPids(_ pidFile: String) -> [Int32] {
        (try? String(contentsOfFile: pidFile, encoding: .utf8))?
            .split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) } ?? []
    }

    private func stillAlive(_ pids: [Int32]) -> [Int32] {
        pids.filter { kill($0, 0) == 0 }
    }

    private func cleanUp(_ pids: [Int32]) {
        for pid in pids { kill(pid, SIGKILL) }
    }

    @Test("응답 없는 기동이 실패하면 띄운 프로세스가 남지 않는다")
    func timedOutStartupReclaimsItsProcess() async throws {
        let fixture = TemporaryProjectFixture()
        let pidFile = fixture.rootURL.appendingPathComponent("pids.txt").path
        let editor = try makeMuteEditor(fixture, pidFile: pidFile)

        let session = NeovimEditorSession(
            executableLocator: NeovimExecutableLocator(wellKnownPaths: []),
            executableOverridePath: editor
        )
        await #expect(throws: (any Error).self) {
            try await session.startForTesting(
                projectRoot: fixture.rootURL, columns: 80, rows: 24,
                startupTimeout: .milliseconds(400)
            )
        }

        let pids = recordedPids(pidFile)
        #expect(pids.count == 1, "가짜 편집기가 한 번 떠야 한다: \(pids)")

        // 정리는 즉시가 아닐 수 있으므로 잠깐 폴링한다.
        var survivors = stillAlive(pids)
        for _ in 0..<40 where !survivors.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            survivors = stillAlive(pids)
        }
        cleanUp(pids)
        #expect(survivors.isEmpty, "타임아웃으로 실패한 기동이 프로세스를 남겼다: \(survivors)")
    }

    @Test("'다시 확인'을 반복해도 프로세스가 쌓이지 않는다 — D-7이 흔하므로 흔한 경로다")
    func repeatedRetriesDoNotAccumulateProcesses() async throws {
        let fixture = TemporaryProjectFixture()
        let pidFile = fixture.rootURL.appendingPathComponent("pids.txt").path
        let editor = try makeMuteEditor(fixture, pidFile: pidFile)

        let session = NeovimEditorSession(
            executableLocator: NeovimExecutableLocator(wellKnownPaths: []),
            executableOverridePath: editor
        )

        // 사용자가 실패 카드에서 '다시 확인'을 세 번 누른 상황.
        for _ in 0..<3 {
            _ = try? await session.startForTesting(
                projectRoot: fixture.rootURL, columns: 80, rows: 24,
                startupTimeout: .milliseconds(300)
            )
        }

        let pids = recordedPids(pidFile)
        #expect(pids.count == 3, "세 번 시도했으니 세 번 떠야 한다: \(pids)")

        var survivors = stillAlive(pids)
        for _ in 0..<40 where !survivors.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            survivors = stillAlive(pids)
        }
        cleanUp(pids)
        #expect(survivors.isEmpty, "재시도가 이전 프로세스를 회수하지 않았다: \(survivors)")
    }

    @Test("restart() 도 이전 프로세스를 회수한다")
    func restartReclaimsThePreviousProcess() async throws {
        let fixture = TemporaryProjectFixture()
        let pidFile = fixture.rootURL.appendingPathComponent("pids.txt").path
        let editor = try makeMuteEditor(fixture, pidFile: pidFile)

        let session = NeovimEditorSession(
            executableLocator: NeovimExecutableLocator(wellKnownPaths: []),
            executableOverridePath: editor
        )
        _ = try? await session.startForTesting(
            projectRoot: fixture.rootURL, columns: 80, rows: 24, startupTimeout: .milliseconds(300)
        )
        _ = try? await session.restart()

        let pids = recordedPids(pidFile)
        var survivors = stillAlive(pids)
        for _ in 0..<40 where !survivors.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            survivors = stillAlive(pids)
        }
        cleanUp(pids)
        #expect(survivors.isEmpty, "재기동이 이전 프로세스를 회수하지 않았다: \(survivors)")
    }
}

/// A session that is simply dropped — no `shutDown()` — must not leave its editor running.
///
/// This is the shape a retry takes when the interface builds a *new* session instead of reusing
/// the old one: the previous object goes out of scope holding a live process, and nothing in the
/// contract obliges the caller to have said goodbye first.
@Suite("버려진 세션도 프로세스를 남기지 않는다", .serialized)
struct AbandonedSessionTests {

    private func aliveCount(_ pids: [Int32]) -> Int {
        pids.filter { kill($0, 0) == 0 }.count
    }

    @Test("shutDown() 없이 버려진 세션의 편집기가 사라진다")
    func droppingASessionWithoutShutDownStillReclaims() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")

        var identifier: Int32?
        do {
            let session = NeovimEditorSession()
            try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
            identifier = await session.processIdentifierForTesting()
            #expect(identifier != nil)
            #expect(aliveCount([identifier!]) == 1, "기동 직후에는 살아 있어야 한다")
            // 여기서 session 이 범위를 벗어난다 — shutDown() 을 부르지 않는다.
        }

        let pid = try #require(identifier)
        // 회수는 ARC 해제 → deinit → SIGTERM → 종료까지 걸리는 일이라 즉시가 아니다.
        // 얼마나 걸렸는지 남긴다 — 마감을 늘려 플레이크를 덮는 대신 분포를 보고 정하기 위해.
        let startedAt = ContinuousClock.now
        var alive = aliveCount([pid])
        let deadline = startedAt + .seconds(10)
        while alive > 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            alive = aliveCount([pid])
        }
        let elapsed = startedAt.duration(to: .now)
        print("[회수] 버려진 세션의 자식이 사라지기까지 \(elapsed)")
        if alive > 0 { kill(pid, SIGKILL) }
        #expect(alive == 0, "세션을 버렸는데 편집기 \(pid) 이 \(elapsed) 이 지나도 남았다")
    }
}
