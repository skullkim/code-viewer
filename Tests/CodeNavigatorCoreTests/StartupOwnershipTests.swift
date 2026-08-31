import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// `deinit` terminates the Neovim process, so the question "who holds the channel while it is
/// starting" stopped being bookkeeping and became load-bearing: a reference dropped for even a
/// moment during start-up would kill the editor that was just spawned, and the symptom would be
/// an application with no child process at all.
///
/// These pin the ownership that makes that impossible, so a later refactor that weakens a
/// reference fails here instead of in the field.
@Suite("기동 중 소유권 — 정리 코드가 정상 경로를 죽이지 않는다", .serialized)
struct StartupOwnershipTests {

    private func isAlive(_ processIdentifier: Int32) -> Bool {
        kill(processIdentifier, 0) == 0
    }

    @Test("세션만 붙들고 있어도 편집기는 계속 산다 — 리더 태스크의 weak self 가 죽이지 않는다")
    func theSessionAloneKeepsTheEditorAlive() async throws {
        let fixture = TemporaryProjectFixture()
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)

        let identifier = try #require(await session.processIdentifierForTesting())
        #expect(isAlive(identifier))

        // 리더 태스크가 self 를 약하게 잡는다. 그 태스크가 유일한 소유자였다면 여기서
        // 채널이 사라지고 deinit 이 프로세스를 죽인다. 세션이 붙들고 있으므로 살아야 한다.
        try await Task.sleep(for: .milliseconds(300))
        #expect(isAlive(identifier), "아무도 놓지 않았는데 nvim \(identifier) 이 죽었다")
        #expect(await session.state() == .connected)

        await session.shutDown()
    }

    /// The application's own ownership shape: it holds the workspace, the workspace holds the
    /// session, the session holds the channel. This used to be written against
    /// `CodeNavigatorEngine`, which nothing ships — so the shape it checked was not the app's.
    @Test("앱과 같은 소유 구조에서도 편집기가 살아 있다 — 워크스페이스만 붙들고 있는 경우")
    func theWorkspaceAloneKeepsTheEditorAlive() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        let workspace = ProjectWorkspaceEngine(columns: 80, rows: 24)
        _ = try await workspace.openProject(at: fixture.rootURL)

        let identifier = try #require(await workspace.editorSession.processIdentifierForTesting())
        try await Task.sleep(for: .milliseconds(300))

        #expect(isAlive(identifier), "워크스페이스가 살아 있는데 nvim \(identifier) 이 죽었다")
        #expect(await workspace.editorSession.state() == .connected)

        await workspace.shutDown()
    }

    /// The positive control. If dropping every reference did *not* kill the process, the two
    /// tests above would pass for a reason that has nothing to do with ownership.
    @Test("모두가 놓으면 편집기는 죽는다 — 위 두 검사가 실제로 무언가를 재고 있다는 증거")
    func droppingEveryReferenceDoesKillTheEditor() async throws {
        let fixture = TemporaryProjectFixture()
        var session: NeovimEditorSession? = NeovimEditorSession()
        try await session!.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        let identifier = try #require(await session!.processIdentifierForTesting())

        session = nil

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, isAlive(identifier) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!isAlive(identifier), "아무도 안 붙들고 있는데 nvim \(identifier) 이 남았다")
    }
}

/// `kill(0, …)` signals the whole process group, so a pid accessor that answers `0` for "no
/// process" hands every caller a loaded gun. This is small and it guards something large.
@Suite("프로세스 식별자는 0을 돌려주지 않는다")
struct ProcessIdentifierSafetyTests {

    @Test("기동하지 않은 채널의 pid 는 nil 이다 — 0 이면 kill 이 프로세스 그룹을 겨눈다")
    func anUnlaunchedChannelHasNoProcessIdentifier() async throws {
        let channel = NeovimChannel()
        #expect(await channel.processIdentifier == nil)
    }

    @Test("기동 실패한 세션의 pid 도 nil 이다")
    func aSessionThatFailedToLaunchHasNoProcessIdentifier() async throws {
        let session = NeovimEditorSession()
        let missing = URL(fileURLWithPath: "/nonexistent/project-\(UUID().uuidString)")
        _ = try? await session.start(projectRoot: missing, columns: 80, rows: 24)
        #expect(await session.processIdentifierForTesting() == nil)
    }
}
