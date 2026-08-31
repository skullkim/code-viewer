import Testing
@testable import CodeNavigatorAppKit

/// W-15 의 본문 자리표시자. **HTML 이다** — 문서는 웹뷰 안에서 그려지므로 SwiftUI 박스는 그
/// 안에 들어갈 자리가 원리적으로 없다(리더 판정 D1, ADR-0109).
@Suite("BlockedResourceBox — 차단된 자리에 남는 박스 (W-15 · INV-6)")
struct BlockedResourceBoxTests {

    private func box(
        _ kind: BlockedResourceKind,
        detail: String = "evil.example",
        alternativeText: String? = nil
    ) -> String {
        BlockedResourceBox.html(kind: kind, detail: detail, alternativeText: alternativeText)
    }

    // MARK: 무엇이 빠졌는지 말한다

    @Test("종류를 문장으로 말한다")
    func theBoxNamesWhatWasBlocked() {
        #expect(box(.remoteImage).contains("원격 이미지가 차단되었습니다"))
        #expect(box(.frame).contains("프레임이 차단되었습니다"))
    }

    @Test("루트 밖 파일은 다른 문장이다")
    func aFileOutsideTheRootReadsDifferently() {
        // "차단되었습니다"만으로는 왜인지 모른다 — 이건 정책이 아니라 위치의 문제다.
        let output = box(.outsideProjectRoot, detail: "/etc/passwd")

        #expect(output.contains("프로젝트 폴더 밖"))
        #expect(output.contains("/etc/passwd"))
    }

    @Test("출처가 박스에 남는다")
    func theSourceIsShown() {
        // 칩은 개수를 세지만 "이 자리에 뭐가 있었나"는 여기서만 보인다.
        #expect(box(.remoteImage, detail: "cdn.example.com").contains("cdn.example.com"))
    }

    @Test("alt 가 있으면 보여 주고 없으면 줄을 만들지 않는다")
    func alternativeTextAppearsOnlyWhenPresent() {
        #expect(box(.remoteImage, alternativeText: "회사 로고").contains("회사 로고"))
        #expect(!box(.remoteImage, alternativeText: nil).contains("alt:"))
        #expect(!box(.remoteImage, alternativeText: "").contains("alt:"))
    }

    // MARK: 자리를 차지하던 것만

    @Test("공간을 차지하지 않던 종류는 박스를 남기지 않는다")
    func kindsThatOccupiedNoSpaceLeaveNoBox() {
        // 차단된 스크립트는 페이지에 자리가 없었다. 박스를 그리면 문서에 없던 구멍을 만든다.
        #expect(box(.script).isEmpty)
        #expect(box(.remoteStylesheet).isEmpty)
        #expect(box(.remoteFont).isEmpty)
    }

    @Test("자리를 차지하던 종류는 전부 박스를 남긴다")
    func everyKindThatOccupiedSpaceLeavesABox() {
        for kind in BlockedResourceKind.allCases where kind.showsInlinePlaceholder {
            #expect(!box(kind).isEmpty, "\(kind.rawValue)")
        }
    }

    // MARK: 문서에서 온 문자열은 마크업이 되지 않는다

    @Test("출처의 꺾쇠가 태그가 되지 않는다")
    func angleBracketsInTheSourceDoNotBecomeMarkup() {
        let output = box(.remoteImage, detail: "<script>alert(1)</script>")

        #expect(!output.contains("<script>"))
        #expect(output.contains("&lt;script&gt;"))
    }

    @Test("출처의 따옴표가 속성을 끝내지 못한다")
    func quotesInTheSourceCannotCloseAnAttribute() {
        // 박스는 `aria-label` 안에 출처를 넣는다. 이스케이프를 빼면 차단 고지 자체가
        // 주입 통로가 된다 — 막았다고 말하는 자리에서.
        let output = box(.remoteImage, detail: "\" onmouseover=\"alert(1)")

        #expect(!output.contains("onmouseover=\"alert(1)\""))
        #expect(output.contains("&quot;"))
    }

    @Test("alt 의 꺾쇠도 태그가 되지 않는다")
    func angleBracketsInAltTextDoNotBecomeMarkup() {
        let output = box(.remoteImage, alternativeText: "<img src=x onerror=y>")

        #expect(!output.contains("<img src=x"))
    }

    // MARK: 화면에 읽히는 형태

    @Test("스크린리더가 읽을 이름이 있다")
    func theBoxHasAnAccessibleName() {
        let output = box(.remoteImage, alternativeText: "회사 로고")

        #expect(output.contains("aria-label="))
        #expect(output.contains("role=\"img\""))
    }

    @Test("문단 안에 들어가도 되는 인라인 요소다")
    func theBoxIsInlineLevel() {
        // `<p>` 안의 `<img>` 를 대신하므로 블록 요소를 넣으면 문단이 쪼개진다.
        let output = box(.remoteImage)

        #expect(output.hasPrefix("<span"))
        #expect(output.hasSuffix("</span>"))
    }

    @Test("테마 토큰을 쓰되 없어도 보인다")
    func theBoxUsesThemeTokensWithFallbacks() {
        // 호스트 스타일시트가 아직 없다. 변수만 쓰면 색이 안 잡히고, 값만 쓰면 나중에
        // 테마를 못 따라간다 — 그래서 변수 + 폴백이다.
        let output = box(.remoteImage)

        #expect(output.contains("var(--cn-"))
        #expect(output.contains("var(--cn-text-secondary, "))
    }
}
