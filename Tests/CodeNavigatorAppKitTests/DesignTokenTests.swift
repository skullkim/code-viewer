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
        #expect(DesignTokens.allColorTokens.count >= 20)
        #expect(DesignTokens.badgeTokens.count == 4)
        #expect(DesignTokens.badgeBearingSurfaces.count >= 4)
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

    @Test("심볼 종류 배지 색이 놓이는 모든 표면에서 3:1 이상이다", arguments: AppearanceScheme.allCases)
    func badgeColoursClearTheirFloor(scheme: AppearanceScheme) {
        // §4.5 sets 3:1 for badges rather than 4.5:1, because a badge carries one letter
        // and is never the only signal — the kind is also spelled out in the row. The
        // floor still has to hold on every surface a badge appears on.
        for token in DesignTokens.badgeTokens {
            for surface in DesignTokens.badgeBearingSurfaces {
                let ratio = ColorContrast.ratio(token.value(for: scheme), surface.value(for: scheme))
                #expect(
                    ratio >= DesignTokens.minimumBadgeContrastRatio,
                    "배지 \(token.name) on \(surface.name) (\(scheme)): \(String(format: "%.3f", ratio)):1"
                )
            }
        }
    }

    @Test("teal은 프로토타입의 --syn-type 값과 같다")
    func tealMatchesThePrototype() {
        // The prototype styles the I and T badges with --syn-type; keeping the same hex
        // means the visual reference stays usable for the fidelity comparison.
        #expect(DesignTokens.teal.light == RGBColor(hex: "#0E7166"))
        #expect(DesignTokens.teal.dark == RGBColor(hex: "#57C7B8"))
    }

    /// 구문 색이 놓이는 표면은 **셋**이다 — 평문 배경 · 선택 배경 · 같은 심볼 강조 배경.
    /// §4.5 규약("그 토큰이 실제로 놓이는 모든 표면 중 최악값")을 편집기에 적용하면 6종 × 3표면
    /// = **18조합**이다.
    ///
    /// ⚠ 초판은 콘텐츠 배경 **한 곳**만 검사하고 통과했는데, 그 값들은 **선택 배경 위에서 6종 중
    /// 4종이 4.5:1 아래**였다(type 4.46 · str 4.39 · num 3.93 · cmt 4.01, 라이트). 즉 드래그하는
    /// 순간 바닥을 뚫었다. **표면을 하나만 걷는 검사는 초록인 채로 갭을 덮는다.**
    @Test("구문 강조 토큰이 편집기 표면 3종 전부에서 대비 바닥을 넘는다 (REQ-016 AC-3)", arguments: AppearanceScheme.allCases)
    func syntaxTokensClearTheContrastFloorOnEveryEditorSurface(scheme: AppearanceScheme) {
        // 둘 중 하나라도 비면 아래 루프가 안 돌고 테스트는 저절로 통과한다.
        #expect(!DesignTokens.syntaxTokens.isEmpty, "구문 토큰 목록이 비면 이 검사는 아무것도 안 지킨다")
        #expect(DesignTokens.editorSurfaces.count == 3, "표면이 셋이 아니면 §4.1.1 과 어긋난다")

        for token in DesignTokens.syntaxTokens {
            for surface in DesignTokens.editorSurfaces {
                let ratio = ColorContrast.ratio(token.value(for: scheme), surface.value(for: scheme))
                #expect(
                    ratio >= DesignTokens.minimumTextContrastRatio,
                    "\(token.name) on \(surface.name) (\(scheme)): \(ratio)"
                )
            }
        }
    }

    /// 대비는 *읽히는가*를 묻고 ΔE 는 *구별되는가*를 묻는다. **둘은 다른 질문이고, 이 요구가
    /// 고치는 결함은 두 번째 쪽이다** — nvim 기본 키워드 색은 평문과 값이 **같아서**(ΔE 0)
    /// 대비는 완벽한데 키워드로 보이지 않는다. 대비만 검사하면 그 팔레트가 건강하다고 나온다.
    @Test("구문 색이 평문과 충분히 떨어져 있다 — ΔE 바닥 (REQ-016 AC-1)", arguments: AppearanceScheme.allCases)
    func syntaxTokensAreFarEnoughFromPlainText(scheme: AppearanceScheme) {
        #expect(!DesignTokens.syntaxTokens.isEmpty)
        let plain = DesignTokens.editorPlainForeground.value(for: scheme)

        for token in DesignTokens.syntaxTokens {
            let distance = ColorContrast.colorDistance(token.value(for: scheme), plain)
            #expect(
                distance >= DesignTokens.minimumSyntaxColorDistance,
                "\(token.name) (\(scheme)) ΔE=\(distance) — 평문과 구별되지 않는다"
            )
        }
    }

    @Test("여섯 구문 색이 서로도 구별된다", arguments: AppearanceScheme.allCases)
    func theSixSyntaxColoursAreDistinctFromEachOther(scheme: AppearanceScheme) {
        // 전부 평문에서 멀어도 서로 붙어 있으면 키워드와 타입을 구별할 수 없다.
        let tokens = DesignTokens.syntaxTokens
        #expect(tokens.count == 6)

        for (index, token) in tokens.enumerated() {
            for other in tokens[(index + 1)...] {
                let distance = ColorContrast.colorDistance(
                    token.value(for: scheme), other.value(for: scheme)
                )
                #expect(
                    distance >= DesignTokens.minimumSyntaxColorDistance,
                    "\(token.name) ↔ \(other.name) (\(scheme)) ΔE=\(distance)"
                )
            }
        }
    }

    @Test("구문 강조 토큰이 §4.1.1 발행값과 같다")
    func syntaxTokensMatchTheDesignDocument() {
        // AC-3 은 "색이 02_design 토큰에서 온다"를 요구한다. 그 문장이 참이려면 토큰이 문서와
        // 같아야 하고, 같은지는 여기서만 검사된다 — 팔레트를 Neovim 에 넘기는 쪽은 값이 옳은지
        // 알 수 없고 넘기기만 한다.
        //
        // ⚠ 단일 소스는 **§4.1.1 표**다. 초판은 §4.1 산문(:289)에서 값을 가져왔고, 그 사이 PD 가
        // 표를 새로 발행해 5개가 갈라졌다. 산문은 "이런 색들이 있다"를 적고 표는 "어느 표면에서
        // 얼마인가"를 적는다 — 구현이 읽어야 하는 것은 표다.
        let published: [(ColorToken, String, String)] = [
            (DesignTokens.syntaxKeyword, "#A626A4", "#C792EA"),
            (DesignTokens.syntaxType, "#0E7166", "#57C7B8"),
            (DesignTokens.syntaxFunction, "#1A56C4", "#82AAFF"),
            (DesignTokens.syntaxString, "#2B742E", "#C3E88D"),
            (DesignTokens.syntaxNumber, "#9E4F00", "#F78C6C"),
            (DesignTokens.syntaxComment, "#606570", "#9AA0AD"),
        ]
        #expect(published.count == DesignTokens.syntaxTokens.count, "발행값 표가 토큰 수와 어긋난다")

        for (token, light, dark) in published {
            #expect(token.light == RGBColor(hex: light), "\(token.name) light")
            #expect(token.dark == RGBColor(hex: dark), "\(token.name) dark")
        }
    }

    @Test("편집기 강조 배경 두 종이 §4.1.1 발행값과 같다")
    func theEditorHighlightBackgroundsMatchTheDesignDocument() {
        // 둘 다 §4.1.1 이 **불투명 hex 로** 발행한다 — nvim_set_hl 이 8자리 hex 를 거절하므로
        // 앱이 합성해서 넘길 수 없고, 합성 지점이 디자인 문서로 옮겨갔다.
        #expect(DesignTokens.backgroundSelection.light == RGBColor(hex: "#E0EFFF"))
        #expect(DesignTokens.backgroundSelection.dark == RGBColor(hex: "#233043"))
        #expect(DesignTokens.backgroundSameSymbol.light == RGBColor(hex: "#E8E8E8"))
        #expect(DesignTokens.backgroundSameSymbol.dark == RGBColor(hex: "#343438"))
    }

    @Test("같은 심볼 배경과 선택 배경은 서로 다르다")
    func theTwoHighlightBackgroundsAreNotTheSame() {
        // 검색 결과와 커서 아래 심볼은 동시에 화면에 있을 수 있다. 같은 색이면 두 사건이
        // 한 색이 되고, 사용자는 무엇이 무엇인지 알 수 없다 — PD 가 match 재사용을 반려한 이유.
        for scheme in AppearanceScheme.allCases {
            #expect(
                DesignTokens.backgroundSameSymbol.value(for: scheme)
                    != DesignTokens.backgroundSelection.value(for: scheme),
                "\(scheme)"
            )
        }
    }

    @Test("syntax-type 과 teal 은 같은 색이다 — 하나만 움직일 수 없다")
    func syntaxTypeAndTealStayTogether() {
        // 같은 색이 두 이름으로 있다. 배지가 그리는 teal 과 에디터가 그리는 타입 색이
        // 갈라지면 같은 개념이 화면에서 두 색이 된다 — 조용하고, 스크린샷 대조에서만 보인다.
        // §4.1.1 이 라이트를 #0F7A6E → #0E7166 으로 바꿨을 때 실제로 갈라질 뻔했다.
        #expect(DesignTokens.syntaxType.light == DesignTokens.teal.light)
        #expect(DesignTokens.syntaxType.dark == DesignTokens.teal.dark)
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
