import Testing
@testable import CodeNavigatorAppKit

/// Resolving a translucent token against the surface under it.
///
/// Neovim highlight groups carry no alpha, so the same-symbol highlight (REQ-016 AC-2) cannot
/// be handed over as `match` — it has to become one opaque colour first. These tests pin the
/// two ends and one real value rather than restating the blend, because a test that recomputes
/// the formula agrees with the implementation even when both are wrong.
@Suite("반투명 토큰 평탄화 — 알파 없는 곳으로 넘길 색 (REQ-016 AC-2)")
struct TranslucentTokenFlatteningTests {

    private let tolerance = 0.002

    private func expectClose(
        _ actual: RGBColor,
        _ expected: RGBColor,
        _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(actual.red - expected.red) < tolerance, "\(label) red: \(actual.red)", sourceLocation: sourceLocation)
        #expect(abs(actual.green - expected.green) < tolerance, "\(label) green: \(actual.green)", sourceLocation: sourceLocation)
        #expect(abs(actual.blue - expected.blue) < tolerance, "\(label) blue: \(actual.blue)", sourceLocation: sourceLocation)
    }

    @Test("완전히 불투명하면 배경이 사라진다", arguments: AppearanceScheme.allCases)
    func fullyOpaqueLeavesOnlyTheSource(scheme: AppearanceScheme) {
        let solid = TranslucentColorToken(
            name: "solid", light: RGBColor(hex: "#123456")!, lightOpacity: 1,
            dark: RGBColor(hex: "#123456")!, darkOpacity: 1
        )

        let result = solid.flattened(over: RGBColor(hex: "#FFFFFF")!, for: scheme)

        expectClose(result, RGBColor(hex: "#123456")!, "opaque \(scheme)")
    }

    @Test("완전히 투명하면 배경만 남는다", arguments: AppearanceScheme.allCases)
    func fullyTransparentLeavesOnlyTheBackground(scheme: AppearanceScheme) {
        let invisible = TranslucentColorToken(
            name: "invisible", light: RGBColor(hex: "#123456")!, lightOpacity: 0,
            dark: RGBColor(hex: "#123456")!, darkOpacity: 0
        )
        let background = RGBColor(hex: "#1B1B1F")!

        let result = invisible.flattened(over: background, for: scheme)

        expectClose(result, background, "transparent \(scheme)")
    }

    /// 기대값의 출처는 CSS 다. 프로토타입이 `match` 를 `rgba(224,162,27,.30)` 로 쓰고, 그것을
    /// 흰 배경 위에 얹으면 브라우저가 내는 색이 이 값이다 — 채널마다
    /// `224·0.30 + 255·0.70 = 245.7` 식으로 계산했다. 구현이 아니라 **대조 대상**에서 왔다.
    @Test("match 를 흰 배경에 얹으면 프로토타입 CSS 와 같은 색이 된다")
    func matchOverWhiteAgreesWithTheProtoype() {
        let white = RGBColor(hex: "#FFFFFF")!

        let result = DesignTokens.match.flattened(over: white, for: .light)

        expectClose(
            result,
            RGBColor(red: 245.7 / 255, green: 227.1 / 255, blue: 186.6 / 255),
            "match over white"
        )
    }

    @Test("평탄화된 색은 원색과 배경 사이에 있다")
    func theResultSitsBetweenSourceAndBackground() {
        // 방향 불변식. 공식을 베끼지 않고도 부호가 뒤집히거나 알파가 반대로 쓰인 것을 잡는다.
        let background = RGBColor(hex: "#FFFFFF")!
        let (source, opacity) = DesignTokens.match.value(for: .light)
        #expect(opacity > 0 && opacity < 1, "이 단언은 반투명일 때만 의미가 있다")

        let result = DesignTokens.match.flattened(over: background, for: .light)

        // match 는 배경(흰색)보다 어둡고 원색보다 밝아야 한다.
        #expect(result.red < background.red && result.red > source.red, "red \(result.red)")
        #expect(result.green < background.green && result.green > source.green, "green \(result.green)")
        #expect(result.blue < background.blue && result.blue > source.blue, "blue \(result.blue)")
    }
}
