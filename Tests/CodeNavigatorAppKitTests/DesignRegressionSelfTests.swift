import Testing
import AppKit
import CoreGraphics
@testable import CodeNavigatorAppKit

/// Checks the checker (`_workspace/CERTIFICATION.md`: a checker running is not a checker
/// catching).
///
/// Every defect the gate claims to catch is planted here and the detector has to fire. The
/// planting happens in bitmaps built in memory — nothing under `Sources/` is modified, so an
/// interrupted run cannot leave the tree damaged. That failure mode is not hypothetical: it
/// happened today when a self-test mutated real sources.
@MainActor
@Suite("디자인 회귀 게이트 자체 검사 — 심어 놓고 잡히는지 본다")
struct DesignRegressionSelfTests {

    /// A bitmap filled with one colour — what a render that drew nothing produces.
    private func flatCanvas(
        width: Int = 200,
        height: Int = 120,
        colour: NSColor = .white
    ) -> NSBitmapImageRep {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: representation)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        colour.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }

    /// A canvas with `count` separate dark bars — stand-ins for glyphs.
    private func bars(count: Int, merged: Bool) -> NSBitmapImageRep {
        let representation = flatCanvas()
        let context = NSGraphicsContext(bitmapImageRep: representation)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.black.setFill()

        for index in 0..<count {
            // Merged bars are laid down touching, which is what a glyph collision looks
            // like to a column scan: no blank column anywhere between them.
            let x = merged ? 20 + index * 20 : 20 + index * 40
            NSBezierPath(rect: CGRect(x: x, y: 30, width: 20, height: 60)).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
        return representation
    }

    private var fullBand: CGRect { CGRect(x: 0, y: 0, width: 200, height: 120) }

    // MARK: 빈 캔버스

    @Test("빈 캔버스를 심으면 색 수 검사가 잡는다")
    func aBlankCanvasIsCaught() {
        // 게이트의 판정선은 "구별되는 색 > 3". 단색 캔버스는 그 아래여야 한다.
        #expect(PixelAssertions.distinctColourCount(flatCanvas()) <= 3)
    }

    @Test("실제로 그려진 화면은 그 검사를 통과한다")
    func adrawnCanvasPassesTheSameCheck() {
        // 반대 방향도 확인한다 — 무엇이든 빈 캔버스라고 하는 검사라면 쓸모가 없다.
        #expect(PixelAssertions.distinctColourCount(bars(count: 3, merged: false)) > 1)
    }

    // MARK: 틀린 토큰 색

    @Test("틀린 토큰 색을 심으면 색 대조가 잡는다")
    func aWrongTokenColourIsCaught() {
        // bg-sidebar 대신 흰색을 칠한 화면. 두 색은 눈에 거의 같지만(#F2F2F4 vs #FFFFFF)
        // 허용오차보다는 크게 다르다 — 토큰을 손으로 바꿔 쓰면 정확히 이렇게 어긋난다.
        let white = flatCanvas(colour: .white)
        #expect(
            !PixelAssertions.matches(white, atX: 100, y: 60, token: DesignTokens.backgroundSidebar.light),
            "흰색을 bg-sidebar 로 인정했다 — 허용오차가 너무 넓다"
        )
    }

    @Test("올바른 토큰 색은 통과한다")
    func theRightTokenColourPasses() {
        let token = DesignTokens.backgroundSidebar.light
        let painted = flatCanvas(colour: NSColor(
            srgbRed: token.red, green: token.green, blue: token.blue, alpha: 1
        ))
        #expect(PixelAssertions.matches(painted, atX: 100, y: 60, token: token))
    }

    // MARK: 겹친 글리프

    @Test("붙여 놓은 막대를 심으면 덩어리 세기가 하나로 읽는다")
    func mergedMarksAreCountedAsOne() {
        // 글리프 충돌의 모형. 세 덩어리가 서로 닿으면 열 주사로는 하나다.
        #expect(PixelAssertions.inkRunCount(bars(count: 3, merged: true), band: fullBand) == 1)
    }

    @Test("떨어뜨려 놓은 막대는 제 수대로 세어진다")
    func separateMarksAreCountedIndividually() {
        // 이쪽이 더 중요하다 — 검사기가 **무엇이든 하나로 읽는다면** 위 테스트는
        // 통과하면서 아무것도 증명하지 못한다.
        #expect(PixelAssertions.inkRunCount(bars(count: 3, merged: false), band: fullBand) == 3)
        #expect(PixelAssertions.inkRunCount(bars(count: 2, merged: false), band: fullBand) == 2)
    }

    // MARK: 잉크 없음 (한글 미렌더의 모형)

    @Test("아무것도 안 그린 영역은 잉크 0으로 읽힌다")
    func anEmptyRegionHasNoInk() {
        // 오늘의 한글 결함이 이 모양이었다 — 글리프가 없어 전부 스킵되니 잉크가 없다.
        #expect(PixelAssertions.inkPixelCount(flatCanvas(), band: fullBand) == 0)
    }

    @Test("그린 영역은 잉크가 잡힌다")
    func adrawnRegionHasInk() {
        #expect(PixelAssertions.inkPixelCount(bars(count: 3, merged: false), band: fullBand) > 0)
    }
}
