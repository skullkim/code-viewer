import Testing
import Foundation
@testable import CodeNavigatorCore

@Suite("ProjectScanner — 파일 열거와 제외")
struct ProjectScannerTests {

    private func scan(_ fixture: TemporaryProjectFixture) throws -> ProjectScan {
        try ProjectScanner().scan(rootPath: fixture.rootURL)
    }

    @Test("소스 파일을 프로젝트 상대 POSIX 경로로 열거한다")
    func listsFilesAsRelativePosixPaths() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/main/App.kt")
        fixture.write("README.md")

        let scan = try scan(fixture)
        #expect(scan.filePaths.contains("src/main/App.kt"))
        #expect(scan.filePaths.contains("README.md"))
        #expect(scan.filePaths.allSatisfy { !$0.hasPrefix("/") })
    }

    @Test("기본 제외 디렉토리는 열거되지 않는다")
    func excludesDefaultDirectories() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt")
        for excluded in ["node_modules", "build", "dist", "target", "out", ".gradle"] {
            fixture.write("\(excluded)/junk.kt")
            fixture.write("nested/\(excluded)/junk.kt")
        }

        let scan = try scan(fixture)
        #expect(scan.filePaths == ["src/App.kt"])
    }

    @Test("점으로 시작하는 파일과 디렉토리는 열거되지 않는다")
    func excludesHiddenEntries() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt")
        fixture.write(".hiddenrc")
        fixture.write(".git/config")
        fixture.write(".hidden/inside.kt")

        let scan = try scan(fixture)
        #expect(scan.filePaths == ["src/App.kt"])
    }

    @Test("루트 .gitignore가 존중된다")
    func respectsRootGitignore() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write(".gitignore", contents: "*.log\ngenerated/\n")
        fixture.write("src/App.kt")
        fixture.write("app.log")
        fixture.write("generated/Thing.kt")

        let scan = try scan(fixture)
        #expect(scan.filePaths == ["src/App.kt"])
    }

    @Test("하위 디렉토리의 .gitignore도 존중된다")
    func respectsNestedGitignore() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt")
        fixture.write("sub/.gitignore", contents: "ignored.kt\n")
        fixture.write("sub/ignored.kt")
        fixture.write("sub/kept.kt")
        fixture.write("other/ignored.kt")

        let scan = try scan(fixture)
        #expect(scan.filePaths.contains("sub/kept.kt"))
        #expect(scan.filePaths.contains("other/ignored.kt"))
        #expect(scan.filePaths.contains("sub/ignored.kt") == false)
    }

    @Test("무시된 디렉토리 안으로는 내려가지 않는다")
    func doesNotDescendIntoIgnoredDirectories() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write(".gitignore", contents: "vendor/\n")
        fixture.write("vendor/deep/nested/Thing.kt")
        fixture.write("src/App.kt")

        let scan = try scan(fixture)
        #expect(scan.filePaths == ["src/App.kt"])
    }

    @Test("심링크는 따라가지 않는다 — 순환에서 죽지 않는다")
    func doesNotFollowSymbolicLinks() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt")
        fixture.makeSymbolicLink(at: "loop", pointingTo: fixture.rootURL.path)
        fixture.makeSymbolicLink(at: "dangling.kt", pointingTo: "/nonexistent/target.kt")

        let scan = try scan(fixture)
        #expect(scan.filePaths == ["src/App.kt"])
    }

    @Test("존재하지 않는 경로는 명확한 에러다")
    func throwsForMissingRoot() {
        let missing = URL(fileURLWithPath: "/nonexistent/project/root")
        #expect(throws: (any Error).self) {
            try ProjectScanner().scan(rootPath: missing)
        }
    }

    @Test("파일을 루트로 주면 에러다")
    func throwsWhenRootIsAFile() throws {
        let fixture = TemporaryProjectFixture()
        let file = fixture.write("notADirectory.kt")
        #expect(throws: (any Error).self) {
            try ProjectScanner().scan(rootPath: file)
        }
    }

    @Test("빈 프로젝트는 빈 목록이다 — 에러가 아니다")
    func returnsEmptyListForEmptyProject() throws {
        let fixture = TemporaryProjectFixture()
        let scan = try scan(fixture)
        #expect(scan.filePaths.isEmpty)
    }

    @Test("지원 언어 파일만 따로 가려낼 수 있다")
    func separatesIndexableFiles() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt")
        fixture.write("src/Main.java")
        fixture.write("README.md")
        fixture.write("data.json")

        let scan = try scan(fixture)
        #expect(Set(scan.indexableFilePaths) == ["src/App.kt", "src/Main.java"])
        // 미지원 파일도 전문 검색 대상으로 남아야 한다 (REQ-002 AC-3).
        #expect(scan.filePaths.contains("README.md"))
    }

    @Test("열거 결과는 정렬되어 결정적이다")
    func returnsDeterministicallySortedResults() throws {
        let fixture = TemporaryProjectFixture()
        for name in ["zeta.kt", "alpha.kt", "middle/beta.kt"] {
            fixture.write(name)
        }
        let first = try scan(fixture).filePaths
        let second = try scan(fixture).filePaths
        #expect(first == second)
        #expect(first == first.sorted())
    }
}
