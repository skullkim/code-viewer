import Testing
@testable import CodeNavigatorAppKit

@Suite("ColorContrast — WCAG 대비 계산")
struct ColorContrastTests {

    @Test("흑백 대비는 21:1이다")
    func blackOnWhiteIsTheMaximum() {
        let ratio = ColorContrast.ratio(RGBColor(hex: "#000000")!, RGBColor(hex: "#FFFFFF")!)
        #expect(abs(ratio - 21.0) < 0.01)
    }

    @Test("같은 색끼리는 1:1이다")
    func aColourAgainstItselfIsOne() {
        let colour = RGBColor(hex: "#1C1C1E")!
        #expect(abs(ColorContrast.ratio(colour, colour) - 1.0) < 0.001)
    }

    @Test("대비는 순서에 무관하다")
    func ratioIsSymmetric() {
        let first = RGBColor(hex: "#55555E")!
        let second = RGBColor(hex: "#FFFFFF")!
        #expect(abs(ColorContrast.ratio(first, second) - ColorContrast.ratio(second, first)) < 0.0001)
    }

    @Test("16진 파싱이 채널을 올바르게 나눈다")
    func hexParsingSplitsChannels() {
        let colour = RGBColor(hex: "#0A84FF")!
        #expect(abs(colour.red - 10.0 / 255) < 0.0001)
        #expect(abs(colour.green - 132.0 / 255) < 0.0001)
        #expect(abs(colour.blue - 255.0 / 255) < 0.0001)
    }

    @Test("잘못된 16진 문자열은 nil이다")
    func malformedHexIsRejected() {
        #expect(RGBColor(hex: "#FFF") == nil)
        #expect(RGBColor(hex: "не-цвет") == nil)
        #expect(RGBColor(hex: "#GGGGGG") == nil)
    }
}
