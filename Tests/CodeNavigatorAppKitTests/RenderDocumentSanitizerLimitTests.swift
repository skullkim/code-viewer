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

        #expect(!result.html.contains("evil.com"), "따옴표 없는 값이 남았다: \(result.html)")
        #expect(!result.blocked.isEmpty)
    }

    @Test("회귀: 속성값 안의 > 가 태그를 일찍 끊지 못한다")
    func aBracketInsideAValueDoesNotEndTheTag() {
        // 첫 `>` 를 태그 끝으로 보면 `alt="a>b"` 에서 요소가 잘리고, **그 뒤의 진짜 src 는
        // 아예 검사되지 않는다.** 실측으로 잔존을 확인하고 따옴표 인식으로 고쳤다.
        let result = sanitize(#"<img alt="a>b" src="https://evil.com/w.png">"#)

        #expect(!result.html.contains("evil.com"), "가짜 태그 끝 뒤의 참조가 남았다: \(result.html)")
    }

    @Test("회귀: = 주변 공백이 있어도 같은 속성이다")
    func whitespaceAroundEqualsIsStillTheSameAttribute() {
        let result = sanitize(#"<img src = "https://evil.com/t.png">"#)
        #expect(!result.html.contains("evil.com"), "공백 낀 속성이 남았다: \(result.html)")
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
        #expect(!sanitize(#"<IMG SRC="https://evil.com/u.png">"#).html.contains("evil.com"))
    }

    @Test("태그 안 개행도 잡는다")
    func newlinesInsideATagAreCaught() {
        #expect(!sanitize("<img\n  src=\"https://evil.com/v.png\">").html.contains("evil.com"))
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
