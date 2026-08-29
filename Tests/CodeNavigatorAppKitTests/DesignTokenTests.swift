import Testing
@testable import CodeNavigatorAppKit

/// Design §4.5 sets a contrast floor for text and §4.1 lists the values. A token is one
/// hex digit away from failing accessibility, and nothing in a screenshot review reliably
/// catches that, so the floor is checked here instead of trusted.
@Suite("DesignTokens — 토큰 값과 접근성 (REQ-011 AC-4, 02 §4)")
struct DesignTokenTests {

    @Test("검사 대상 컬렉션이 비어 있지 않다 — 방어선이 조용히 사라지지 않게")
    func theCollectionsUnderTestAreNotEmpty() {
        // Every contrast check below is a `for` loop over a production collection. Empty
        // one and the loops run zero times, the suite goes green, and the accessibility
        // floor disappears without a word. A defence line that has already caught a real
        // defect (3.81:1 on the toolbar) is worth defending in turn.
        #expect(DesignTokens.textTokens.count >= 8)
        #expect(DesignTokens.textBearingSurfaces.count >= 6)
        #expect(DesignTokens.allColorTokens.count >= 19)
        #expect(AppearanceScheme.allCases.count == 2)
    }

    @Test("모든 텍스트 토큰이 실제로 놓이는 모든 배경에서 4.5:1 이상이다", arguments: AppearanceScheme.allCases)
    func everyTextTokenClearsTheContrastFloorOnEverySurface(scheme: AppearanceScheme) {
        // Checking only against the content background is how the published text-3 came to
        // be listed at 5.0:1 while measuring 3.81:1 on the toolbar. Text is checked against
        // every surface it is drawn on, not against the most flattering one.
        for token in DesignTokens.textTokens {
            for surface in DesignTokens.textBearingSurfaces {
                let ratio = ColorContrast.ratio(token.value(for: scheme), surface.value(for: scheme))
                #expect(
                    ratio >= DesignTokens.minimumTextContrastRatio,
                    "\(token.name) on \(surface.name) (\(scheme)): \(String(format: "%.3f", ratio)):1 — 4.5:1 미만"
                )
            }
        }
    }

    @Test("힌트·라인 번호 색이 툴바와 상태바에서도 읽힌다")
    func theHintColourSurvivesTheChromeBackgrounds() {
        // text-3 carries the key hints in the status bar and the shortcut labels in the
        // toolbar. Those two backgrounds are the darkest light surfaces in the system, and
        // they are exactly where the original value failed.
        for scheme in AppearanceScheme.allCases {
            for surface in [DesignTokens.backgroundStatus, DesignTokens.backgroundWindow, DesignTokens.backgroundElevated] {
                let ratio = ColorContrast.ratio(
                    DesignTokens.textTertiary.value(for: scheme),
                    surface.value(for: scheme)
                )
                #expect(ratio >= DesignTokens.minimumTextContrastRatio, "text-3 on \(surface.name) (\(scheme)): \(ratio)")
            }
        }
    }

    @Test("두 테마의 토큰 값이 서로 다르다 — 다크 모드가 라이트를 그대로 쓰지 않는다")
    func theTwoSchemesActuallyDiffer() {
        // A token accidentally given the same value twice would look correct in one theme
        // and unreadable in the other.
        for token in DesignTokens.allColorTokens where token.name != "bg-elevated" {
            #expect(token.light != token.dark, "\(token.name)의 라이트/다크 값이 같다")
        }
    }

    @Test("배경 토큰이 라이트에서 밝고 다크에서 어둡다")
    func backgroundsFollowTheirScheme() {
        let backgrounds = [
            DesignTokens.backgroundWindow, DesignTokens.backgroundSidebar,
            DesignTokens.backgroundContent, DesignTokens.backgroundPanel,
            DesignTokens.backgroundStatus, DesignTokens.backgroundElevated,
        ]
        for token in backgrounds {
            let lightLuminance = ColorContrast.relativeLuminance(
                red: token.light.red, green: token.light.green, blue: token.light.blue
            )
            let darkLuminance = ColorContrast.relativeLuminance(
                red: token.dark.red, green: token.dark.green, blue: token.dark.blue
            )
            #expect(lightLuminance > darkLuminance, "\(token.name)의 라이트가 다크보다 어둡다")
        }
    }

    @Test("간격 스케일이 §4.3의 4/8/12/16/24/32다")
    func spacingScaleMatchesTheDocument() {
        #expect(DesignTokens.Spacing.scale == [4, 8, 12, 16, 24, 32])
    }

    @Test("라운딩 값이 §4.3과 일치한다")
    func cornerRadiiMatchTheDocument() {
        #expect(DesignTokens.Radius.control == 5)
        #expect(DesignTokens.Radius.surface == 8)
        #expect(DesignTokens.Radius.modal == 10)
        #expect(DesignTokens.Radius.chip == 999)
    }
}
