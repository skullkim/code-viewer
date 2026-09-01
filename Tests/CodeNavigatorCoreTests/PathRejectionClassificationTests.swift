import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: INV-6 (프로젝트 밖 접근 금지) 의 거절 이유 분류 — BUILD_COMPLETE 인증 후 처리 2번
///
/// `invalidPath` 하나가 **네 가지 다른 상황**을 받고 있었다:
///
/// | 상황 | 무엇인가 |
/// |---|---|
/// | 절대 경로를 줬다 | 계약 오용 — 상대 경로를 달라고 했는데 아니다 |
/// | 빈 경로를 줬다 | 계약 오용 |
/// | `..` 로 올라가려 했다 | **보안 거절** — INV-6 |
/// | 심링크가 밖을 가리킨다 | **보안 거절** — INV-6 |
///
/// 앞의 둘은 "그렇게 부르면 안 된다"이고 뒤의 둘은 "그건 프로젝트 밖이다"이다. 하나로 뭉개면
/// 사용자는 오타와 차단을 같은 문장으로 듣고, 로그를 읽는 쪽은 **실제 탈출 시도를 오타로 본다.**
/// 여기서 넷을 갈라 둘로 만든다 — 원인이 넷이어도 답은 둘이고, 그 둘은 서로 다른 답이다.
@Suite("경로 거절 이유 분류 (INV-6)")
struct PathRejectionClassificationTests {

    private func makeFixture() -> TemporaryProjectFixture {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/inside.txt", contents: "inside\n")
        return fixture
    }

    // MARK: - 계약 오용

    @Test("절대 경로는 계약 오용이다 — 보안 거절이 아니다")
    func anAbsolutePathIsAContractMisuse() throws {
        let fixture = makeFixture()
        #expect(throws: NavigatorError.invalidPath("/etc/passwd")) {
            try ProjectRelativePath.resolve("/etc/passwd", inProjectRoot: fixture.rootURL)
        }
    }

    @Test("빈 경로는 계약 오용이다")
    func anEmptyPathIsAContractMisuse() throws {
        let fixture = makeFixture()
        #expect(throws: NavigatorError.invalidPath("")) {
            try ProjectRelativePath.resolve("", inProjectRoot: fixture.rootURL)
        }
        // `.` 만 있는 경로도 걸러지면 남는 세그먼트가 없다 — 같은 계약 오용이다.
        #expect(throws: NavigatorError.invalidPath("./.")) {
            try ProjectRelativePath.resolve("./.", inProjectRoot: fixture.rootURL)
        }
    }

    // MARK: - 보안 거절 (INV-6)

    @Test("올라가는 경로는 보안 거절이다 — 오타가 아니다")
    func aClimbingPathIsRefusedForLeavingTheProject() throws {
        let fixture = makeFixture()
        #expect(throws: NavigatorError.pathOutsideProject("../outside.txt")) {
            try ProjectRelativePath.resolve("../outside.txt", inProjectRoot: fixture.rootURL)
        }
        #expect(throws: NavigatorError.pathOutsideProject("src/../../outside.txt")) {
            try ProjectRelativePath.resolve("src/../../outside.txt", inProjectRoot: fixture.rootURL)
        }
    }

    /// 세그먼트가 전부 결백한데 파일이 밖에 있는 경우. `..` 검사로는 절대 안 잡힌다.
    @Test("밖을 가리키는 심링크는 보안 거절이다")
    func aSymbolicLinkLeavingTheProjectIsRefused() throws {
        let fixture = makeFixture()
        let outsideDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("code-navigator-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideDirectory) }

        let secret = outsideDirectory.appendingPathComponent("secret.txt")
        try "secret\n".write(to: secret, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: fixture.rootURL.appendingPathComponent("link.txt"), withDestinationURL: secret
        )

        #expect(throws: NavigatorError.pathOutsideProject("link.txt")) {
            try ProjectRelativePath.resolve("link.txt", inProjectRoot: fixture.rootURL)
        }
    }

    @Test("프로젝트 안의 파일은 통과한다 — 거절이 전부를 막지 않는다")
    func aFileInsideTheProjectResolves() throws {
        let fixture = makeFixture()
        let resolved = try ProjectRelativePath.resolve("src/inside.txt", inProjectRoot: fixture.rootURL)
        #expect(resolved.relativePath == "src/inside.txt")
    }

    /// 없는 파일은 없다고 말한다. 오타를 보안 문제로 부르면 사용자는 배울 것이 없다.
    @Test("없는 파일은 여전히 '없음'이지 거절이 아니다")
    func aMissingFileIsStillReportedAsMissing() throws {
        let fixture = makeFixture()
        #expect(throws: NavigatorError.fileNotFound(path: "src/typo.txt")) {
            try ProjectRelativePath.resolve("src/typo.txt", inProjectRoot: fixture.rootURL)
        }
    }

    // MARK: - 다른 두 진입점도 같은 분류를 쓴다

    @Test("트리 나열도 같은 두 이유로 갈린다")
    func listingADirectoryUsesTheSameTwoReasons() throws {
        let fixture = makeFixture()
        let lister = DirectoryTreeLister()

        #expect(throws: NavigatorError.invalidPath("/etc")) {
            try lister.list(relativePath: "/etc", rootPath: fixture.rootURL)
        }
        #expect(throws: NavigatorError.pathOutsideProject("../..")) {
            try lister.list(relativePath: "../..", rootPath: fixture.rootURL)
        }
    }

    @Test("편집기 열기도 밖으로 나가는 경로를 보안 거절로 말한다")
    func openingAFileOutsideTheProjectIsRefusedAsSuch() async throws {
        let fixture = makeFixture()
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 12)
        defer { Task { await session.shutDown() } }

        await #expect(throws: NavigatorError.pathOutsideProject("../outside.txt")) {
            try await session.openFile(atRelativePath: "../outside.txt", line: nil, recordJump: false)
        }
    }

    // MARK: - 두 이유가 서로 다른 문장을 말한다

    @Test("두 거절이 사용자에게 다른 문장을 말한다")
    func theTwoRefusalsReadDifferently() {
        let misuse = NavigatorError.invalidPath("x")
        let refusal = NavigatorError.pathOutsideProject("x")
        #expect(misuse.errorDescription != refusal.errorDescription)
        #expect(refusal.errorDescription?.contains("프로젝트") == true)
    }
}
