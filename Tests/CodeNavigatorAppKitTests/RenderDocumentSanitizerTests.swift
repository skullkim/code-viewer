import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// INV-6 layer one: the document is rewritten before the web view sees it.
///
/// The property every test here defends is one sentence: **after this pass, no URI the
/// author wrote survives.** That is what makes the CSP backstop simple — `img-src data:` is
/// only safe if every remaining `data:` is ours. So "blocked" is never enough on its own;
/// each case also checks the original reference is *gone from the output*.
@Suite("RenderDocumentSanitizer — 작성자 URI 를 남기지 않는다 (INV-6)")
struct RenderDocumentSanitizerTests {

    private let root = "/Users/dev/repo"

    private func sanitize(
        _ html: String,
        loadFile: @escaping RenderDocumentSanitizer.FileLoader = { _ in Data("png".utf8) }
    ) -> SanitizedDocument {
        RenderDocumentSanitizer.sanitize(
            html: html,
            projectRoot: root,
            loadFile: loadFile
        )
    }

    // MARK: 원격 참조

    @Test("원격 이미지는 차단되고 그 URI 가 문서에서 사라진다")
    func aRemoteImageIsBlockedAndItsURIRemoved() {
        let result = sanitize(#"<img src="https://evil.com/x.png">"#)

        #expect(result.blocked.contains { $0.kind == .remoteImage })
        #expect(
            fetchableValues(in: result.html, containing: "evil.com").isEmpty,
            "차단했다면서 URI 를 페치 가능한 자리에 남겼다"
        )
    }

    @Test("원격 스타일시트도 마찬가지다")
    func aRemoteStylesheetIsRemoved() {
        let result = sanitize(#"<link rel="stylesheet" href="https://cdn.example.com/a.css">"#)

        #expect(result.blocked.contains { $0.kind == .remoteStylesheet })
        #expect(!result.html.contains("cdn.example.com"))
    }

    @Test("프레임은 로컬이어도 차단되고 참조가 사라진다")
    func framesAreRemovedWhereverTheyPoint() {
        let result = sanitize(#"<iframe src="inner.html"></iframe>"#)

        #expect(result.blocked.contains { $0.kind == .frame })
        #expect(!result.html.contains("inner.html"))
    }

    // MARK: 스크립트

    @Test("스크립트는 내용째로 제거된다")
    func scriptsAreRemovedWholesale() {
        // `src` 만 비우면 인라인 내용이 채울 수 있는 껍데기가 남는다.
        let result = sanitize("<p>a</p><script>alert(1)</script><p>b</p>")

        #expect(result.blocked.contains { $0.kind == .script })
        #expect(!result.html.contains("alert"))
        #expect(!result.html.contains("<script"))
        #expect(result.html.contains("<p>a</p>"))
        #expect(result.html.contains("<p>b</p>"))
    }

    @Test("닫히지 않은 스크립트는 나머지를 통째로 버린다")
    func anUnclosedScriptSwallowsTheRest() {
        // 파편을 남기면 그 의미가 브라우저의 복구 규칙에 달린다 — 우리가 통제 못 하는 것.
        let result = sanitize("<p>ok</p><script>alert(1)")

        #expect(!result.html.contains("alert"))
        #expect(result.blocked.contains { $0.kind == .script })
    }

    // MARK: 로컬 허용 — 우리가 만든 data: 로

    @Test("루트 안 로컬 이미지는 우리가 만든 data: 로 바뀐다")
    func anAllowedLocalImageBecomesOurDataURI() throws {
        let fixture = try TemporaryProject()
        defer { fixture.cleanUp() }

        let result = RenderDocumentSanitizer.sanitize(
            html: #"<img src="images/logo.png">"#,
            projectRoot: fixture.root.path,
            loadFile: { _ in Data([0x89, 0x50]) }
        )

        #expect(result.blocked.isEmpty)
        #expect(result.html.contains("data:image/png;base64,"), "인라인되지 않았다: \(result.html)")
        #expect(!result.html.contains("images/logo.png"), "원본 경로가 남았다")
    }

    @Test("파일을 못 읽으면 차단으로 떨어진다")
    func anUnreadableFileFallsBackToBlocked() throws {
        // 허용 판정을 받았어도 바이트가 없으면 그릴 것이 없다. 빈 src 를 남기지 않는다.
        let fixture = try TemporaryProject()
        defer { fixture.cleanUp() }

        let result = RenderDocumentSanitizer.sanitize(
            html: #"<img src="images/logo.png">"#,
            projectRoot: fixture.root.path,
            loadFile: { _ in nil }
        )

        #expect(!result.blocked.isEmpty)
        #expect(!result.html.contains("images/logo.png"))
    }

    // MARK: data: — 리더 판정

    @Test("작성자가 쓴 래스터 data: 는 통과한다")
    func anAuthorsRasterDataURISurvives() {
        let result = sanitize(#"<img src="data:image/png;base64,AAAA">"#)

        #expect(result.blocked.isEmpty)
        #expect(result.html.contains("data:image/png;base64,AAAA"))
    }

    @Test("작성자가 쓴 SVG data: 는 제거된다 — CSP 가 못 보는 자리다")
    func anAuthorsSVGDataURIIsRemoved() {
        // **이 케이스가 2겹 설계의 존재 이유다.** `WKContentRuleList` 도 CSP 도 `data:`
        // 안의 미디어 타입을 구분하지 못한다. 여기서 안 막으면 어디서도 안 막힌다.
        let result = sanitize(#"<img src="data:image/svg+xml;base64,PHN2Zz4=">"#)

        #expect(result.blocked.contains { $0.kind == .remoteImage })
        #expect(
            fetchableValues(in: result.html, containing: "svg+xml").isEmpty,
            "SVG data: 가 페치 가능한 자리에 남았다"
        )
    }

    // MARK: CSS url()

    @Test("style 속성 안의 원격 url() 도 제거된다")
    func remoteURLsInStyleAttributesAreRemoved() {
        let result = sanitize(#"<div style="background: url('https://evil.com/bg.png')">x</div>"#)

        #expect(fetchableValues(in: result.html, containing: "evil.com").isEmpty)
        #expect(!result.blocked.isEmpty)
    }

    @Test("style 블록 안의 원격 url() 도 제거된다")
    func remoteURLsInStyleBlocksAreRemoved() {
        let result = sanitize("<style>body { background: url(https://evil.com/bg.png); }</style>")
        #expect(fetchableValues(in: result.html, containing: "evil.com").isEmpty)
    }

    // MARK: srcset

    @Test("srcset 은 통째로 버린다")
    func srcsetIsDroppedEntirely() {
        // 후보 목록을 부분 재작성하면 구멍 뚫린 목록이 되고, 브라우저가 자기 마음에 드는
        // 항목을 고른다.
        let result = sanitize(#"<img srcset="https://evil.com/a.png 1x, b.png 2x" src="data:image/png;base64,AA">"#)

        #expect(fetchableValues(in: result.html, containing: "evil.com").isEmpty)
        #expect(!result.blocked.isEmpty)
    }

    // MARK: CSP 백스톱

    @Test("CSP 메타가 주입된다")
    func theContentSecurityPolicyIsInjected() {
        #expect(sanitize("<html><head></head><body></body></html>").html
            .contains("Content-Security-Policy"))
    }

    @Test("head 가 없는 조각에도 주입된다")
    func aFragmentGetsThePolicyToo() {
        // 마크다운은 조각으로 렌더된다. head 를 요구하면 그 경로가 통째로 무방비다.
        #expect(sanitize("<p>hello</p>").html.contains("Content-Security-Policy"))
    }

    @Test("CSP 가 이미지 말고는 아무것도 허용하지 않는다")
    func thePolicyAllowsNothingButOurImages() {
        let policy = RenderDocumentSanitizer.contentSecurityPolicy

        #expect(policy.contains("default-src 'none'"))
        #expect(policy.contains("script-src 'none'"))
        #expect(policy.contains("frame-src 'none'"))
        #expect(policy.contains("connect-src 'none'"))
        // `img-src data:` 가 안전한 것은 **위 재작성이 성립할 때뿐이다** — 작성자 data: 가
        // 하나도 안 남기 때문에 미디어 타입을 CSP 가 구분할 필요가 없어진다.
        #expect(policy.contains("img-src data:"))
    }

    // MARK: 전체 성질

    @Test("여러 참조가 섞여 있어도 작성자 URI 가 하나도 안 남는다")
    func noAuthorURISurvivesAMixedDocument() {
        let html = """
        <html><head><link rel="stylesheet" href="https://cdn.example.com/a.css"></head>
        <body>
          <img src="https://evil.com/x.png" alt="x">
          <iframe src="https://evil.com/frame"></iframe>
          <div style="background: url(https://evil.com/bg.png)"></div>
          <script src="https://evil.com/s.js"></script>
        </body></html>
        """
        let result = sanitize(html)

        #expect(
            fetchableValues(in: result.html, containing: "evil.com").isEmpty,
            "페치 가능한 자리에 남은 참조: \(result.html)"
        )
        #expect(!result.html.contains("cdn.example.com"))
        #expect(result.blocked.count >= 4, "차단 목록이 \(result.blocked.count)건뿐")
    }

    @Test("차단 목록이 그대로 칩·팝오버로 이어진다")
    func theBlockedListFeedsThePopover() {
        let result = sanitize("""
        <img src="https://a.com/1.png"><img src="https://b.com/2.png">
        <script>x</script>
        """)
        let panel = BlockedResourcePresentation.make(blocked: result.blocked)

        #expect(panel.blockedCount == result.blocked.count)
        #expect(panel.chipLabel.hasPrefix("🛡 차단됨"))
        #expect(panel.rows.contains { $0.kind == .remoteImage })
        #expect(panel.rows.contains { $0.kind == .script })
    }

    @Test("차단할 것이 없는 문서는 그대로 통과한다")
    func acleanDocumentIsLeftAlone() {
        // 반대 방향. 전부 지우는 구현이면 위 테스트들이 전부 통과하면서 렌더가 아무것도
        // 못 그린다.
        let result = sanitize("<h1>제목</h1><p>본문입니다.</p>")

        #expect(result.blocked.isEmpty)
        #expect(result.html.contains("<h1>제목</h1>"))
        #expect(result.html.contains("본문입니다."))
    }

    // MARK: 링크는 리소스가 아니다

    @Test("<a href> 는 인라인하지 않는다 — 네비게이션이지 페치가 아니다")
    func anchorsAreLeftForTheNavigationHandler() throws {
        // 처음에 `href` 를 리소스로 취급했더니 **루트 안 `.md` 링크가 data: 로 인라인돼
        // 링크가 파괴**됐다. W-14 는 클릭 동작을 따로 정의한다(이 탭에서 열기 / 브라우저 /
        // 상태바 거부). 로드는 클릭 전까지 일어나지 않고, 페이지가 스스로 뭘 가져오는 것은
        // CSP 가 막는다.
        let fixture = try TemporaryProject()
        defer { fixture.cleanUp() }

        let result = RenderDocumentSanitizer.sanitize(
            html: ##"<a href="OTHER.md">문서</a><a href="#anchor">앵커</a>"##,
            projectRoot: fixture.root.path,
            loadFile: { _ in Data("x".utf8) }
        )

        #expect(result.html.contains("href=\"OTHER.md\""), "링크가 재작성됐다: \(result.html)")
        #expect(result.html.contains("href=\"#anchor\""), "문서 내 앵커가 깨졌다")
    }

    @Test("이름이 비슷한 속성에 속지 않고 진짜 src 를 비운다")
    func theRealSourceAttributeIsTheOneRewritten() {
        // **이 테스트가 실제 결함을 잡았다.** `src="` 를 부분 문자열로 찾으면
        // `data-src="` 안에서도 걸린다. 그래서 미끼를 재작성하고 **진짜 `src` 를 원격인
        // 채로 남겼다.** 문서가 속성 이름을 정하므로 스캐너는 기대한 이름만 온다고
        // 가정할 수 없다.
        let result = sanitize(#"<img data-src="https://evil.com/x.png" src="https://evil.com/x.png">"#)

        // 무력화의 **방식**은 바뀌었다(비우기 → 요소째 W-15 박스로 교체). 그래서 `src=""`
        // 를 찾던 단언은 더 이상 그 성질을 재지 못한다. 재려던 것은 형태가 아니라
        // **"진짜 참조가 페치 가능한 자리에 안 남는다"** 이므로 그것을 직접 잰다.
        #expect(
            fetchableValues(in: result.html, containing: "evil.com").isEmpty,
            "진짜 src 가 페치 가능한 자리에 남았다: \(result.html)"
        )
        #expect(result.blocked.contains { $0.kind == .remoteImage })
        // 미끼만 재작성하고 끝내지 않았다는 것 — 차단이 실제로 한 번 일어났다.
        #expect(result.html.contains("차단되었습니다"))
    }

    @Test("data-* 는 남지만 아무것도 가져오지 못한다")
    func inertDataAttributesAreLeftAlone() {
        // `data-*` 는 스크립트가 읽어야 의미가 생기는데 스크립트는 제거되고 CSP 가
        // `script-src 'none'` 이다. **페치를 일으킬 수 있는 자리**의 URI 가 하나도 안
        // 남는다는 것이 이 단계의 성질이고, 불활성 메타데이터까지 지우는 것은 문서를
        // 망가뜨리는 과잉이다.
        let result = sanitize(#"<img data-tracking="https://evil.com/px" src="data:image/png;base64,AA">"#)

        #expect(result.html.contains("data-tracking"), "불활성 속성까지 지웠다")
        #expect(result.html.contains("script-src 'none'"), "그것을 읽을 수 있는 경로가 열려 있다")
    }

    // MARK: 경로 판정을 우회하는 문들 (리더 지적)

    @Test("<base> 는 제거된다 — 경로 판정을 통째로 무의미하게 만든다")
    func theBaseTagIsRemoved() {
        // `<base href="file:///Users/victim/.ssh/">` 뒤의 `src="id_rsa"` 는 **상대 경로라
        // 내 정책이 "루트 안"으로 판정**하는데, 브라우저는 base 기준으로 연다. 판정이
        // 옳아도 다른 파일이 열린다. 허용 목록이 아니라 제거인 이유다 — 우리가 통제하지
        // 못하는 전제 위에 허용을 세우지 않는다.
        let result = sanitize(##"<head><base href="file:///Users/victim/.ssh/"></head><img src="id_rsa">"##)

        #expect(!result.html.contains("<base"), "base 가 남았다: \(result.html)")
        #expect(!result.html.contains(".ssh"))
    }

    @Test("basefont 처럼 이름이 겹치는 태그는 지우지 않는다")
    func aTagMerelyStartingWithBaseSurvives() {
        // `<base` 를 부분 문자열로 지우면 `<basefont>` 도 사라진다 — `data-src` 때와 같은
        // 형태의 실수다.
        let result = sanitize("<basefont size=\"3\">글자</basefont>")
        #expect(result.html.contains("basefont"), "이름이 겹칠 뿐인 태그를 지웠다")
    }

    @Test("meta refresh 는 제거된다 — 스크립트 없이 이동한다")
    func aMetaRefreshIsRemoved() {
        let result = sanitize(#"<meta http-equiv="refresh" content="0;url=https://evil.com">"#)

        #expect(!result.html.contains("refresh"), "meta refresh 가 남았다")
        #expect(fetchableValues(in: result.html, containing: "evil.com").isEmpty)
    }

    @Test("평범한 meta 는 남는다")
    func anOrdinaryMetaSurvives() {
        // charset 까지 지우면 문서 인코딩이 깨진다.
        #expect(sanitize(#"<meta charset="utf-8">"#).html.contains("charset"))
    }

    @Test("iframe srcdoc 은 비워진다 — 속성 안의 문서다")
    func srcdocIsEmptied() {
        let result = sanitize(#"<iframe srcdoc="<script>alert(1)</script>"></iframe>"#)
        #expect(!result.html.contains("alert"), "srcdoc 내용이 남았다: \(result.html)")
    }

    @Test("문서 안 조각 참조는 그대로 둔다")
    func inDocumentFragmentsAreLeftAlone() {
        // `<use href="#icon">` 는 아무것도 가져오지 않는다. 경로 규칙에 태우면 루트
        // 기준으로 해석돼 없는 파일이 되고, 멀쩡한 참조가 비워진다.
        let result = sanitize(##"<svg><use href="#icon"/></svg>"##)
        #expect(result.html.contains("href=\"#icon\""), "문서 내 참조가 지워졌다: \(result.html)")
    }

    @Test("CSP 가 head 안에서 다른 참조보다 앞에 온다")
    func thePolicyPrecedesEveryReference() {
        // 뒤에 오면 그 앞의 참조는 이미 나간 뒤다.
        let result = sanitize(#"<html><head><link rel="stylesheet" href="a.css"><title>t</title></head></html>"#)

        guard let policyIndex = result.html.range(of: "Content-Security-Policy")?.lowerBound,
              let linkIndex = result.html.range(of: "<link")?.lowerBound
        else {
            Issue.record("CSP 또는 link 를 찾지 못했다: \(result.html)")
            return
        }
        #expect(policyIndex < linkIndex, "CSP 가 참조보다 뒤에 있다")
    }

    // MARK: xlink:href — SVG 의 옛 철자 (리더 지적)

    @Test("xlink:href 로 쓴 원격 참조도 1층에서 잡힌다")
    func theLegacyXlinkSpellingIsCaught() {
        // WebKit 이 아직 지원한다. CSP 가 막긴 하지만 **조용히** 막아서 차단 목록에 안
        // 실리고, 그러면 사용자가 W-15 칩에서 무엇이 빠졌는지 볼 수 없다.
        let result = sanitize(#"<svg><image xlink:href="https://evil.com/pixel.png"/></svg>"#)

        #expect(
            fetchableValues(in: result.html, containing: "evil.com").isEmpty,
            "xlink:href 가 페치 가능한 자리에 남았다: \(result.html)"
        )
        #expect(result.blocked.contains { $0.kind == .remoteImage }, "차단 목록에 안 실렸다 — 칩에 안 보인다")
    }

    @Test("xlink:href 의 조각 참조는 그대로 둔다")
    func aLegacyFragmentReferenceSurvives() {
        let result = sanitize(##"<svg><use xlink:href="#icon"/></svg>"##)
        #expect(result.html.contains("xlink:href=\"#icon\""), "문서 내 참조가 지워졌다: \(result.html)")
    }

    @Test("href 검색이 xlink:href 안에서 걸리지 않는다")
    func thePlainSpellingDoesNotMatchInsideTheLegacyOne() {
        // 경계 규칙이 `data-src` 를 막은 것과 같은 이유로 `xlink:href` 도 막는다 —
        // 그래서 옛 철자는 **따로 이름을 대야만** 보인다. 두 철자가 한 요소에 같이 있어도
        // 각자 처리돼야 한다.
        let result = sanitize(#"<svg><image href="https://a.com/1.png" xlink:href="https://b.com/2.png"/></svg>"#)

        #expect(!result.html.contains("a.com"), "href 가 안 바뀌었다")
        #expect(!result.html.contains("b.com"), "xlink:href 가 안 바뀌었다")
    }
}

/// A real project directory with a real image inside it.
private struct TemporaryProject {
    let base: URL
    let root: URL

    init() throws {
        base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sanitizer-\(UUID().uuidString)")
        root = base.appendingPathComponent("project")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data([0x89, 0x50]).write(to: root.appendingPathComponent("images/logo.png"))
    }

    func cleanUp() { try? FileManager.default.removeItem(at: base) }
}
