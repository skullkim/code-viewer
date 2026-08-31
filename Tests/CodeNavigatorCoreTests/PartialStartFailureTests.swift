import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Starting a project starts two things at once. When one fails, the other may already have
/// succeeded — and a half that nobody owns is worse than a clean failure: a live Neovim the app
/// cannot see, cannot shut down, and leaves behind when it quits.
@Suite("부분 실패 — 성공한 절반을 남기지 않는다", .serialized)
struct PartialStartFailureTests {

    private func isAlive(_ processIdentifier: Int32) -> Bool {
        kill(processIdentifier, 0) == 0
    }

    /// Waits for the child to actually disappear. "Gone" is an eventual property — the parent has
    /// to reap the process — so a single immediate check would fail for a timing reason rather
    /// than a real leak. Reports how long it took so a regression shows up as a slowdown too.
    private func waitUntilGone(_ processIdentifier: Int32, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isAlive(processIdentifier) { return true }
            usleep(20_000)
        }
        return !isAlive(processIdentifier)
    }

    /// A directory the process cannot read, which is what a denied macOS permission looks like.
    private func makeUnreadableDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("unreadable-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        return url
    }

    private func restore(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - The orphan

    @Test("읽을 수 없는 루트는 조용히 성공하지 않는다 — 빈 프로젝트로 위장 금지")
    func unreadableRootIsAnErrorNotAnEmptyProject() async throws {
        let unreadable = makeUnreadableDirectory()
        defer { restore(unreadable) }

        #expect(throws: (any Error).self) {
            try ProjectScanner().scan(rootPath: unreadable)
        }
        await #expect(throws: (any Error).self) {
            try await ProjectEngine().openProject(at: unreadable)
        }
    }

    @Test("읽을 수 없는 하위 디렉토리는 건너뛴다 — 폴더 하나가 인덱싱 전체를 막지 않는다")
    func unreadableSubdirectoryIsSkippedNotFatal() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        fixture.makeDirectory("locked")
        let locked = fixture.rootURL.appendingPathComponent("locked")
        try? FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        // 루트는 읽을 수 있으므로 스캔은 성공해야 하고, 읽히는 것은 다 나와야 한다.
        let scan = try ProjectScanner().scan(rootPath: fixture.rootURL)
        #expect(scan.filePaths.contains("src/App.kt"))
    }
}
