import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Reading project files for the render view, per tab.
///
/// These live on the workspace rather than on a single-project engine because rendering belongs to
/// a project and there are now several open at once. One door for text and one for bytes, both
/// through `ProjectRelativePath`, so INV-6's root restriction is enforced at a boundary instead of
/// being remembered at each call site — a second reader with its own rules is how the two rules
/// drift apart, and the weaker one becomes the real one.
@Suite("워크스페이스 렌더 읽기 — 탭 단위, 문은 하나", .serialized)
struct WorkspaceRenderReadingTests {

    private func makeWorkspace() -> ProjectWorkspaceEngine {
        ProjectWorkspaceEngine(columns: 80, rows: 24, editorExecutableOverridePath: "/nonexistent/nvim")
    }

    @Test("탭의 문서를 읽는다 — 그 탭의 루트 기준으로")
    func readsADocumentFromItsOwnTab() async throws {
        let alpha = TemporaryProjectFixture()
        alpha.write("README.md", contents: "# alpha")
        let beta = TemporaryProjectFixture()
        beta.write("README.md", contents: "# beta")
        let workspace = makeWorkspace()

        let first = try await workspace.openProject(at: alpha.rootURL)
        let second = try await workspace.openProject(at: beta.rootURL)

        // 같은 상대 경로가 탭에 따라 다른 파일이다. 활성 탭이 아니라 인자가 정한다.
        let fromAlpha = try await workspace.renderSource(atRelativePath: "README.md", in: first.tab.id)
        let fromBeta = try await workspace.renderSource(atRelativePath: "README.md", in: second.tab.id)
        #expect(fromAlpha.text == "# alpha")
        #expect(fromBeta.text == "# beta")
        await workspace.shutDown()
    }

    @Test("리소스 바이트를 읽는다 — 이미지 인라인용")
    func readsResourceBytes() async throws {
        let fixture = TemporaryProjectFixture()
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try pngHeader.write(to: fixture.rootURL.appendingPathComponent("logo.png"))
        let workspace = makeWorkspace()
        let tab = try await workspace.openProject(at: fixture.rootURL)

        let bytes = try await workspace.renderResource(atRelativePath: "logo.png", in: tab.tab.id)
        #expect(bytes == pngHeader)
        await workspace.shutDown()
    }

    @Test("루트 밖을 가리키면 거부한다 (INV-6)")
    func refusesResourcesOutsideTheRoot() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("doc.md", contents: "x")
        let workspace = makeWorkspace()
        let tab = try await workspace.openProject(at: fixture.rootURL)

        await #expect(throws: NavigatorError.invalidPath("../escape.png")) {
            try await workspace.renderResource(atRelativePath: "../escape.png", in: tab.tab.id)
        }
        await workspace.shutDown()
    }

    /// The trap the render limit exists for. The indexer refuses at 1MiB and the render limit is
    /// 2MB, so a reader that borrowed the indexer's number would refuse files that must render —
    /// and a reader that reported "missing" instead of "too large" would leave the view blank,
    /// which is what REQ-013 AC-6 forbids.
    @Test("2MB 를 넘으면 없는 파일이 아니라 tooLarge 로 거부한다")
    func refusesOversizedResourcesWithAReason() async throws {
        let fixture = TemporaryProjectFixture()
        let big = Data(repeating: 0x41, count: RenderSource.maximumByteSize + 1_024)
        try big.write(to: fixture.rootURL.appendingPathComponent("huge.png"))
        let workspace = makeWorkspace()
        let tab = try await workspace.openProject(at: fixture.rootURL)

        do {
            _ = try await workspace.renderResource(atRelativePath: "huge.png", in: tab.tab.id)
            Issue.record("2MB 초과인데 통과했다")
        } catch let error as NavigatorError {
            guard case .fileTooLarge(_, let byteSize, let limit) = error else {
                Issue.record("이유가 tooLarge 가 아니다: \(error)")
                return
            }
            #expect(byteSize > limit)
            #expect(limit == RenderSource.maximumByteSize, "인덱서 상한을 빌려 쓰고 있다")
        }
        await workspace.shutDown()
    }

    @Test("1MiB 를 넘고 2MB 이하인 리소스는 통과한다 — 인덱서 상한을 빌리면 여기서 걸린다")
    func acceptsResourcesBetweenTheTwoLimits() async throws {
        let fixture = TemporaryProjectFixture()
        let between = Data(repeating: 0x41, count: 1_500_000)
        try between.write(to: fixture.rootURL.appendingPathComponent("mid.png"))
        let workspace = makeWorkspace()
        let tab = try await workspace.openProject(at: fixture.rootURL)

        let bytes = try await workspace.renderResource(atRelativePath: "mid.png", in: tab.tab.id)
        #expect(bytes.count == 1_500_000)
        await workspace.shutDown()
    }

    @Test("닫힌 탭으로는 읽을 수 없다")
    func aClosedTabCannotBeRead() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("doc.md", contents: "x")
        let workspace = makeWorkspace()
        let tab = try await workspace.openProject(at: fixture.rootURL)
        try await workspace.closeTab(tab.tab.id)

        await #expect(throws: NavigatorError.noProjectOpen) {
            try await workspace.renderSource(atRelativePath: "doc.md", in: tab.tab.id)
        }
        await workspace.shutDown()
    }
}
