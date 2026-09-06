import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 편집기의 **주변부** — 상태줄, 버퍼 끝의 `~`, 사인 열. 코드가 아니라서 오래 방치됐는데,
/// 방치의 대가가 라이트 모드에서 드러났다: 밝은 화면 아래에 어두운 회색 막대가 남아
/// 편집기 절반이 다른 앱처럼 보였다.
///
/// 색을 안 주면 nvim 기본값이 나온다. 그건 우리 배경을 모르고 고른 색이라, 대비가 맞을
/// 이유가 없다.
@Suite("편집기 주변부 대비")
struct EditorChromeContrastTests {

    private func palette(_ scheme: AppearanceScheme) -> EditorSyntaxPalette {
        SyntaxPaletteBuilder.palette(for: scheme)
    }

    /// `EditorColor` 는 0–255 정수이고 `RGBColor` 는 0–1 실수다. 그대로 넘기면 컴파일도
    /// 안 되지만, 255 로 안 나누고 넘겼다면 모든 대비가 21:1 로 나와 검사가 통째로 무의미했다.
    private func ratio(_ foreground: EditorColor, on background: EditorColor) -> Double {
        ColorContrast.ratio(rgb(foreground), rgb(background))
    }

    private func rgb(_ colour: EditorColor) -> RGBColor {
        RGBColor(
            red: Double(colour.red) / 255,
            green: Double(colour.green) / 255,
            blue: Double(colour.blue) / 255
        )
    }

    /// 3:1 은 WCAG 의 큰 글자·UI 구성요소 기준이다. 상태줄은 글자가 작지만 읽어야 하는
    /// 정보(파일명·위치)를 담으므로 4.5:1 을 요구한다.
    @Test("상태줄 글자가 상태줄 배경 위에서 읽힌다")
    func theStatusLineIsLegible() {
        for scheme in AppearanceScheme.allCases {
            let palette = palette(scheme)
            let measured = ratio(palette.statusLineForeground, on: palette.statusLineBackground)
            #expect(measured >= 4.5, "\(scheme) 상태줄 대비 \(measured)")
        }
    }

    /// `~` 와 사인 열은 정보가 아니라 **경계 표시**다. 너무 밝으면 코드로 오인되고 너무
    /// 어두우면 편집기가 어디서 끝나는지 안 보인다. 3:1 이 그 사이다.
    @Test("버퍼 끝 표시와 사인 열이 배경과 구분된다")
    func theBufferEdgeIsVisible() {
        for scheme in AppearanceScheme.allCases {
            let palette = palette(scheme)
            for (name, colour) in [
                ("endOfBuffer", palette.endOfBufferForeground),
                ("nonText", palette.nonTextForeground),
            ] {
                let measured = ratio(colour, on: palette.normalBackground)
                #expect(measured >= 3.0, "\(scheme) \(name) 대비 \(measured)")
            }
        }
    }

    /// 사인 열 배경은 편집기 배경과 **같아야** 한다. 다르면 브레이크포인트가 없는 줄에도
    /// 세로 띠가 생겨서, 사용자는 그것을 무언가 켜져 있는 표시로 읽는다.
    @Test("사인 열 배경이 편집기 배경과 같다")
    func theSignColumnBlendsIn() {
        for scheme in AppearanceScheme.allCases {
            let palette = palette(scheme)
            #expect(palette.signColumnBackground == palette.normalBackground, "\(scheme)")
        }
    }

    /// 이 스위트가 실제로 무언가를 재는지 확인한다. 색이 전부 같으면 대비는 1 이고,
    /// 그러면 위 검사들이 전부 실패해야 한다 — 실패하지 않으면 검사가 죽은 것이다.
    @Test("검사기 자체 검사 — 같은 색이면 대비가 1 이다")
    func theCheckerCanFail() {
        let white = EditorColor(red: 255, green: 255, blue: 255)
        let black = EditorColor(red: 0, green: 0, blue: 0)
        #expect(ratio(white, on: white) < 1.01)
        #expect(ratio(black, on: white) > 20)
    }
}
