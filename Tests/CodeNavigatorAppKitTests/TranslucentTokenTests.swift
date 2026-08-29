import Testing
@testable import CodeNavigatorAppKit

/// Design §4.1 states two tokens as `rgba(...)` rather than hex: `accent-dim` (selected
/// rows and banner backgrounds) and `match` (search highlights). `ColorToken` carries no
/// alpha, so those two are absent from `DesignTokens` — and they are exactly the tokens
/// W-3, W-5 and W-6 need.
///
/// Expressed here as a base colour plus a per-appearance opacity. The point of the tests is
/// that the *product* still equals what §4.1 writes down, so the translucent tokens cannot
/// drift away from the document the way an eyeballed alpha would.
@Suite("반투명 토큰 — §4.1의 rgba 값 (REQ-011 AC-4)")
struct TranslucentTokenTests {

    @Test("accent-dim 라이트는 rgba(0,122,255,.12)")
    func accentDimLightMatchesTheDocument() {
        let token = DesignTokens.accentDim
        #expect(token.light == RGBColor(hex: "#007AFF"))
        #expect(token.lightOpacity == 0.12)
    }

    @Test("accent-dim 다크는 rgba(77,159,255,.16)")
    func accentDimDarkMatchesTheDocument() {
        // 다크의 밑색은 accent(#0A84FF)가 아니라 accent-text(#4D9FFF)다 — §4.1의 숫자를
        // 그대로 읽으면 그렇다. 직관으로 accent를 쓰면 조용히 다른 색이 된다.
        let token = DesignTokens.accentDim
        #expect(token.dark == RGBColor(hex: "#4D9FFF"))
        #expect(token.darkOpacity == 0.16)
    }

    @Test("match 라이트는 rgba(224,162,27,.30)")
    func matchLightMatchesTheDocument() {
        let token = DesignTokens.match
        #expect(token.light == RGBColor(hex: "#E0A21B"))
        #expect(token.lightOpacity == 0.30)
    }

    @Test("match 다크는 rgba(232,179,61,.26)")
    func matchDarkMatchesTheDocument() {
        let token = DesignTokens.match
        #expect(token.dark == RGBColor(hex: "#E8B33D"))
        #expect(token.darkOpacity == 0.26)
    }

    @Test("반투명 토큰의 밑색은 §4.1의 불투명 토큰과 같은 값이다")
    func theBaseColoursAreExistingTokens() {
        // 새 색을 들여온 것이 아니라 기존 토큰에 §4.1이 명시한 알파를 씌운 것뿐이라는 확인.
        #expect(DesignTokens.accentDim.light == DesignTokens.accent.light)
        #expect(DesignTokens.accentDim.dark == DesignTokens.accentText.dark)
        #expect(DesignTokens.match.light == DesignTokens.warningSolid.light)
        #expect(DesignTokens.match.dark == DesignTokens.warningSolid.dark)
    }

    @Test("불투명도는 0과 1 사이다")
    func opacitiesAreWithinRange() {
        for token in [DesignTokens.accentDim, DesignTokens.match] {
            #expect(token.lightOpacity > 0 && token.lightOpacity < 1, "\(token.name)")
            #expect(token.darkOpacity > 0 && token.darkOpacity < 1, "\(token.name)")
        }
    }
}
