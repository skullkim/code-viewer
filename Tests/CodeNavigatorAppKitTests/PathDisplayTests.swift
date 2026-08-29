import Testing
@testable import CodeNavigatorAppKit

/// The status bar shows a project-relative path (design §3 W-7) and the file tree
/// highlights the file currently being edited (REQ-003 AC-3). Both need the engine's two
/// path shapes — absolute from the edit session, project-relative from the tree — to meet.
@Suite("PathDisplay — 경로 상대화와 축약 (REQ-003 AC-3, 02 §3 W-7)")
struct PathDisplayTests {

    // MARK: Relativising

    @Test("루트 아래 경로는 프로젝트 상대 경로가 된다")
    func pathsUnderTheRootBecomeRelative() {
        let relative = PathDisplay.relativePath(
            ofAbsolutePath: "/Users/dev/repo/Sources/Index/SymbolIndex.swift",
            projectRoot: "/Users/dev/repo"
        )
        #expect(relative == "Sources/Index/SymbolIndex.swift")
    }

    @Test("루트의 뒤따르는 슬래시가 결과를 바꾸지 않는다")
    func trailingSlashOnTheRootIsIgnored() {
        #expect(PathDisplay.relativePath(ofAbsolutePath: "/a/b/c.swift", projectRoot: "/a/b/") == "c.swift")
        #expect(PathDisplay.relativePath(ofAbsolutePath: "/a/b/c.swift", projectRoot: "/a/b") == "c.swift")
    }

    @Test("/private 접두사 차이로 매칭이 조용히 실패하지 않는다")
    func theOldPrivatePrefixDoesNotBreakMatching() {
        // macOS reports /tmp and /var both with and without the /private prefix depending
        // on which API produced the path. Mismatching them would silently drop the tree
        // highlight rather than fail loudly, so it is normalised on both sides.
        #expect(PathDisplay.relativePath(ofAbsolutePath: "/private/tmp/repo/a.swift", projectRoot: "/tmp/repo") == "a.swift")
        #expect(PathDisplay.relativePath(ofAbsolutePath: "/tmp/repo/a.swift", projectRoot: "/private/tmp/repo") == "a.swift")
    }

    @Test("상대 경로 조각이 정규화된다")
    func relativeSegmentsAreNormalised() {
        #expect(PathDisplay.relativePath(ofAbsolutePath: "/a/b/./sub/../c.swift", projectRoot: "/a/b") == "c.swift")
    }

    @Test("루트 밖 경로는 nil이다 — 억지로 맞추지 않는다")
    func pathsOutsideTheRootAreRejected() {
        #expect(PathDisplay.relativePath(ofAbsolutePath: "/other/place/a.swift", projectRoot: "/a/b") == nil)
        // A sibling directory whose name merely starts with the root's name is not inside it.
        #expect(PathDisplay.relativePath(ofAbsolutePath: "/a/broader/a.swift", projectRoot: "/a/b") == nil)
    }

    @Test("루트 자신은 빈 상대 경로다")
    func theRootItselfIsEmpty() {
        #expect(PathDisplay.relativePath(ofAbsolutePath: "/a/b", projectRoot: "/a/b") == "")
    }

    // MARK: Truncating for a narrow status bar

    @Test("들어가는 경로는 축약하지 않는다")
    func shortPathsAreLeftAlone() {
        #expect(PathDisplay.truncatedFromStart("Sources/App.swift", maximumCharacters: 40) == "Sources/App.swift")
    }

    @Test("좁으면 앞쪽 디렉토리부터 줄인다")
    func longPathsLoseTheirLeadingDirectories() {
        let truncated = PathDisplay.truncatedFromStart(
            "Sources/CodeNavigatorAppKit/Logic/ShellLayout.swift",
            maximumCharacters: 30
        )
        #expect(truncated.hasPrefix("…/"))
        #expect(truncated.hasSuffix("ShellLayout.swift"))
        #expect(truncated.count <= 30)
    }

    @Test("파일 이름은 어떤 폭에서도 온전히 남는다")
    func theFileNameSurvivesEveryWidth() {
        // Losing the directory tells you less; losing the file name tells you nothing.
        let truncated = PathDisplay.truncatedFromStart(
            "a/b/c/AVeryLongFileNameIndeed.swift",
            maximumCharacters: 10
        )
        #expect(truncated.hasSuffix("AVeryLongFileNameIndeed.swift"))
    }

    @Test("파일 이름만 있으면 축약하지 않는다")
    func aBareFileNameIsNeverTruncated() {
        #expect(PathDisplay.truncatedFromStart("App.swift", maximumCharacters: 4) == "App.swift")
    }

    @Test("파일 이름을 뽑는다")
    func fileNameIsExtracted() {
        #expect(PathDisplay.fileName("Sources/Index/SymbolIndex.swift") == "SymbolIndex.swift")
        #expect(PathDisplay.fileName("App.swift") == "App.swift")
        #expect(PathDisplay.fileName("") == "")
    }
}
