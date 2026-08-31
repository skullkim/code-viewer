import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// What the scanner does and does not catch — **measured, not assumed** (INV-6 layer one).
///
/// This file exists because the limits were previously recorded only in a comment, and the
/// comment was wrong: it claimed comments and CDATA were not understood (they are) while
/// omitting three real bypasses it did have. A limit written in prose cannot be re-measured
/// by the next person; a limit written as a test fails the day it changes.
///
/// The cases below are grouped into two kinds, and the difference matters:
///   - **회귀**: bypasses that were real and are now closed. These must keep passing.
///   - **알려진 한계**: things this layer genuinely does not do. They assert the *current*
///     behaviour so that closing one later shows up as a failure, and someone decides
///     whether it was intended.
@Suite("RenderDocumentSanitizer 한계 — 무엇을 잡고 무엇을 못 잡는가")
struct RenderDocumentSanitizerLimitTests {

    private func sanitize(_ html: String) -> SanitizedDocument {
        RenderDocumentSanitizer.sanitize(
            html: html,
            projectRoot: "/Users/dev/repo",
            loadFile: { _ in nil }
        )
    }

    // MARK: 회귀 — 실측으로 발견해 닫은 우회 3종

    @Test("회귀: 따옴표 없는 속성값도 잡는다")
    func unquotedAttributeValuesAreCaught() {
        // HTML 은 따옴표를 요구하지 않는다. 따옴표만 찾던 스캐너에게 이 형태는
        // **보이지 않았고**, 작성자가 그렇게 쓰기만 하면 1층이 통째로 우회됐다.
        let result = sanitize(#"<img src=https://evil.com/x.png>"#)

        #expect(
            fetchableValues(in: result.html, containing: "evil.com").isEmpty,
            "따옴표 없는 값이 페치 가능한 자리에 남았다: \(result.html)"
        )
        #expect(!result.blocked.isEmpty)
    }

    @Test("회귀: 속성값 안의 > 가 태그를 일찍 끊지 못한다")
    func aBracketInsideAValueDoesNotEndTheTag() {
        // 첫 `>` 를 태그 끝으로 보면 `alt="a>b"` 에서 요소가 잘리고, **그 뒤의 진짜 src 는
        // 아예 검사되지 않는다.** 실측으로 잔존을 확인하고 따옴표 인식으로 고쳤다.
        let result = sanitize(#"<img alt="a>b" src="https://evil.com/w.png">"#)

        #expect(
            fetchableValues(in: result.html, containing: "evil.com").isEmpty,
            "가짜 태그 끝 뒤의 참조가 페치 가능한 자리에 남았다: \(result.html)"
        )
    }

    @Test("회귀: = 주변 공백이 있어도 같은 속성이다")
    func whitespaceAroundEqualsIsStillTheSameAttribute() {
        let result = sanitize(#"<img src = "https://evil.com/t.png">"#)
        #expect(
            fetchableValues(in: result.html, containing: "evil.com").isEmpty,
            "공백 낀 속성이 페치 가능한 자리에 남았다: \(result.html)"
        )
    }

    // MARK: 잡는 것 — 주석·CDATA·대문자·개행 (주석이 반대로 적혀 있던 것들)

    @Test("주석 안의 참조도 재작성된다")
    func referencesInsideCommentsAreRewritten() {
        // 이전 주석은 "주석을 모른다"고 적혀 있었으나 실측은 반대였다. 주석 안까지
        // 재작성하는 것은 과할지언정 안전한 방향이다.
        #expect(!sanitize("<!-- <img src=\"https://evil.com/x.png\"> -->").html.contains("evil.com"))
    }

    @Test("CDATA 안의 참조도 재작성된다")
    func referencesInsideCDATAAreRewritten() {
        #expect(!sanitize("<![CDATA[<img src=\"https://evil.com/z.png\">]]>").html.contains("evil.com"))
    }

    @Test("대문자 태그·속성도 잡는다")
    func uppercaseMarkupIsCaught() {
        let result = sanitize(#"<IMG SRC="https://evil.com/u.png">"#)
        #expect(fetchableValues(in: result.html, containing: "evil.com").isEmpty)
    }

    @Test("태그 안 개행도 잡는다")
    func newlinesInsideATagAreCaught() {
        let result = sanitize("<img\n  src=\"https://evil.com/v.png\">")
        #expect(fetchableValues(in: result.html, containing: "evil.com").isEmpty)
    }

    // MARK: 알려진 한계 — 고쳐야 할 실패가 아니다

    @Test("알려진 한계: 이 층은 HTML 을 파싱하지 않는다 — CSP 가 그 뒤를 받는다")
    func theKnownLimitIsThatThisIsNotAParser() {
        // **이 테스트는 결함 보고가 아니다.** 스캐너는 태그와 속성을 문자열로 훑는다.
        // 여기 없는 구문(문서 타입 특유의 표기, 미래의 요소·속성)은 놓칠 수 있고, 그것이
        // 2층이 존재하는 이유다.
        //
        // **CSP 가 덮는 범위 — 정책 문자열을 그대로 읽은 것**:
        //   default-src 'none'  → 아래에 안 적힌 모든 종류의 가져오기가 거부된다
        //   img-src data:       → 이미지는 `data:` 만. 따라서 `https:` 도 **`file:` 도** 거부
        //   script-src 'none'   → 외부·인라인 스크립트 모두
        //   frame-src 'none' · font-src 'none' · connect-src 'none'
        // 즉 스캐너가 놓친 참조가 **원격이든 로컬 `file:` 이든** 정책상 가져오지 못한다.
        let policy = RenderDocumentSanitizer.contentSecurityPolicy

        #expect(policy.contains("default-src 'none'"))
        #expect(policy.contains("img-src data:"))
        // `file:` 이 따로 허용되지 않는다는 것이 위 주장의 근거다.
        #expect(!policy.contains("file:"), "정책이 file: 을 허용하면 위 설명이 거짓이 된다")
    }

    @Test("이벤트 핸들러는 1층이 지우지 않는다 — 2층이 막는다는 것을 실측했다")
    func inlineEventHandlersAreLeftToTheBackstop() {
        // 마크다운은 원시 HTML 을 품을 수 있고, 신뢰하지 않는 레포의 README 가
        // `<img onerror="…">` 를 담는 것이 INV-6 이 상정한 바로 그 상황이다.
        //
        // 1층은 **참조만** 다루므로 핸들러 속성은 남는다. 그것이 결함이 아니라는 근거는
        // 추론이 아니라 실측이다 — 스파이크에 인라인 핸들러 프로브를 넣고 **JS 를 켠 채**
        // (즉 `allowsContentJavaScript = false` 의 도움 없이 **CSP 단독의 힘**만으로) 쟀다:
        //
        //   대조군 조각  원격 21건 · `/from-onerror` 3건 도착   ← 핸들러가 실제로 실행됨
        //   CSP    조각  원격  0건 · `/from-onerror` 0건
        //   CSP    페이지 원격  0건 · `/from-onerror` 0건
        //
        // `<script>` 요소와 인라인 핸들러는 **다른 구문이고 CSP 에서도 다른 검사를 탄다.**
        // 앞의 것이 막힌다고 뒤의 것이 막히는 것은 아니라서 따로 쟀다.
        //
        // 따라서 핸들러를 여기서 긁어내는 규칙을 더하지 않는다 — 속성 이름 목록을 세는 방식은
        // 빠뜨린 이름이 곧 구멍이고, 그 구멍은 조용하다. 이 층이 지키는 성질은 좁게 유지한다.
        // 예시는 **1층을 살아서 통과하는** 요소여야 한다. 차단된 이미지를 쓰면 요소째
        // 박스로 바뀌면서 핸들러가 같이 사라지고(아래 테스트가 그 사실을 고정한다), 그러면
        // 이 테스트는 "핸들러가 남는다"가 아니라 "차단됐다"를 재게 된다 — 재려던 것과 다른 것.
        let result = sanitize("<p onclick=\"fetch('https://evil.example')\">문단</p>")

        #expect(result.html.contains("onclick"), "1층은 핸들러를 지우지 않는다 — 그 사실을 고정한다")
        // 위 실측의 전제. 이 지시어가 빠지면 측정 결과가 근거가 아니게 되므로 같이 깨져야 한다.
        #expect(
            RenderDocumentSanitizer.contentSecurityPolicy.contains("script-src 'none'"),
            "핸들러 차단의 근거가 이 지시어다"
        )
    }

    @Test("차단된 이미지의 핸들러는 요소째 사라진다")
    func aBlockedImageTakesItsHandlerWithIt() {
        // W-15 박스가 요소를 통째로 대신하면서 생긴 부수 효과인데, 방향이 맞으므로 고정한다.
        // 위 테스트가 말하는 "1층은 핸들러를 안 지운다"는 **살아남는 요소**에 대한 말이고,
        // 차단된 이미지는 살아남지 않는다. 두 문장이 모순이 아니라는 것을 여기서 보인다.
        let result = sanitize("<img src=\"https://evil.example/x.png\" onerror=\"fetch('https://evil.example')\">")

        #expect(!result.html.contains("onerror"))
        #expect(result.html.contains("차단되었습니다"))
    }

    @Test("2층은 실측됐다 — 다만 이 테스트가 재는 것은 주입까지다")
    func theSecondLayerIsMeasuredElsewhere() {
        // **이 단위 테스트가 보장하는 것은 문자열이 문서에 들어간다는 것까지다.** 강제
        // 여부는 런타임 사실이라 단위 테스트로 잴 수 없고, `scripts/spike-csp-enforcement.swift`
        // 가 실제 리스너로 쟀다(2026-08-30):
        //
        //   대조군 loadHTMLString  원격 18건 · 래스터 표시됨   ← 리스너가 살아 있다는 증거
        //   CSP    loadHTMLString  원격  0건 · 래스터 표시됨
        //   대조군 loadFileURL     원격 18건 · 래스터 표시됨
        //   CSP    loadFileURL     원격  0건 · 래스터 표시됨
        //
        // **머리 없는 조각도 따로 쟀다**(2026-08-31, `--fragment`). 첫 측정은 `<head>` 가 있는
        // 완전한 페이지만 재는데, **마크다운은 그 모양을 만들지 않는다** — 위의 "head 가 없는
        // 조각에도 주입된다"가 바로 그 경로이고, 거기서는 정책 메타가 문서 맨 앞에 온다.
        // 파서가 그것을 head 로 끌어올린다는 것은 그럴듯한 이야기였을 뿐이라 실제로 쟀다:
        //
        //   대조군 조각 loadHTMLString  원격 18건 · 래스터 표시됨
        //   CSP    조각 loadHTMLString  원격  0건 · 래스터 표시됨
        //   CSP    조각 loadFileURL     원격  0건 · 래스터 표시됨
        //
        // 즉 **마크다운 경로에서도 2층이 실재한다.** 재기 전까지 이 경로의 2층은 가정이었다.
        //
        // 대조군을 **먼저** 통과시켰기 때문에 0 이 "막았다"를 뜻한다 — 그 순서가 아니면
        // 0 은 "리스너가 고장났다"와 구별되지 않는다. 그리고 `data:` 래스터가 네 변종
        // 모두에서 떴으므로 **과차단도 아니다**.
        //
        // 스크립트는 앱이 주입하는 것과 **같은 정책 문자열**을 쓴다. 정책을 여기서 고치면
        // 스파이크의 근거가 낡으므로 다시 재야 한다.
        let result = sanitize("<p>x</p>")
        #expect(result.html.contains("Content-Security-Policy"), "문자열 주입까지가 이 층의 보장이다")
        #expect(
            result.html.contains(RenderDocumentSanitizer.contentSecurityPolicy),
            "주입되는 정책이 스파이크가 측정한 그 문자열이어야 한다"
        )
    }
}
