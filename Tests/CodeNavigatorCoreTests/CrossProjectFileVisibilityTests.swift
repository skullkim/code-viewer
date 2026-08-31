import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// ADR-0009 keeps one Neovim for every project, and Vim's buffer list is process-global. So a user
/// who types `:bnext` can land on a file belonging to a different open project. The application
/// never builds that path, but it cannot block it either.
///
/// The leader's condition for adopting ADR-0009 is that the situation be **visible**: INV-5 is
/// about a user not mistaking another project's file for their own, so reaching one is acceptable
/// exactly as long as the screen says where they are.
///
/// This measures the engine's half — whether the status the interface draws from carries enough to
/// tell the two apart. A project-relative name would not: two projects can both hold `README.md`.
@Suite("다른 프로젝트 파일에 닿으면 그것이 드러난다 (ADR-0009 조건)", .serialized)
struct CrossProjectFileVisibilityTests {

    private func firstStatus(
        from session: NeovimEditorSession,
        matching predicate: @escaping @Sendable (EditorStatus) -> Bool
    ) async throws -> EditorStatus? {
        let statuses = await session.statusUpdates()
        return await withTaskGroup(of: EditorStatus?.self) { group in
            group.addTask {
                for await status in statuses where predicate(status) {
                    return status
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    @Test("같은 이름의 파일이 두 프로젝트에 있어도 상태가 어느 쪽인지 말한다")
    func statusDistinguishesSameNamedFilesAcrossProjects() async throws {
        // 두 프로젝트가 같은 이름의 파일을 갖는다 — 상대 경로로는 구별이 불가능한 상황.
        let alpha = TemporaryProjectFixture()
        alpha.write("README.md", contents: "# alpha")
        let beta = TemporaryProjectFixture()
        beta.write("README.md", contents: "# beta")

        let session = NeovimEditorSession()
        try await session.start(projectRoot: alpha.rootURL, columns: 80, rows: 24)
        defer { Task { await session.shutDown() } }

        let alphaTab = ProjectTabIdentifier()
        try await session.openProjectTab(alphaTab, root: alpha.rootURL)
        try await session.openFile(atRelativePath: "README.md", line: 1, recordJump: false)

        let inAlpha = try await firstStatus(from: session) { $0.filePath?.hasSuffix("README.md") == true }
        let alphaPath = try #require(inAlpha?.filePath)

        // 이제 사용자가 Vim 명령으로 다른 프로젝트의 파일을 연다 — 앱이 만들지 않는 길이다.
        try await session.sendKeys(":edit \(beta.rootURL.appendingPathComponent("README.md").path)\r")

        let inBeta = try await firstStatus(from: session) {
            guard let path = $0.filePath else { return false }
            return path.hasSuffix("README.md") && path != alphaPath
        }
        let betaPath = try #require(inBeta?.filePath, "다른 프로젝트 파일을 열었는데 상태가 안 바뀌었다")

        // 절대 경로라야 구별된다. 프로젝트 상대 이름이면 둘 다 "README.md" 이고, 사용자는
        // 자기 프로젝트의 파일을 보고 있다고 믿는다 — INV-5 가 막으려는 바로 그 오인이다.
        #expect(alphaPath.hasPrefix("/"), "절대 경로가 아니다: \(alphaPath)")
        #expect(betaPath.hasPrefix("/"), "절대 경로가 아니다: \(betaPath)")
        #expect(alphaPath != betaPath)
        #expect(betaPath.contains(beta.rootURL.lastPathComponent),
                "상태가 가리키는 경로에 그 프로젝트가 드러나지 않는다: \(betaPath)")
    }
}
