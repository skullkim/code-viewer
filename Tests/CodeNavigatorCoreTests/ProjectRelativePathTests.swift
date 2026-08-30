import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// INV-6 says local file access stays inside the open project root. This is the one place that
/// decides it, so this is the one place to attack.
@Suite("프로젝트 루트 제한 — INV-6 의 단일 경계")
struct ProjectRelativePathTests {

    private func makeRoot() -> TemporaryProjectFixture {
        let fixture = TemporaryProjectFixture()
        fixture.write("README.md", contents: "# hello")
        fixture.write("docs/guide.md", contents: "# guide")
        return fixture
    }

    @Test("루트 안의 평범한 경로는 통과한다")
    func ordinaryPathsResolve() throws {
        let fixture = makeRoot()
        let resolved = try ProjectRelativePath.resolve("docs/guide.md", inProjectRoot: fixture.rootURL)
        #expect(resolved.relativePath == "docs/guide.md")
        #expect(FileManager.default.fileExists(atPath: resolved.url.path))
    }

    @Test("절대 경로는 거부한다", arguments: ["/etc/passwd", "/", "/tmp/x.md"])
    func absolutePathsAreRejected(path: String) {
        let fixture = makeRoot()
        #expect(throws: (any Error).self) {
            try ProjectRelativePath.resolve(path, inProjectRoot: fixture.rootURL)
        }
    }

    @Test("루트 밖으로 올라가는 경로는 거부한다",
          arguments: ["../secret.md", "../../etc/passwd", "docs/../../etc/passwd", ".."])
    func traversalIsRejected(path: String) {
        let fixture = makeRoot()
        #expect(throws: (any Error).self) {
            try ProjectRelativePath.resolve(path, inProjectRoot: fixture.rootURL)
        }
    }

    /// `..` is rejected as a whole segment only. A directory honestly named `docs..old` is not an
    /// attack, and a `contains("..")` check would refuse to open it.
    @Test("이름에 점 두 개가 들어간 정상 디렉토리는 막지 않는다")
    func dotsInsideANameAreNotTraversal() throws {
        let fixture = makeRoot()
        fixture.write("docs..old/note.md", contents: "old")
        let resolved = try ProjectRelativePath.resolve("docs..old/note.md", inProjectRoot: fixture.rootURL)
        #expect(resolved.relativePath == "docs..old/note.md")
    }

    /// The one a segment check alone does not catch: every segment is innocent and the path still
    /// lands outside the project.
    @Test("루트 밖을 가리키는 심링크는 거부한다 — 세그먼트 검사만으로는 못 잡는다")
    func symlinkEscapeIsRejected() throws {
        let fixture = makeRoot()
        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("outside-\(UUID().uuidString).md")
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        try FileManager.default.createSymbolicLink(
            at: fixture.rootURL.appendingPathComponent("escape.md"),
            withDestinationURL: outside
        )

        #expect(throws: (any Error).self) {
            try ProjectRelativePath.resolve("escape.md", inProjectRoot: fixture.rootURL)
        }
    }

    @Test("루트 안에 머무는 심링크는 통과한다 — 심링크 자체를 금지하는 게 아니다")
    func symlinkStayingInsideIsAllowed() throws {
        let fixture = makeRoot()
        try FileManager.default.createSymbolicLink(
            at: fixture.rootURL.appendingPathComponent("alias.md"),
            withDestinationURL: fixture.rootURL.appendingPathComponent("README.md")
        )
        let resolved = try ProjectRelativePath.resolve("alias.md", inProjectRoot: fixture.rootURL)
        #expect(resolved.url.lastPathComponent == "README.md")
    }

    @Test("없는 파일은 경로 위반이 아니라 없는 파일로 보고한다")
    func aMissingFileIsNotATraversalError() {
        let fixture = makeRoot()
        #expect(throws: NavigatorError.fileNotFound(path: "nope.md")) {
            try ProjectRelativePath.resolve("nope.md", inProjectRoot: fixture.rootURL)
        }
    }
}
