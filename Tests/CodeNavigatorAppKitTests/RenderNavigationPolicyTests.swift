import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// 렌더 문서의 링크 클릭 (02b §3 W-14 링크 동작표, INV-6).
///
/// 이 판정은 **약속된 채로 비어 있던 자리**다. 전처리는 `<a href>` 를 일부러 통과시키면서
/// 주석에 *"웹뷰가 내비게이션을 가로챈다"* 고 적었는데, 그 층이 없었다. 주석이 다른 층을
/// 가리키는데 그 층이 없으면 **읽는 사람은 막혀 있다고 믿는다.**
@Suite("RenderNavigationPolicy — 렌더 문서의 링크 클릭 (W-14 · INV-6)")
struct RenderNavigationPolicyTests {

    /// 실제 디렉토리를 만든다 — 경로 판정은 문자열이 아니라 파일 시스템에 묻는다(D-12).
    private func withFixture(_ body: (String) throws -> Void) throws {
        let root = NSTemporaryDirectory() + "cn-nav-\(UUID().uuidString)"
        let manager = FileManager.default
        try manager.createDirectory(atPath: root + "/docs", withIntermediateDirectories: true)
        try manager.createDirectory(atPath: root + "/src", withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: root + "/docs/OTHER.md"))
        try Data().write(to: URL(fileURLWithPath: root + "/docs/guide.md"))
        try Data().write(to: URL(fileURLWithPath: root + "/src/a.ts"))
        try Data().write(to: URL(fileURLWithPath: root + "/page.html"))
        defer { try? manager.removeItem(atPath: root) }
        try body(root)
    }

    private func decide(_ href: String, from document: String = "docs/guide.md", root: String) -> RenderNavigation {
        RenderNavigationPolicy.decide(href: href, documentRelativePath: document, projectRoot: root)
    }

    // MARK: 문서 안

    @Test("앵커는 문서 안 스크롤이다")
    func anchorsScrollWithinTheDocument() throws {
        try withFixture { root in
            #expect(decide("#설치", root: root) == .scrollToFragment("설치"))
        }
    }

    // MARK: 루트 안 로컬

    @Test("루트 안 마크다운은 이 탭에서 렌더로 연다")
    func aMarkdownFileInsideTheRootOpensRendered() throws {
        try withFixture { root in
            #expect(decide("./OTHER.md", root: root) == .openInTab(relativePath: "docs/OTHER.md", asRendered: true))
        }
    }

    @Test("상대 경로는 문서가 있는 폴더 기준이다")
    func relativeLinksResolveAgainstTheDocumentsFolder() throws {
        try withFixture { root in
            // 루트 기준으로 풀면 `docs/guide.md` 옆의 파일을 못 찾는다.
            #expect(decide("OTHER.md", root: root) == .openInTab(relativePath: "docs/OTHER.md", asRendered: true))
        }
    }

    @Test("렌더할 수 없는 파일은 소스로 연다")
    func aNonRenderableFileOpensAsSource() throws {
        try withFixture { root in
            #expect(decide("../src/a.ts", root: root) == .openInTab(relativePath: "src/a.ts", asRendered: false))
        }
    }

    @Test("html 도 렌더로 연다")
    func htmlOpensRendered() throws {
        try withFixture { root in
            #expect(decide("../page.html", root: root) == .openInTab(relativePath: "page.html", asRendered: true))
        }
    }

    // MARK: 루트 밖 — 사유가 구별된다

    @Test("루트 밖 절대 경로는 거절한다")
    func anAbsolutePathOutsideTheRootIsRefused() throws {
        try withFixture { root in
            #expect(decide("/etc/passwd", root: root) == .refuse(.outsideProjectRoot))
        }
    }

    @Test("상위로 빠져나가는 경로는 거절한다")
    func escapingUpwardsIsRefused() throws {
        try withFixture { root in
            #expect(decide("../../../../etc/passwd", root: root) == .refuse(.outsideProjectRoot))
        }
    }

    @Test("루트 밖을 가리키는 심링크는 루트 안에 있어도 밖이다")
    func aSymlinkPointingOutsideIsOutside() throws {
        try withFixture { root in
            let outside = NSTemporaryDirectory() + "cn-nav-outside-\(UUID().uuidString)"
            try FileManager.default.createDirectory(atPath: outside, withIntermediateDirectories: true)
            try Data().write(to: URL(fileURLWithPath: outside + "/secret.md"))
            defer { try? FileManager.default.removeItem(atPath: outside) }
            try FileManager.default.createSymbolicLink(atPath: root + "/docs/link.md", withDestinationPath: outside + "/secret.md")

            #expect(decide("link.md", root: root) == .refuse(.outsideProjectRoot))
        }
    }

    @Test("없는 파일은 루트 밖과 다른 사유다")
    func aMissingFileIsNotTheSameAsOutsideTheRoot() throws {
        // 뭉개면 사용자가 오타를 고칠지 폴더를 옮길지 모른다. 사유 마스킹 금지.
        try withFixture { root in
            #expect(decide("MISSING.md", root: root) == .refuse(.notFound))
        }
    }

    @Test("거절 문구가 루트 밖 파일의 존재를 알려 주지 않는다")
    func theRefusalDoesNotRevealWhatExistsOutsideTheRoot() throws {
        // 사유를 나눈 것의 대가다. 존재를 **먼저** 확인하면 문구가 신탁이 된다 — 문서가
        // `../../etc/shadow` 로 링크해 보고 "찾을 수 없습니다"와 "폴더 밖입니다"를 구별하면,
        // 링크 하나에 한 칸씩 프로젝트 밖 파일 목록을 읽어 낼 수 있다.
        // **거절 사유도 출력이고, 신뢰할 수 없는 입력에 대한 검사의 출력은 채널이다.**
        try withFixture { root in
            let existsOutside = decide("../../../../../../../../etc/passwd", root: root)
            let missingOutside = decide("../../../../../../../../etc/cn-definitely-absent-\(UUID().uuidString)", root: root)

            #expect(existsOutside == .refuse(.outsideProjectRoot))
            #expect(existsOutside == missingOutside, "있는 것과 없는 것이 다른 문구를 낸다 — 존재가 새어 나간다")
        }
    }

    @Test("루트 안에서는 없는 파일을 없다고 말한다")
    func insideTheRootAMissingFileIsNamedAsMissing() throws {
        // 위 규칙이 "전부 뭉개라"가 되면 안 된다. 자기 프로젝트 안에 그 파일이 있는지는
        // 비밀이 아니고, 오타를 고칠 수 있어야 한다.
        try withFixture { root in
            #expect(decide("MISSING.md", root: root) == .refuse(.notFound))
        }
    }

    // MARK: 스킴

    @Test("http·https 는 기본 브라우저로 넘긴다")
    func remoteLinksGoToTheBrowser() throws {
        try withFixture { root in
            #expect(decide("https://example.com/a", root: root) == .openInBrowser(url: "https://example.com/a"))
            #expect(decide("http://example.com/a", root: root) == .openInBrowser(url: "http://example.com/a"))
        }
    }

    @Test("javascript· data· file 스킴은 거절한다")
    func dangerousSchemesAreRefused() throws {
        try withFixture { root in
            #expect(decide("javascript:alert(1)", root: root) == .refuse(.unsupportedScheme))
            #expect(decide("data:text/html,<script>", root: root) == .refuse(.unsupportedScheme))
            #expect(decide("file:///etc/passwd", root: root) == .refuse(.unsupportedScheme))
        }
    }

    @Test("모르는 스킴은 거절한다 — 열거가 아니라 허용목록이다")
    func unknownSchemesAreRefused() throws {
        // 위험한 스킴을 세는 방식은 빠뜨린 것이 곧 구멍이다. http(s) 만 통과시킨다.
        try withFixture { root in
            #expect(decide("cnres://x", root: root) == .refuse(.unsupportedScheme))
            #expect(decide("vbscript:msgbox(1)", root: root) == .refuse(.unsupportedScheme))
        }
    }

    @Test("대문자 스킴도 같은 판정이다")
    func schemeMatchingIsCaseInsensitive() throws {
        try withFixture { root in
            #expect(decide("JavaScript:alert(1)", root: root) == .refuse(.unsupportedScheme))
            #expect(decide("HTTPS://example.com", root: root) == .openInBrowser(url: "HTTPS://example.com"))
        }
    }

    @Test("스킴 안의 공백·제어문자가 판정을 비켜가지 못한다")
    func whitespaceInsideASchemeDoesNotEvadeTheCheck() throws {
        // 브라우저는 URL 에서 탭·개행을 **버리고** 파싱한다. `java\nscript:` 가 살아나는
        // 고전적 우회다. 우리가 같은 정규화를 하지 않으면 우리 판정과 브라우저의 해석이
        // 갈라지고, 갈라진 틈이 곧 구멍이다.
        try withFixture { root in
            #expect(decide("java\nscript:alert(1)", root: root) == .refuse(.unsupportedScheme))
            #expect(decide("java\tscript:alert(1)", root: root) == .refuse(.unsupportedScheme))
            #expect(decide("  javascript:alert(1)", root: root) == .refuse(.unsupportedScheme))
        }
    }

    @Test("프로토콜 상대 참조는 원격이므로 로컬 경로로 읽지 않는다")
    func protocolRelativeReferencesAreNotLocalPaths() throws {
        // `//evil.com/x` 는 경로처럼 생겼지만 원격이다. 로컬로 읽으면 루트 검사에
        // 걸려 "없는 파일"이 되고, 사용자는 왜 안 열리는지 엉뚱한 설명을 듣는다.
        try withFixture { root in
            #expect(decide("//evil.com/x.md", root: root) == .refuse(.unsupportedScheme))
        }
    }

    // MARK: 웹뷰가 넘겨주는 URL

    @Test("웹뷰가 푼 file URL 은 로컬 경로로 판정한다")
    func aResolvedFileURLIsJudgedAsALocalPath() throws {
        try withFixture { root in
            let url = URL(fileURLWithPath: root + "/docs/OTHER.md")
            let decision = RenderNavigationPolicy.decide(
                navigationURL: url, documentRelativePath: "docs/guide.md", projectRoot: root
            )

            #expect(decision == .openInTab(relativePath: "docs/OTHER.md", asRendered: true))
        }
    }

    @Test("루트 밖 file URL 은 거절한다")
    func aFileURLOutsideTheRootIsRefused() throws {
        try withFixture { root in
            let decision = RenderNavigationPolicy.decide(
                navigationURL: URL(fileURLWithPath: "/etc/passwd"),
                documentRelativePath: "docs/guide.md",
                projectRoot: root
            )

            // 사유는 `unsupportedScheme` 가 아니라 `outsideProjectRoot` 다 — 둘 다 거절이고,
            // 살아남는 쪽이 더 구체적인 진실이다.
            #expect(decision == .refuse(.outsideProjectRoot))
        }
    }

    @Test("원격 URL 은 그대로 브라우저로 간다")
    func aRemoteURLStillGoesToTheBrowser() throws {
        try withFixture { root in
            let url = try #require(URL(string: "https://example.com/a"))
            let decision = RenderNavigationPolicy.decide(
                navigationURL: url, documentRelativePath: "docs/guide.md", projectRoot: root
            )

            #expect(decision == .openInBrowser(url: "https://example.com/a"))
        }
    }

    @Test("URL 경로로 와도 위험 스킴은 거절한다")
    func dangerousSchemesAreStillRefusedAsURLs() throws {
        try withFixture { root in
            let url = try #require(URL(string: "javascript:alert(1)"))
            let decision = RenderNavigationPolicy.decide(
                navigationURL: url, documentRelativePath: "docs/guide.md", projectRoot: root
            )

            #expect(decision == .refuse(.unsupportedScheme))
        }
    }

    // MARK: 상태바 문구

    @Test("사유마다 다른 문구를 낸다")
    func eachRefusalSaysSomethingDifferent() {
        let messages = Set([
            RenderNavigationRefusal.outsideProjectRoot.statusMessage,
            RenderNavigationRefusal.notFound.statusMessage,
            RenderNavigationRefusal.unsupportedScheme.statusMessage,
        ])

        #expect(messages.count == 3, "사유가 셋인데 문구가 \(messages.count)종이다")
        #expect(RenderNavigationRefusal.outsideProjectRoot.statusMessage.contains("프로젝트 폴더 밖"))
    }
}
