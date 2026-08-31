import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// One Neovim, a tabpage per project (ADR-0008).
///
/// The tabpage handles stay inside the session: they are msgpack values that mean nothing outside
/// this process, and putting them in the contract would make the application carry a token it
/// cannot inspect. The session keys them by the tab identity the application already has.
@Suite("편집기 프로젝트 탭 — 프로세스 하나, 탭페이지 N개", .serialized)
struct EditorProjectTabTests {

    private func startedSession(_ root: URL) async throws -> NeovimEditorSession {
        let session = NeovimEditorSession()
        try await session.start(projectRoot: root, columns: 80, rows: 24)
        return session
    }

    @Test("프로젝트마다 탭페이지가 생기고 각자 자기 루트를 작업 디렉토리로 갖는다")
    func eachProjectTabHasItsOwnWorkingDirectory() async throws {
        let first = TemporaryProjectFixture()
        let second = TemporaryProjectFixture()
        let session = try await startedSession(first.rootURL)
        // 던지는 경로용 보험. 그때는 프로세스가 계속 살아 있어 이 Task 가 실제로 돈다.
        defer { Task { await session.shutDown() } }

        let firstTab = ProjectTabIdentifier()
        let secondTab = ProjectTabIdentifier()
        try await session.openProjectTab(firstTab, root: first.rootURL)
        try await session.openProjectTab(secondTab, root: second.rootURL)

        try await session.activateProjectTab(firstTab)
        #expect(try await session.currentWorkingDirectoryForTesting() == first.rootURL.resolved())

        try await session.activateProjectTab(secondTab)
        #expect(try await session.currentWorkingDirectoryForTesting() == second.rootURL.resolved())
        // 명시적으로 기다린다. defer 의 분리된 Task 는 프로세스가 끝나면 그냥 버려지고,
        // 그러면 deinit 도 안 돌아 편집기가 부모 없이 남는다 — 이 스위트만 실행당 4개씩
        // 남기고 있었다. 남은 편집기는 SIGTERM 도 안 듣고 스스로 나가지도 않는다.
        await session.shutDown()
    }

    @Test("첫 프로젝트는 새 탭페이지를 만들지 않는다 — 빈 탭이 하나 남지 않게")
    func theFirstProjectReusesTheTabThatAlreadyExists() async throws {
        let first = TemporaryProjectFixture()
        let session = try await startedSession(first.rootURL)
        // 던지는 경로용 보험. 그때는 프로세스가 계속 살아 있어 이 Task 가 실제로 돈다.
        defer { Task { await session.shutDown() } }

        try await session.openProjectTab(ProjectTabIdentifier(), root: first.rootURL)
        #expect(try await session.tabPageCountForTesting() == 1)
        // 명시적으로 기다린다. defer 의 분리된 Task 는 프로세스가 끝나면 그냥 버려지고,
        // 그러면 deinit 도 안 돌아 편집기가 부모 없이 남는다 — 이 스위트만 실행당 4개씩
        // 남기고 있었다. 남은 편집기는 SIGTERM 도 안 듣고 스스로 나가지도 않는다.
        await session.shutDown()
    }

    @Test("탭을 닫으면 탭페이지가 사라진다")
    func closingATabRemovesItsTabPage() async throws {
        let first = TemporaryProjectFixture()
        let second = TemporaryProjectFixture()
        let session = try await startedSession(first.rootURL)
        // 던지는 경로용 보험. 그때는 프로세스가 계속 살아 있어 이 Task 가 실제로 돈다.
        defer { Task { await session.shutDown() } }

        let firstTab = ProjectTabIdentifier()
        let secondTab = ProjectTabIdentifier()
        try await session.openProjectTab(firstTab, root: first.rootURL)
        try await session.openProjectTab(secondTab, root: second.rootURL)
        #expect(try await session.tabPageCountForTesting() == 2)

        try await session.closeProjectTab(secondTab)
        #expect(try await session.tabPageCountForTesting() == 1)
        // 명시적으로 기다린다. defer 의 분리된 Task 는 프로세스가 끝나면 그냥 버려지고,
        // 그러면 deinit 도 안 돌아 편집기가 부모 없이 남는다 — 이 스위트만 실행당 4개씩
        // 남기고 있었다. 남은 편집기는 SIGTERM 도 안 듣고 스스로 나가지도 않는다.
        await session.shutDown()
    }

    /// The last tab is a special case in Neovim: `tabclose` refuses on the final tabpage with
    /// `E784`. Restarting the process instead would make the user pay the start-up cost again for
    /// closing a project, so the session stays and the tabpage is simply emptied.
    @Test("마지막 탭을 닫아도 세션은 살아 있다 — 다시 열 때 기동 비용을 다시 물지 않게")
    func closingTheLastTabKeepsTheSessionAlive() async throws {
        let first = TemporaryProjectFixture()
        let session = try await startedSession(first.rootURL)
        // 던지는 경로용 보험. 그때는 프로세스가 계속 살아 있어 이 Task 가 실제로 돈다.
        defer { Task { await session.shutDown() } }

        let onlyTab = ProjectTabIdentifier()
        try await session.openProjectTab(onlyTab, root: first.rootURL)
        try await session.closeProjectTab(onlyTab)

        #expect(await session.state() == .connected)
        // 명시적으로 기다린다. defer 의 분리된 Task 는 프로세스가 끝나면 그냥 버려지고,
        // 그러면 deinit 도 안 돌아 편집기가 부모 없이 남는다 — 이 스위트만 실행당 4개씩
        // 남기고 있었다. 남은 편집기는 SIGTERM 도 안 듣고 스스로 나가지도 않는다.
        await session.shutDown()
    }

    /// Neovim draws its own tab line by default. The application draws the tab bar, so two would
    /// appear and every grid row would be off by one — and it only shows up with two or more
    /// tabpages, so a single-tab test would never catch it.
    @Test("Neovim 이 자기 탭줄을 그리지 않는다 — 탭 2개 이상에서만 드러나는 어긋남")
    func neovimDrawsNoTabLineOfItsOwn() async throws {
        let first = TemporaryProjectFixture()
        let second = TemporaryProjectFixture()
        let session = try await startedSession(first.rootURL)
        // 던지는 경로용 보험. 그때는 프로세스가 계속 살아 있어 이 Task 가 실제로 돈다.
        defer { Task { await session.shutDown() } }

        try await session.openProjectTab(ProjectTabIdentifier(), root: first.rootURL)
        try await session.openProjectTab(ProjectTabIdentifier(), root: second.rootURL)

        #expect(try await session.showTabLineSettingForTesting() == 0)
        // 명시적으로 기다린다. defer 의 분리된 Task 는 프로세스가 끝나면 그냥 버려지고,
        // 그러면 deinit 도 안 돌아 편집기가 부모 없이 남는다 — 이 스위트만 실행당 4개씩
        // 남기고 있었다. 남은 편집기는 SIGTERM 도 안 듣고 스스로 나가지도 않는다.
        await session.shutDown()
    }
}

private extension URL {
    /// The path as the operating system reports it, so comparisons are not defeated by `/var`
    /// against `/private/var`.
    func resolved() -> String {
        guard let pointer = realpath(path, nil) else { return path }
        defer { free(pointer) }
        return String(cString: pointer)
    }
}
