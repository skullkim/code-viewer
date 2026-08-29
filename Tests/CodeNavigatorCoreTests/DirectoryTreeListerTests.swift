import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-003 AC-1 (한 레벨 지연 로드) · AC-2 (제외 대상은 트리에 없다)
@Suite("DirectoryTreeLister")
struct DirectoryTreeListerTests {

    private func list(
        _ fixture: TemporaryProjectFixture,
        at relativePath: String = ""
    ) throws -> [DirectoryEntry] {
        try DirectoryTreeLister().list(relativePath: relativePath, rootPath: fixture.rootURL)
    }

    // 한 레벨만 — 트리는 펼칠 때 로드된다.

    @Test("루트를 나열하면 최상위 항목만 나온다")
    func listsOnlyOneLevelAtRoot() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("README.md")
        fixture.write("src/App.kt")
        fixture.write("src/deep/Nested.kt")

        let entries = try list(fixture)

        #expect(entries.map(\.name) == ["src", "README.md"])
        #expect(entries.map(\.path) == ["src", "README.md"])
    }

    @Test("하위 디렉토리를 나열하면 그 디렉토리의 항목만 나온다")
    func listsOneLevelInSubdirectory() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt")
        fixture.write("src/deep/Nested.kt")

        let entries = try list(fixture, at: "src")

        #expect(entries.map(\.name) == ["deep", "App.kt"])
        #expect(entries.map(\.path) == ["src/deep", "src/App.kt"])
        #expect(entries.map(\.isDirectory) == [true, false])
    }

    @Test("디렉토리가 먼저, 그다음 이름 오름차순으로 정렬된다")
    func sortsDirectoriesFirstThenByName() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("b.kt")
        fixture.write("a.kt")
        fixture.write("zeta/x.kt")
        fixture.write("alpha/y.kt")

        let entries = try list(fixture)

        #expect(entries.map(\.name) == ["alpha", "zeta", "a.kt", "b.kt"])
    }

    // 제외 — 트리에 보이는 것과 인덱싱되는 것이 어긋나면 안 된다.

    @Test("기본 제외 디렉토리와 숨김 항목은 나오지 않는다")
    func hidesExcludedAndHiddenEntries() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt")
        fixture.write("node_modules/pkg/index.js")
        fixture.write("build/output.jar")
        fixture.write(".env")
        fixture.makeDirectory(".git")

        let entries = try list(fixture)

        #expect(entries.map(\.name) == ["src"])
    }

    @Test("gitignore 대상은 나오지 않는다")
    func hidesGitignoredEntries() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write(".gitignore", contents: "secrets.txt\ngenerated/\n")
        fixture.write("secrets.txt")
        fixture.write("keep.txt")
        fixture.write("generated/output.kt")

        let entries = try list(fixture)

        #expect(entries.map(\.name) == ["keep.txt"])
    }

    @Test("중첩 gitignore가 해당 디렉토리 안에서 적용된다")
    func appliesNestedGitignore() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/.gitignore", contents: "ignored.kt\n")
        fixture.write("src/ignored.kt")
        fixture.write("src/kept.kt")
        fixture.write("ignored.kt")

        #expect(try list(fixture, at: "src").map(\.name) == ["kept.kt"])
        // 같은 이름이라도 상위 디렉토리에는 그 규칙이 적용되지 않는다.
        #expect(try list(fixture).map(\.name) == ["src", "ignored.kt"])
    }

    @Test("심볼릭 링크는 나열되지 않는다")
    func skipsSymbolicLinks() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("real.kt")
        fixture.makeSymbolicLink(at: "link.kt", pointingTo: "real.kt")

        #expect(try list(fixture).map(\.name) == ["real.kt"])
    }

    @Test("내용이 전부 제외된 디렉토리는 빈 배열로 성공한다")
    func emptyAfterExclusionsSucceedsWithNoEntries() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("tools/.hidden")

        // 존재하지 않는 것과 구분되어야 한다 — 던지지 않고 빈 배열이다.
        #expect(try list(fixture, at: "tools").isEmpty)
    }

    // 경로 검증.

    @Test("상위 경로 세그먼트는 거부된다")
    func rejectsParentDirectorySegments() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt")

        #expect(throws: NavigatorError.invalidPath("..")) {
            try list(fixture, at: "..")
        }
        #expect(throws: NavigatorError.invalidPath("src/../src")) {
            try list(fixture, at: "src/../src")
        }
    }

    @Test("이름에 점 두 개가 들어간 정상 디렉토리는 거부되지 않는다")
    func allowsNamesContainingTwoDots() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("docs..old/notes.md")

        // 부분 문자열 검사로 ".."를 막으면 이 정상 경로가 함께 막힌다.
        #expect(try list(fixture, at: "docs..old").map(\.name) == ["notes.md"])
    }

    @Test("절대 경로는 거부된다")
    func rejectsAbsolutePaths() throws {
        let fixture = TemporaryProjectFixture()

        #expect(throws: NavigatorError.invalidPath("/etc")) {
            try list(fixture, at: "/etc")
        }
    }

    @Test("읽을 수 없는 디렉토리는 빈 목록이 아니라 에러로 실패한다")
    func unreadableDirectoryFailsInsteadOfLookingEmpty() throws {
        // root로 돌면 권한 검사가 통과해 버려 이 케이스를 만들 수 없다.
        guard getuid() != 0 else { return }

        let fixture = TemporaryProjectFixture()
        fixture.write("locked/inside.kt")
        let lockedPath = fixture.rootURL.appendingPathComponent("locked").path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedPath)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedPath)
        }

        let expected = NavigatorError.projectNotReadable(
            path: "locked",
            reason: "디렉토리를 읽을 수 없습니다"
        )
        #expect(throws: expected) {
            try list(fixture, at: "locked")
        }
    }

    @Test("없는 경로와 파일 요청은 파일 없음으로 실패한다")
    func missingPathAndFileRequestFail() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt")

        #expect(throws: NavigatorError.fileNotFound(path: "nope")) {
            try list(fixture, at: "nope")
        }
        #expect(throws: NavigatorError.fileNotFound(path: "src/App.kt")) {
            try list(fixture, at: "src/App.kt")
        }
    }
}
