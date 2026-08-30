import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// INV-6: the render view is a sandbox, and blocking is the default.
///
/// These are security decisions, so the tests are written around the failure that costs
/// more. Blocking something harmless shows up in the chip, the popover and a placeholder —
/// the user sees it and can open the file in a browser. Loading something that should have
/// been blocked is silent, and the document chose it, not the user. Every ambiguous case
/// below therefore expects a block.
@Suite("RenderSandboxPolicy — 무엇을 싣고 무엇을 막는가 (INV-6)")
struct RenderSandboxPolicyTests {

    private let root = "/Users/dev/repo"

    private func decide(_ element: RenderedElement, root: String? = nil) -> SandboxDecision {
        RenderSandboxPolicy.decide(
            element,
            projectRoot: root ?? self.root,
            isCaseSensitiveVolume: true
        )
    }

    private func blockedKind(_ decision: SandboxDecision) -> BlockedResourceKind? {
        guard case .block(let kind, _) = decision else { return nil }
        return kind
    }

    // MARK: 원격은 전부 막는다

    @Test("원격 이미지·스타일시트·폰트는 종류별로 막힌다")
    func remoteResourcesAreBlockedUnderTheirOwnHeading() {
        #expect(blockedKind(decide(.image(source: "https://raw.githubusercontent.com/a/b.png"))) == .remoteImage)
        #expect(blockedKind(decide(.stylesheet(source: "https://cdn.jsdelivr.net/x.css"))) == .remoteStylesheet)
        #expect(blockedKind(decide(.font(source: "https://fonts.example.com/f.woff2"))) == .remoteFont)
    }

    @Test("차단 항목에 호스트가 남는다")
    func theHostIsRecordedSoTheUserKnowsWhatWasMissed() {
        guard case .block(_, let detail) = decide(.image(source: "https://raw.githubusercontent.com/a/b.png")) else {
            Issue.record("원격 이미지가 허용됐다")
            return
        }
        #expect(detail == "raw.githubusercontent.com")
    }

    @Test("http 말고도 네트워크에 닿는 스킴은 전부 막는다")
    func everyNetworkSchemeIsBlocked() {
        for source in ["http://a/b.png", "ftp://a/b.png", "ws://a/b.png", "smb://a/b.png"] {
            #expect(blockedKind(decide(.image(source: source))) == .remoteImage, "\(source)")
        }
    }

    // MARK: 스크립트와 프레임은 위치와 무관하다

    @Test("스크립트는 프로젝트 안에 있어도 막힌다")
    func scriptsAreBlockedEvenInsideTheProject() {
        // INV-6은 스크립트 **실행**을 막는다. 루트 안의 스크립트도 똑같이 실행된다.
        #expect(blockedKind(decide(.script(source: "/Users/dev/repo/app.js"))) == .script)
        #expect(blockedKind(decide(.script(source: "https://cdn.example.com/a.js"))) == .script)
    }

    @Test("인라인 스크립트도 막히고 그렇게 표기된다")
    func inlineScriptsAreBlockedAndLabelled() {
        guard case .block(let kind, let detail) = decide(.script(source: nil)) else {
            Issue.record("인라인 스크립트가 허용됐다")
            return
        }
        #expect(kind == .script)
        #expect(detail == "(인라인)")
    }

    @Test("프레임은 로컬이어도 막힌다")
    func framesAreBlockedWhereverTheyPoint() {
        // 프레임은 문서 안의 문서다. 허용하면 여기 규칙 전부를 그 내용물에 넘기게 된다.
        #expect(blockedKind(decide(.frame(source: "/Users/dev/repo/inner.html"))) == .frame)
        #expect(blockedKind(decide(.frame(source: "https://example.com"))) == .frame)
    }

    // MARK: 루트 안의 로컬은 허용한다

    @Test("프로젝트 루트 안의 로컬 이미지는 표시한다")
    func localImagesInsideTheProjectAreAllowed() {
        // INV-6은 로컬 접근을 루트로 **제한**하는 것이지 금지가 아니다. README 이미지
        // 대부분이 여기 해당하고, 전부 막으면 렌더 보기가 쓸모를 잃는다.
        #expect(decide(.image(source: "/Users/dev/repo/docs/diagram.png")) == .allow)
        #expect(decide(.image(source: "docs/diagram.png")) == .allow)
        #expect(decide(.image(source: "file:///Users/dev/repo/docs/diagram.png")) == .allow)
    }

    @Test("루트 안의 스타일시트·폰트도 허용한다")
    func localStylesheetsAndFontsInsideTheProjectAreAllowed() {
        #expect(decide(.stylesheet(source: "styles/site.css")) == .allow)
        #expect(decide(.font(source: "fonts/body.woff2")) == .allow)
    }

    // MARK: 루트 밖은 막는다

    @Test("루트 밖 절대 경로는 막힌다")
    func absolutePathsOutsideTheProjectAreBlocked() {
        #expect(blockedKind(decide(.image(source: "/etc/passwd"))) == .outsideProjectRoot)
    }

    @Test("..로 루트를 빠져나가는 경로는 막힌다")
    func parentTraversalIsBlocked() {
        #expect(blockedKind(decide(.image(source: "../../.ssh/config"))) == .outsideProjectRoot)
        #expect(blockedKind(decide(.image(source: "docs/../../../etc/hosts"))) == .outsideProjectRoot)
    }

    @Test("이름이 루트로 시작할 뿐인 형제 폴더는 루트 안이 아니다")
    func aSiblingSharingThePrefixIsNotInside() {
        // `/Users/dev/repo-secrets` 는 `/Users/dev/repo` 로 시작하지만 다른 폴더다.
        // 구분자를 안 보면 통과한다.
        #expect(blockedKind(decide(.image(source: "/Users/dev/repo-secrets/key.png"))) == .outsideProjectRoot)
    }

    @Test("루트 밖을 가리키는 심링크는 루트 안에 있어도 밖이다")
    func aSymlinkEscapingTheRootIsOutside() throws {
        // 실제 심링크로 확인한다. 철자만 보면 루트 안이라 통과하고, 그게 문서가
        // `~/.ssh/config` 를 읽는 경로가 된다.
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sandbox-\(UUID().uuidString)")
        let projectRoot = base.appendingPathComponent("project")
        let outside = base.appendingPathComponent("outside")

        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let secret = outside.appendingPathComponent("secret.png")
        try Data("x".utf8).write(to: secret)
        let escape = projectRoot.appendingPathComponent("looks-local.png")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: secret)

        let decision = RenderSandboxPolicy.decide(
            .image(source: escape.path),
            projectRoot: projectRoot.path,
            isCaseSensitiveVolume: true
        )
        #expect(blockedKind(decision) == .outsideProjectRoot, "루트를 빠져나가는 심링크가 허용됐다")
    }

    @Test("루트 안의 진짜 파일은 같은 조건에서 허용된다")
    func arealFileInsideTheRootIsAllowedUnderTheSameConditions() throws {
        // 반대 방향. 무엇이든 막는 정책이라면 위 테스트는 통과하면서 아무것도 증명하지
        // 못한다 — 렌더 보기가 이미지를 하나도 못 그리는 상태와 구별되지 않는다.
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sandbox-\(UUID().uuidString)")
        let projectRoot = base.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let image = projectRoot.appendingPathComponent("real.png")
        try Data("x".utf8).write(to: image)

        let decision = RenderSandboxPolicy.decide(
            .image(source: image.path),
            projectRoot: projectRoot.path,
            isCaseSensitiveVolume: true
        )
        #expect(decision == .allow, "루트 안의 실제 파일이 막혔다")
    }

    @Test("탭이 다르면 루트도 다르다 — 다른 탭의 파일은 밖이다")
    func anotherTabsFileIsOutsideThisTabsRoot() {
        // INV-5. A 탭 문서가 B 탭 파일을 읽으면 격리 위반이다.
        let decision = RenderSandboxPolicy.decide(
            .image(source: "/Users/dev/other-project/logo.png"),
            projectRoot: "/Users/dev/repo",
            isCaseSensitiveVolume: true
        )
        #expect(blockedKind(decision) == .outsideProjectRoot)
    }

    // MARK: 애매하면 막는다

    @Test("data: 래스터 이미지는 허용한다 (리더 판정)")
    func rasterDataImagesAreAllowed() {
        // INV-6이 막는 것은 네트워크와 실행 둘이고, 래스터 data: 는 어느 쪽에도 안 닿는다.
        // 마크다운에 다이어그램을 박아 넣는 실제 패턴이라 막으면 정당한 문서가 깨진다.
        for mediaType in ["image/png", "image/jpeg", "image/gif", "image/webp"] {
            #expect(
                decide(.image(source: "data:\(mediaType);base64,iVBORw0K")) == .allow,
                "\(mediaType)"
            )
        }
    }

    @Test("data:image/svg+xml 은 막는다 — 마크업이고 스크립트를 품을 수 있다")
    func svgDataImagesAreBlocked() {
        // `<img>` 로 불리면 스크립트가 안 돈다는 것이 통설이지만 **그 안전이 렌더러
        // 구현에 달려 있다.** 차단이 기본값인 이상 통제 못 하는 전제 위에 허용을 세우지
        // 않는다.
        #expect(blockedKind(decide(.image(source: "data:image/svg+xml;base64,PHN2Zz4="))) == .remoteImage)
        #expect(blockedKind(decide(.image(source: "data:image/svg+xml,<svg/>"))) == .remoteImage)
    }

    @Test("그 밖의 data: 는 전부 막는다")
    func otherDataUrisAreBlocked() {
        for source in [
            "data:text/html,<h1>x</h1>",
            "data:application/javascript,alert(1)",
            "data:image/bmp;base64,Qk0=",   // 목록에 없는 이미지 포맷
            "data:,plain",                   // 미디어 타입 없음 = text/plain
        ] {
            #expect(blockedKind(decide(.image(source: source))) == .remoteImage, "\(source)")
        }
    }

    @Test("data: 는 이미지 자리에서만 허용된다 — 스타일시트·폰트는 아니다")
    func dataUrisAreOnlyAllowedForImages() {
        // 판정은 래스터 **이미지**에 대한 것이었다. 같은 스킴을 다른 자리로 넓히면
        // 판정 범위를 내가 늘리는 셈이다.
        #expect(blockedKind(decide(.stylesheet(source: "data:image/png;base64,iVBORw0K"))) == .remoteStylesheet)
        #expect(blockedKind(decide(.font(source: "data:image/png;base64,iVBORw0K"))) == .remoteFont)
    }

    @Test("javascript: 는 네트워크에 안 닿아도 막는다")
    func javascriptUrisAreBlocked() {
        #expect(blockedKind(decide(.image(source: "javascript:alert(1)"))) == .remoteImage)
    }

    @Test("소스가 비었거나 없으면 막는다")
    func anAbsentSourceIsBlocked() {
        #expect(blockedKind(decide(.image(source: nil))) == .remoteImage)
        #expect(blockedKind(decide(.image(source: "   "))) == .remoteImage)
    }

    @Test("루트가 비어 있으면 아무것도 로컬로 인정하지 않는다")
    func anEmptyRootAllowsNothing() {
        // 프로젝트가 안 열린 상태에서 렌더가 돌면 "루트 안"이 정의되지 않는다.
        #expect(blockedKind(decide(.image(source: "docs/a.png"), root: "")) == .outsideProjectRoot)
    }

    // MARK: 플레이스홀더 대상

    @Test("자리를 차지했던 것만 본문 플레이스홀더를 갖는다")
    func onlyVisibleElementsGetAPlaceholder() {
        // 스크립트는 원래 화면에 없었다. 자리를 그리면 문서에 없던 구멍을 만드는 것이다.
        #expect(BlockedResourceKind.remoteImage.showsInlinePlaceholder)
        #expect(BlockedResourceKind.outsideProjectRoot.showsInlinePlaceholder)
        #expect(BlockedResourceKind.frame.showsInlinePlaceholder)

        #expect(!BlockedResourceKind.script.showsInlinePlaceholder)
        #expect(!BlockedResourceKind.remoteStylesheet.showsInlinePlaceholder)
        #expect(!BlockedResourceKind.remoteFont.showsInlinePlaceholder)
    }

    @Test("여섯 분류가 전부 화면 문구를 갖는다")
    func everyKindHasItsScreenWording() {
        // §3 W-15 의 여섯 종류. 계약이 늘면 여기서 걸린다.
        #expect(BlockedResourceKind.allCases.count == 6)
        for kind in BlockedResourceKind.allCases {
            #expect(!kind.label.isEmpty, "\(kind.rawValue)")
        }
    }
}
