import Testing
@testable import CodeNavigatorAppKit

/// REQ-013 AC-1. The converter feeds the sandbox pass, so the tests are split in two: what it
/// must *draw*, and what it must never *manufacture*.
@Suite("MarkdownDocument — 마크다운을 렌더 표면의 HTML 조각으로 (REQ-013 AC-1)")
struct MarkdownDocumentTests {

    private func html(_ markdown: String) -> String {
        MarkdownDocument.html(from: markdown)
    }

    // MARK: 만들어 내지 않아야 할 것 (INV-6 인접)
    //
    // 이 절의 시험들은 서식이 아니라 **경계**에 관한 것이다. 변환기는 보안 경계가 아니지만,
    // 문서에 없던 마크업을 스스로 만들어 내면 그다음 샌드박스가 검사할 대상 자체가 달라진다.

    @Test("산문의 꺾쇠와 앰퍼샌드는 문자로 남는다")
    func proseAngleBracketsAreEscaped() {
        let output = html("a < b && c > d 는 참이다")

        #expect(output.contains("&lt;"))
        #expect(output.contains("&amp;&amp;"))
        // 이스케이프를 두 번 하면 사용자에게 `&amp;lt;` 가 보인다 — & 를 먼저 바꿔야 한다.
        #expect(!output.contains("&amp;lt;"))
    }

    @Test("코드 블록 안의 스크립트 태그는 글자로 그려진다")
    func fencedCodeContentIsEscaped() {
        let output = html("```\n<script>alert(1)</script>\n```")

        #expect(output.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        // 살아 있는 태그가 남으면 예제를 보여 주려던 문서가 예제를 실행시킨다.
        #expect(!output.contains("<script>"))
    }

    @Test("인라인 코드 안의 태그도 글자로 그려진다")
    func inlineCodeContentIsEscaped() {
        let output = html("설정은 `<img src=x onerror=y>` 처럼 쓴다")

        #expect(output.contains("<code>&lt;img src=x onerror=y&gt;</code>"))
        #expect(!output.contains("<img"))
    }

    @Test("링크 주소 안의 따옴표가 속성을 끝내지 못한다")
    func quotesInAUrlCannotCloseTheAttribute() {
        // `[x](" onerror="alert(1))` 류. 이스케이프를 안 하면 마크다운이 속성 주입 통로가 된다.
        let output = html("[클릭](\" onerror=\"alert(1))")

        #expect(!output.contains("onerror=\"alert(1)\""))
        #expect(output.contains("&quot;"))
    }

    @Test("이미지 alt 안의 따옴표도 속성을 끝내지 못한다")
    func quotesInAltTextCannotCloseTheAttribute() {
        let output = html("![\" onerror=\"alert(1)](logo.png)")

        #expect(!output.contains("onerror=\"alert(1)\""))
        #expect(output.contains("&quot;"))
    }

    @Test("원시 HTML 은 일부러 통과시킨다 — 검사는 샌드박스가 한다")
    func rawHtmlPassesThroughOnPurpose() {
        // ADR-0109: 마크다운과 HTML 은 한 표면을 지난다. 여기서 거르면 경계가 둘이 되고,
        // 둘 중 약한 쪽이 실제 경계가 된다.
        let output = html("<div class=\"note\">주의</div>")

        #expect(output.contains("<div class=\"note\">"))
    }

    // MARK: 블록

    @Test("ATX 제목이 수준별로 그려진다")
    func atxHeadingsRenderAtTheirLevel() {
        #expect(html("# 제목").contains("<h1>제목</h1>"))
        #expect(html("### 제목").contains("<h3>제목</h3>"))
        #expect(html("###### 제목").contains("<h6>제목</h6>"))
    }

    @Test("샵 일곱 개는 제목이 아니다")
    func sevenHashesIsNotAHeading() {
        let output = html("####### 제목")

        #expect(!output.contains("<h7"))
        #expect(output.contains("<p>"))
    }

    @Test("빈 줄이 문단을 가른다")
    func blankLinesSeparateParagraphs() {
        let output = html("첫 문단\n\n둘째 문단")

        #expect(output.contains("<p>첫 문단</p>"))
        #expect(output.contains("<p>둘째 문단</p>"))
    }

    @Test("한 문단 안의 줄바꿈은 문단을 쪼개지 않는다")
    func aLineBreakInsideAParagraphKeepsOneParagraph() {
        let output = html("첫 줄\n둘째 줄")

        #expect(output.contains("<p>"))
        #expect(!output.contains("</p>\n<p>"))
    }

    @Test("펜스 코드의 언어가 class 로 남는다")
    func aFencedBlockKeepsItsLanguage() {
        let output = html("```swift\nlet x = 1\n```")

        #expect(output.contains("<pre><code class=\"language-swift\">"))
        #expect(output.contains("let x = 1"))
    }

    @Test("언어 없는 펜스는 class 를 붙이지 않는다")
    func aFencedBlockWithoutALanguageHasNoClass() {
        let output = html("```\nplain\n```")

        #expect(output.contains("<pre><code>"))
        #expect(!output.contains("class=\"language-"))
    }

    @Test("코드 블록 안의 마크다운은 서식이 되지 않는다")
    func markdownInsideCodeStaysLiteral() {
        let output = html("```\n# 제목이 아니다\n*강조도 아니다*\n```")

        #expect(!output.contains("<h1>"))
        #expect(!output.contains("<em>"))
        #expect(output.contains("# 제목이 아니다"))
    }

    @Test("닫히지 않은 펜스가 문서를 삼키지 않는다")
    func anUnclosedFenceStillCloses() {
        // 깨진 마크업에서 빈 화면을 보이지 않는다(AC-6)는 요구를 변환 단계에서 지킨다.
        let output = html("```\ncode without an end")

        #expect(output.contains("code without an end"))
        #expect(output.contains("</code></pre>"))
    }

    @Test("글머리 기호 세 종류가 모두 목록이 된다")
    func allThreeBulletMarkersMakeAList() {
        for marker in ["-", "*", "+"] {
            let output = html("\(marker) 하나\n\(marker) 둘")
            #expect(output.contains("<ul>"), "\(marker)")
            #expect(output.contains("<li>하나</li>"), "\(marker)")
            #expect(output.contains("<li>둘</li>"), "\(marker)")
        }
    }

    @Test("번호 목록이 ol 이 된다")
    func numberedItemsMakeAnOrderedList() {
        let output = html("1. 하나\n2. 둘")

        #expect(output.contains("<ol>"))
        #expect(output.contains("<li>하나</li>"))
    }

    @Test("목록이 끝나면 닫힌다")
    func aListClosesWhenItEnds() {
        let output = html("- 하나\n\n그다음 문단")

        #expect(output.contains("</ul>"))
        #expect(output.contains("<p>그다음 문단</p>"))
    }

    @Test("인용이 blockquote 가 되고 안의 서식이 산다")
    func blockquotesKeepTheirInlineFormatting() {
        let output = html("> **강조된** 인용")

        #expect(output.contains("<blockquote>"))
        #expect(output.contains("<strong>강조된</strong>"))
    }

    @Test("가로줄이 hr 이 된다")
    func aThematicBreakBecomesAnHr() {
        #expect(html("---").contains("<hr>"))
        #expect(html("***").contains("<hr>"))
    }

    // MARK: 인라인

    @Test("강조와 굵게가 구별된다")
    func emphasisAndStrongAreDistinct() {
        #expect(html("*기울임*").contains("<em>기울임</em>"))
        #expect(html("_기울임_").contains("<em>기울임</em>"))
        #expect(html("**굵게**").contains("<strong>굵게</strong>"))
        #expect(html("__굵게__").contains("<strong>굵게</strong>"))
    }

    @Test("굵게가 기울임보다 먼저 잡힌다")
    func strongWinsOverEmphasis() {
        // `**x**` 를 기울임 규칙이 먼저 먹으면 `<em></em>` 이 낀 이상한 중첩이 나온다.
        let output = html("**굵게**")

        #expect(!output.contains("<em>"))
    }

    @Test("링크가 그려진다")
    func linksRender() {
        let output = html("[문서](docs/README.md)")

        #expect(output.contains("<a href=\"docs/README.md\">문서</a>"))
    }

    @Test("이미지가 그려지고 alt 가 남는다")
    func imagesRenderWithAlt() {
        let output = html("![로고](assets/logo.png)")

        #expect(output.contains("<img"))
        #expect(output.contains("src=\"assets/logo.png\""))
        #expect(output.contains("alt=\"로고\""))
    }

    @Test("이미지가 링크로 오해되지 않는다")
    func anImageIsNotReadAsALink() {
        let output = html("![로고](assets/logo.png)")

        // `!` 를 놓치면 `<a>` 가 되고, 그러면 샌드박스의 앵커 예외를 타고 검사를 통째로 비켜간다.
        #expect(!output.contains("<a href"))
    }

    @Test("코드 스팬 안의 별표는 강조가 아니다")
    func asterisksInsideCodeAreLiteral() {
        let output = html("`*not em*`")

        #expect(!output.contains("<em>"))
        #expect(output.contains("*not em*"))
    }

    @Test("역슬래시로 이스케이프한 별표는 글자로 남는다")
    func backslashEscapedAsterisksStayLiteral() {
        let output = html(##"\*강조 아님\*"##)

        #expect(!output.contains("<em>"))
        #expect(output.contains("*강조 아님*"))
        #expect(!output.contains(##"\*"##))
    }

    @Test("문서 안 앵커 링크가 살아남는다")
    func inDocumentAnchorsSurvive() {
        let output = html("[위로](#top)")

        #expect(output.contains("href=\"#top\""))
    }

    // MARK: 표 (문서에 흔하다)

    @Test("표가 thead 와 tbody 로 그려진다")
    func tablesRenderWithAHeadAndBody() {
        let output = html("| 이름 | 값 |\n|---|---|\n| a | 1 |")

        #expect(output.contains("<table>"))
        #expect(output.contains("<th>이름</th>"))
        #expect(output.contains("<td>a</td>"))
    }

    @Test("표 칸 안의 서식이 산다")
    func tableCellsKeepInlineFormatting() {
        let output = html("| 이름 |\n|---|\n| `코드` |")

        #expect(output.contains("<code>코드</code>"))
    }

    @Test("구분선이 없으면 표가 아니다")
    func withoutADelimiterRowItIsNotATable() {
        let output = html("| 그냥 | 파이프 |")

        #expect(!output.contains("<table>"))
    }

    // MARK: 빈 입력

    @Test("빈 문서는 빈 조각을 낸다")
    func anEmptyDocumentProducesAnEmptyFragment() {
        #expect(html("").isEmpty)
        #expect(html("\n\n   \n").isEmpty)
    }
}
