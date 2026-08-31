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
            projectRoot: root ?? self.root
        )
    }

    private func blockedKind(_ decision: SandboxDecision) -> BlockedResourceKind? {
        guard case .block(let kind, _) = decision else { return nil }
        return kind
    }

    private func isAllowed(_ decision: SandboxDecision) -> Bool {
        decision.isBlocked == false
    }

    /// A real project on disk.
    ///
    /// The allow cases need real files now: the boundary requires the path to resolve, and
    /// a string fixture cannot resolve. That is the same property that makes the rule
    /// enforceable — `realpath` fails on what does not exist.
    private struct Fixture {
        let base: URL
        let root: URL

        init() throws {
            base = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("sandbox-\(UUID().uuidString)")
            root = base.appendingPathComponent("project")
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("images"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("styles"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("fonts"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
            for path in ["images/logo.png", "images/c:logo.png", "styles/site.css", "fonts/body.woff2"] {
                try Data("x".utf8).write(to: root.appendingPathComponent(path))
            }
        }

        func cleanUp() { try? FileManager.default.removeItem(at: base) }

        func decide(_ element: RenderedElement) -> SandboxDecision {
            RenderSandboxPolicy.decide(element, projectRoot: root.path)
        }
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
    func localImagesInsideTheProjectAreAllowed() throws {
        // INV-6은 로컬 접근을 루트로 **제한**하는 것이지 금지가 아니다. README 이미지
        // 대부분이 여기 해당하고, 전부 막으면 렌더 보기가 쓸모를 잃는다.
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        #expect(isAllowed(fixture.decide(.image(source: "images/logo.png"))))
        #expect(isAllowed(fixture.decide(.image(source: fixture.root.appendingPathComponent("images/logo.png").path))))
        #expect(isAllowed(fixture.decide(.image(source: "file://" + fixture.root.appendingPathComponent("images/logo.png").path))))
    }

    @Test("루트 안의 스타일시트·폰트도 허용한다")
    func localStylesheetsAndFontsInsideTheProjectAreAllowed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        #expect(isAllowed(fixture.decide(.stylesheet(source: "styles/site.css"))))
        #expect(isAllowed(fixture.decide(.font(source: "fonts/body.woff2"))))
    }

    @Test("허용된 결과가 해석된 절대경로를 싣고 온다")
    func anAllowedDecisionCarriesTheResolvedPath() throws {
        // 로더는 참조가 아니라 **이 경로**를 연다. 검사한 경로와 여는 경로가 다르면
        // 그 사이에 파일이 생겨 판정이 무의미해진다(TOCTOU).
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        guard case .allowFile(let resolved) = fixture.decide(.image(source: "images/logo.png")) else {
            Issue.record("허용되지 않았다")
            return
        }
        #expect(resolved.hasSuffix("/images/logo.png"))
        #expect(FileManager.default.fileExists(atPath: resolved))
    }

    @Test("루트 안의 없는 파일은 로드되지 않되 차단으로 세지 않는다")
    func aMissingFileInsideTheRootIsNeitherLoadedNorCountedAsBlocked() throws {
        // 예전엔 `.outsideProjectRoot` 로 단언했다. **지키려던 성질은 "해석 못 한 것을
        // 로드하지 않는다"** 였는데, 단언은 *분류*를 붙잡고 있었다. 그 분류가 라이브에서
        // 사용자에게 보였고 — 프로젝트 **안**의 파일이 *"폴더 밖에 있다"* 로 안내됐다.
        // 게다가 안 막은 것이 차단 칩에 실려 **보안 신호가 부풀려졌다**(차단 2건인데 3).
        //
        // 그래서 성질을 직접 잰다: 로드되지 않고(fail closed), 차단으로도 세지 않는다.
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let decision = fixture.decide(.image(source: "images/absent.png"))

        #expect(!decision.isBlocked, "우리가 막은 게 아니다")
        if case .unavailable = decision {} else {
            Issue.record("못 읽은 것으로 분류돼야 한다: \(decision)")
        }
        // fail closed 는 그대로다 — 어떤 경우에도 파일로 허용되지 않는다.
        if case .allowFile = decision {
            Issue.record("해석 못 한 경로가 로드 허용됐다")
        }
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
            projectRoot: projectRoot.path
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
            projectRoot: projectRoot.path
        )
        #expect(isAllowed(decision), "루트 안의 실제 파일이 막혔다")
    }

    @Test("탭이 다르면 루트도 다르다 — 다른 탭의 파일은 밖이다")
    func anotherTabsFileIsOutsideThisTabsRoot() {
        // INV-5. A 탭 문서가 B 탭 파일을 읽으면 격리 위반이다.
        let decision = RenderSandboxPolicy.decide(
            .image(source: "/Users/dev/other-project/logo.png"),
            projectRoot: "/Users/dev/repo"
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
                decide(.image(source: "data:\(mediaType);base64,iVBORw0K")) == .allowInlineData,
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

    @Test("모든 분류가 화면 문구를 갖는다")
    func everyKindHasItsScreenWording() {
        // 분류가 늘면 **여기서 걸리라고** 둔 수다. 실제로 걸렸다 — `.tooLarge` 를 더하자
        // 이 줄이 빨간불이 됐고, 그래서 문구를 빠뜨리지 않고 같이 넣었다. 숫자를 지우면
        // 다음 분류는 문구 없이 조용히 들어온다.
        //
        // 6 → 7: 리더 판정 2026-08-31. 루트 안의 3MB 파일이 `outsideProjectRoot` 로
        // 기록되던 거짓말을 없애기 위해 `.tooLarge` 를 추가했다.
        #expect(BlockedResourceKind.allCases.count == 7)
        for kind in BlockedResourceKind.allCases {
            #expect(!kind.label.isEmpty, "\(kind.rawValue)")
        }
    }

    // MARK: `RenderResourcePolicyTests` 에서 옮겨 온 케이스 (중복 정리 시 커버리지 보존)

    @Test("스킴 없는 프로토콜 상대 참조도 원격이다")
    func protocolRelativeReferencesAreRemote() {
        // `//evil.com/x.png` 는 페이지의 스킴을 물려받는 **원격** 참조인데 생김새는
        // 경로다. 옮겨 오기 전 내 정책은 이걸 상대 경로로 읽어 루트 아래로 해석하고
        // **허용**했다 — 시니어 테스트를 읽지 않고 지웠으면 그대로 남았을 구멍이다.
        #expect(blockedKind(decide(.image(source: "//evil.com/x.png"))) == .remoteImage)

        guard case .block(_, let detail) = decide(.image(source: "//evil.com/x.png")) else {
            Issue.record("허용됐다")
            return
        }
        #expect(detail == "evil.com")
    }

    @Test("루트 자신은 파일이 아니므로 허용하지 않는다")
    func theRootItselfIsNotAResource() {
        // `.` 은 루트 디렉토리로 해석된다. 허용하면 렌더러에 **디렉토리를** 인라인하라고
        // 넘기게 된다. 이것도 옮겨 오기 전에는 허용됐다.
        #expect(blockedKind(decide(.image(source: "."))) == .outsideProjectRoot)
        #expect(blockedKind(decide(.image(source: "/Users/dev/repo"))) == .outsideProjectRoot)
    }

    @Test("경로 안의 콜론을 스킴으로 오해하지 않는다")
    func aColonInsideAPathIsNotAScheme() throws {
        // `images/c:logo.png` 는 콜론이 있지만 앞부분에 구분자가 있어 스킴이 아니다.
        // 스킴으로 읽으면 정당한 파일을 거부한다.
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(isAllowed(fixture.decide(.image(source: "images/c:logo.png"))))
    }

    @Test("스킴처럼 생긴 단독 참조는 통과시키지 않는다")
    func aSchemeShapedReferenceIsNotTreatedAsAPath() {
        // `c:/x.png` 는 Foundation 도 스킴으로 읽는다(시니어 실측). macOS 경로는 그렇게
        // 시작하지 않으므로 거부가 안전한 독해다.
        #expect(blockedKind(decide(.image(source: "c:/x.png"))) == .remoteImage)
    }

    @Test("루트 안으로 되돌아오는 `..` 는 허용된다")
    func traversalThatStaysInsideIsAllowed() throws {
        // 금지된 것은 탈출이지 `..` 라는 글자가 아니다.
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(isAllowed(fixture.decide(.image(source: "docs/../images/logo.png"))))
    }

    @Test("루트 안을 가리키는 심링크는 허용된다")
    func aSymlinkPointingInsideTheRootIsAllowed() throws {
        // 탈출만 막고 정당한 링크는 통과해야 한다. 한 방향만 테스트하면 "전부 차단"
        // 정책도 통과한다.
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sandbox-inside-\(UUID().uuidString)")
        let projectRoot = base.appendingPathComponent("project")
        let assets = projectRoot.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let real = assets.appendingPathComponent("logo.png")
        try Data("x".utf8).write(to: real)
        let link = projectRoot.appendingPathComponent("logo.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let decision = RenderSandboxPolicy.decide(
            .image(source: link.path), projectRoot: projectRoot.path
        )
        #expect(isAllowed(decision), "루트 안을 가리키는 심링크가 차단됐다")
    }

    // MARK: 회귀 — leaf 가 없어도 심링크 탈출은 막힌다 (리더 재현, 2026-08-30)

    @Test("존재하지 않는 leaf 를 통한 심링크 탈출이 막힌다")
    func aSymlinkEscapeIsBlockedEvenWhenTheLeafDoesNotExist() throws {
        // 이 결함은 **문자열 픽스처로는 안 잡힌다** — 그래서 지금까지 안 잡혔다.
        // `URL.resolvingSymlinksInPath()` 는 leaf 가 없으면 링크를 풀지 않아서,
        // 미해석 경로가 접두 비교를 통과했다. 실측 결과:
        //   link/exists.md → 차단 (leaf 존재 → 해석됨)
        //   link/later.md  → **허용** ← 탈출
        //   link/a/b.md    → **허용** ← 탈출
        // 위협 모델이 "신뢰하지 않는 저장소"이고 문서 내용은 공격자가 정한다.
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("escape-\(UUID().uuidString)")
        let root = base.appendingPathComponent("root")
        let outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link"), withDestinationURL: outside)
        try Data("x".utf8).write(to: outside.appendingPathComponent("exists.md"))

        for reference in ["link/exists.md", "link/later.md", "link/a/b.md"] {
            let decision = RenderSandboxPolicy.decide(
                .image(source: reference), projectRoot: root.path)
            #expect(decision.isBlocked, "\(reference) 가 루트를 빠져나갔다")
        }
    }

    @Test("중간 경로가 심링크여도 루트 안이면 허용된다")
    func anIntermediateSymlinkStayingInsideIsAllowed() throws {
        // 반대 방향. 중간 링크를 전부 막아 버리는 구현이면 위 테스트는 통과하면서
        // 정당한 프로젝트 구조를 깨뜨린다.
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("inside-link-\(UUID().uuidString)")
        let root = base.appendingPathComponent("root")
        let real = root.appendingPathComponent("real-assets")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        try Data("x".utf8).write(to: real.appendingPathComponent("logo.png"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("assets"), withDestinationURL: real)

        let decision = RenderSandboxPolicy.decide(
            .image(source: "assets/logo.png"), projectRoot: root.path)
        #expect(!decision.isBlocked, "루트 안을 가리키는 중간 심링크가 차단됐다")
    }
}
