import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// The mapping from design tokens to the editor palette (REQ-016 AC-3).
///
/// The failure this guards against is not "no colour" — it is **the wrong colour in the right
/// place**. A crossed wire (type where keyword belongs) paints a screen that looks finished and
/// is wrong, and no screenshot comparison catches it unless someone already knows what keywords
/// should look like. So every slot is checked against the token it is supposed to carry.
@Suite("구문 팔레트 조립 — 토큰이 제 자리에 들어가는가 (REQ-016 AC-3)")
struct SyntaxPaletteBuilderTests {

    @Test("여섯 구문 색이 각자 제 토큰에서 온다", arguments: AppearanceScheme.allCases)
    func everySyntaxSlotCarriesItsOwnToken(scheme: AppearanceScheme) {
        let palette = SyntaxPaletteBuilder.palette(for: scheme)

        let expected: [(String, EditorColor, ColorToken)] = [
            ("keyword", palette.keyword, DesignTokens.syntaxKeyword),
            ("type", palette.type, DesignTokens.syntaxType),
            ("function", palette.function, DesignTokens.syntaxFunction),
            ("string", palette.string, DesignTokens.syntaxString),
            ("number", palette.number, DesignTokens.syntaxNumber),
            ("comment", palette.comment, DesignTokens.syntaxComment),
        ]
        #expect(expected.count == DesignTokens.syntaxTokens.count, "슬롯 수가 토큰 수와 어긋난다")

        for (slot, actual, token) in expected {
            #expect(actual == EditorColor(token.value(for: scheme)), "\(slot) (\(scheme))")
        }
    }

    @Test("여섯 색이 서로 다르다 — 한 색으로 뭉개지지 않았다", arguments: AppearanceScheme.allCases)
    func theSixColoursAreDistinct(scheme: AppearanceScheme) {
        // 전부 같은 토큰을 읽는 실수는 위 테스트도 통과시킬 수 있다(기대값을 같이 틀리면).
        // 색이 여섯 가지라는 것 자체가 AC-1 이 요구하는 바다.
        let palette = SyntaxPaletteBuilder.palette(for: scheme)

        let colours = Set([
            palette.keyword, palette.type, palette.function,
            palette.string, palette.number, palette.comment,
        ])

        #expect(colours.count == 6, "구문 색이 \(colours.count)가지뿐이다 — 서로 다른 색이어야 한다")
    }

    @Test("라이트와 다크가 실제로 다르다")
    func theTwoAppearancesDiffer() {
        let light = SyntaxPaletteBuilder.palette(for: .light)
        let dark = SyntaxPaletteBuilder.palette(for: .dark)

        #expect(light != dark, "외형을 무시하면 다크 모드에서 라이트 색이 그려진다")
        #expect(light.comment != dark.comment)
        #expect(light.selectionBackground != dark.selectionBackground)
    }

    @Test("배경 두 종이 §4.1.1 발행 토큰에서 그대로 온다", arguments: AppearanceScheme.allCases)
    func theBackgroundsComeFromTheirPublishedTokens(scheme: AppearanceScheme) {
        // 초판은 여기서 반투명 토큰을 평탄화했다. §4.1.1 이 두 배경을 **불투명 hex 로** 직접
        // 발행하면서 합성 지점이 앱에서 디자인 문서로 옮겨갔다 — nvim_set_hl 이 8자리 hex 를
        // 거절하기 때문이고, 덕분에 값이 화면에 칠해지기 전에 사람이 검토한다.
        let palette = SyntaxPaletteBuilder.palette(for: scheme)

        #expect(
            palette.sameSymbolBackground
                == EditorColor(DesignTokens.backgroundSameSymbol.value(for: scheme))
        )
        #expect(
            palette.selectionBackground
                == EditorColor(DesignTokens.backgroundSelection.value(for: scheme))
        )
    }

    @Test("같은 심볼 배경이 검색 강조와 같은 색이 아니다", arguments: AppearanceScheme.allCases)
    func theSameSymbolBackgroundIsNotTheSearchHighlight(scheme: AppearanceScheme) {
        // 이 단언이 PD 반려의 내용이다 — 검색 결과 패널과 커서 아래 심볼은 **동시에** 화면에
        // 있을 수 있고, 같은 색이면 두 사건이 한 색이 된다.
        let palette = SyntaxPaletteBuilder.palette(for: scheme)
        let searchHighlight = EditorColor(
            DesignTokens.match.flattened(
                over: DesignTokens.backgroundContent.value(for: scheme), for: scheme
            )
        )

        #expect(palette.sameSymbolBackground != searchHighlight, "\(scheme)")
    }

    @Test("선택 배경과 같은 심볼 배경이 서로 다르다", arguments: AppearanceScheme.allCases)
    func theTwoHighlightBackgroundsDiffer(scheme: AppearanceScheme) {
        let palette = SyntaxPaletteBuilder.palette(for: scheme)

        #expect(palette.selectionBackground != palette.sameSymbolBackground, "\(scheme)")
    }

    @Test("평문·배경이 편집기 표면 토큰에서 온다 — 빈 채로 나가지 않는다", arguments: AppearanceScheme.allCases)
    func plainTextAndBackgroundAreNamedExplicitly(scheme: AppearanceScheme) {
        // AC-6 이 여기서 조용히 깨진다. 색을 **안 주기로 한** 그룹(`Identifier`·`Normal`)을
        // 비워 두면 사용자 colorscheme 이 그 자리를 채우고, 화면에 우리가 고르지 않은 색이
        // 뜬다. 평문은 "색 없음"이 아니라 **평문 색으로 정해진 것**이어야 한다.
        let palette = SyntaxPaletteBuilder.palette(for: scheme)

        #expect(palette.normalForeground == EditorColor(DesignTokens.textPrimary.value(for: scheme)))
        #expect(
            palette.normalBackground == EditorColor(DesignTokens.backgroundContent.value(for: scheme))
        )
    }

    @Test("키워드는 굵게 나간다", arguments: AppearanceScheme.allCases)
    func keywordsGoOutBold(scheme: AppearanceScheme) {
        // 굵기는 **두 번째 채널**이다. 색만으로는 적록 색각에서 마젠타 키워드가 평문과 가까워질
        // 수 있는데, 굵기는 색을 못 가려도 남는다.
        #expect(SyntaxPaletteBuilder.palette(for: scheme).keywordIsBold)
    }

    @Test("평문 전경이 구문 6색 중 어느 것과도 같지 않다", arguments: AppearanceScheme.allCases)
    func plainTextIsNotOneOfTheSyntaxColours(scheme: AppearanceScheme) {
        // 우리가 고치는 결함이 정확히 이것이다 — nvim 기본 키워드 색이 **평문과 같은 값**이라
        // 대비는 멀쩡한데 키워드로 보이지 않았다. 값이 같아지는 순간 그 결함이 돌아온다.
        let palette = SyntaxPaletteBuilder.palette(for: scheme)
        let syntaxColours = [
            palette.keyword, palette.type, palette.function,
            palette.string, palette.number, palette.comment,
        ]
        #expect(syntaxColours.count == 6)

        for colour in syntaxColours {
            #expect(colour != palette.normalForeground, "구문 색 하나가 평문과 같다 (\(scheme))")
        }
    }

    @Test("두 색 다리가 서로를 되돌린다")
    func theTwoColourBridgesRoundTrip() {
        // `RGBColor(EditorColor)` 는 나눗셈이고 `EditorColor(RGBColor)` 는 곱셈이다. 뒤쪽이
        // 반올림이 아니라 절삭이면 거의 모든 채널이 1씩 줄어드는데, 화면에서는 안 보이고
        // 팔레트 값만 조용히 어긋난다.
        let samples = [
            EditorColor(red: 0, green: 0, blue: 0),
            EditorColor(red: 255, green: 255, blue: 255),
            EditorColor(packedRGB: 0xA626A4),
            EditorColor(packedRGB: 0x6E7481),
            EditorColor(packedRGB: 0x010203),
        ]
        #expect(!samples.isEmpty)

        for original in samples {
            #expect(EditorColor(RGBColor(original)) == original, "\(original) 왕복 실패")
        }
    }
}
