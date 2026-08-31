import Foundation

/// Keeps the test suite out of the user's real Neovim state.
///
/// Every Neovim this suite starts is a normal one, so it writes the user's ShaDa file — marks,
/// registers, command history, shared with their terminal editor. And this suite kills editors on
/// purpose: the D-2 checks abandon them, the teardown escalates to SIGKILL when SIGTERM is refused.
/// A process killed mid-write leaves a `main.shada.tmp.X` behind.
///
/// Measured on this machine before the fix: **26 leftover temp files**, at which point Neovim
/// refuses outright — `E138: All main.shada.tmp.X files exist, cannot write ShaDa file!`. The
/// user's own editor had stopped saving marks and history entirely.
///
/// ⚠ Note for anyone checking whether this still works: **counting the user's shada directory
/// proves nothing while it is in that state.** Once the temp files are full, the count stays
/// frozen whether or not this isolation is in place — the breakage imitates the fix. The test
/// below asks Neovim where its state actually is, which is the only evidence that separates them.
///
/// So the suite gets its own state directory. This is deliberately **test-only**: whether the
/// product should share the user's ShaDa or keep its own is a question about what a user wants
/// from an embedded editor, and that decision is not ours to make from inside a test helper.
enum NeovimTestStateIsolation {

    /// Redirects Neovim's state away from the user's home, once per process.
    ///
    /// `Process` inherits this process's environment when none is set explicitly, so setting it
    /// here reaches every editor the suite starts without any of them having to remember to ask.
    /// A helper each spawn site must opt into is one somebody eventually forgets.
    static let applied: Void = {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("code-navigator-nvim-state", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Both, because which one holds ShaDa moved between Neovim versions and this suite should
        // not depend on which one is installed.
        setenv("XDG_STATE_HOME", base.path, 1)
        setenv("XDG_DATA_HOME", base.path, 1)
    }()
}

import Testing
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Guards the isolation itself. Without this, someone removing the redirect would break nothing
/// visible — the suite would go on passing while quietly corrupting the user's Neovim state again,
/// which is exactly how it went unnoticed the first time.
@Suite("테스트가 사용자의 Neovim 상태를 건드리지 않는다", .serialized)
struct NeovimTestStateIsolationTests {

    @Test("이 스위트가 띄운 편집기는 사용자 홈이 아니라 테스트 경로에 상태를 쓴다")
    func startedEditorsWriteStateOutsideTheUsersHome() async throws {
        let fixture = TemporaryProjectFixture()
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)

        // Neovim 자신에게 묻는다 — 우리가 무엇을 설정했는지가 아니라 그것이 실제로 먹혔는지다.
        let statePath = try await session.evaluateForTesting("stdpath('state')")
        await session.shutDown()

        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
        #expect(statePath.hasPrefix(home) == false,
                "편집기가 사용자 홈에 상태를 쓴다: \(statePath)")
        #expect(statePath.contains("code-navigator-nvim-state"),
                "테스트 전용 경로가 아니다: \(statePath)")
    }
}
