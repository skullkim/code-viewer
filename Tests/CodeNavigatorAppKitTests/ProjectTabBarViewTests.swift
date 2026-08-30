import Testing
import AppKit
import SwiftUI
import Foundation
@testable import CodeNavigatorAppKit

/// The tab bar as pixels (design 02b §3 W-11, REQ-012 AC-1).
///
/// The judgement is already covered by `ProjectTabBarTests`; what these check is that the
/// view honours it on screen. That distinction earned its place today: two real defects this
/// build shipped — Korean drawing as nothing, modifier glyphs colliding — passed every logic
/// test, because the values were right and the drawing was not.
@MainActor
@Suite("ProjectTabBarView — 탭 바가 실제로 그려지는가 (REQ-012 AC-1)")
struct ProjectTabBarViewTests {

    private func tab(
        _ name: String,
        path: String? = nil,
        dirty: Int = 0,
        index: IndexStateSnapshot = .ready
    ) -> ProjectTabDescriptor {
        let root = path ?? "/Users/dev/\(name)"
        return ProjectTabDescriptor(
            id: root, rootPath: root, name: name, dirtyBufferCount: dirty, indexState: index
        )
    }

    private func render(
        _ tabs: [ProjectTabDescriptor],
        active: String? = nil,
        width: CGFloat = 900,
        appearance: NSAppearance.Name = .aqua
    ) -> NSBitmapImageRep? {
        let bar = ProjectTabBarPresentation.make(
            tabs: tabs, activeTabID: active ?? tabs.first?.id, barWidth: width
        )
        let hosting = NSHostingView(rootView: ProjectTabBarView(bar: bar) { _ in })
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: ShellLayout.Metrics.tabBarHeight)
        hosting.appearance = NSAppearance(named: appearance)
        hosting.layoutSubtreeIfNeeded()
        return DesignRegressionGateTests.rasterise(hosting, scale: 2)
    }

    private var fullBand: CGRect {
        CGRect(x: 0, y: 0, width: 900 * 2, height: ShellLayout.Metrics.tabBarHeight * 2)
    }

    /// The strip inside the first tab where its label draws, in @2x pixels.
    ///
    /// Derived from the layout constants rather than written down, so a padding change
    /// moves the band with it instead of silently aiming at the wrong pixels.
    private static var labelBand: CGRect {
        let scale: CGFloat = 2
        let textStart = (10 as CGFloat) * scale          // horizontal padding
        let textWidth = (150 as CGFloat) * scale
        let barHeight = ShellLayout.Metrics.tabBarHeight * scale
        return CGRect(x: textStart, y: barHeight * 0.25, width: textWidth, height: barHeight * 0.5)
    }

    @Test("탭 바가 빈 캔버스가 아니다")
    func theBarActuallyDraws() {
        guard let rendered = render([tab("repo"), tab("other")]) else {
            Issue.record("래스터화 실패")
            return
        }
        let colours = PixelAssertions.distinctColourCount(rendered, step: 4)
        #expect(colours > 2, "구별되는 색이 \(colours)개뿐 — 레이아웃만 되고 아무것도 안 그려졌다")
    }

    @Test("탭 바 배경이 bg-window 토큰이다")
    func theBarCarriesItsToken() {
        // 시니어의 시각 회귀 게이트와 같은 기준. 토큰이 바뀌면 여기서 걸린다.
        guard let rendered = render([tab("repo")], width: 900) else {
            Issue.record("래스터화 실패")
            return
        }
        // 오른쪽 끝 빈 자리 — 탭도 컨트롤도 없는 순수 배경.
        #expect(
            PixelAssertions.matches(
                rendered, atX: rendered.pixelsWide - 120, y: rendered.pixelsHigh / 2,
                token: DesignTokens.backgroundWindow.light
            ),
            "탭 바 배경이 bg-window 가 아니다"
        )
    }

    @Test("다크 모드에서 다른 픽셀을 낸다 (REQ-011 AC-4)")
    func theBarFollowsTheAppearance() {
        guard let light = render([tab("repo"), tab("other")], appearance: .aqua),
              let dark = render([tab("repo"), tab("other")], appearance: .darkAqua)
        else {
            Issue.record("래스터화 실패")
            return
        }
        #expect(
            PixelAssertions.matches(
                dark, atX: dark.pixelsWide - 120, y: dark.pixelsHigh / 2,
                token: DesignTokens.backgroundWindow.dark
            ),
            "다크에서 bg-window 다크값이 아니다"
        )
        #expect(
            PixelAssertions.inkPixelCount(light, band: fullBand)
                != PixelAssertions.inkPixelCount(dark, band: fullBand),
            "라이트와 다크가 같은 픽셀을 냈다"
        )
    }

    @Test("탭이 하나여도 바가 그려진다")
    func oneTabStillDraws() {
        // §12 판정 1. 여기서 안 그리면 열린 프로젝트 이름이 화면 어디에도 없다.
        guard let rendered = render([tab("only")]) else {
            Issue.record("래스터화 실패")
            return
        }
        #expect(PixelAssertions.inkPixelCount(rendered, band: fullBand) > 0, "탭 하나짜리 바가 비어 있다")
    }

    @Test("활성 탭이 비활성 탭과 다르게 그려진다")
    func theActiveTabLooksDifferent() {
        // 채움·굵기·accent 라인 3중. 하나라도 살아 있으면 픽셀이 달라진다.
        let tabs = [tab("a"), tab("b")]
        guard let first = render(tabs, active: tabs[0].id),
              let second = render(tabs, active: tabs[1].id)
        else {
            Issue.record("래스터화 실패")
            return
        }

        let leftHalf = CGRect(x: 0, y: 0, width: 400, height: ShellLayout.Metrics.tabBarHeight * 2)
        #expect(
            PixelAssertions.inkPixelCount(first, band: leftHalf)
                != PixelAssertions.inkPixelCount(second, band: leftHalf),
            "어느 탭이 활성이든 같게 그려졌다"
        )
    }

    @Test("활성 탭 배경이 bg-content 로 채워진다")
    func theActiveTabIsFilledWithItsToken() {
        // 위 테스트("다르게 그려진다")는 굵기·글자색만 달라도 통과한다 — 실제로 채움과
        // accent 라인을 지우고 돌려 보니 그대로 초록이었다. **무엇이 다른지**를 따로
        // 박지 않으면 W-11 의 4중 표시 중 어느 것이 살아 있는지 알 수 없다.
        let tabs = [tab("a"), tab("b")]
        guard let rendered = render(tabs, active: tabs[0].id) else {
            Issue.record("래스터화 실패")
            return
        }
        // 첫 탭 안쪽, 글자가 없는 아래쪽.
        #expect(
            PixelAssertions.matches(
                rendered, atX: 40, y: Int(ShellLayout.Metrics.tabBarHeight * 2) - 6,
                token: DesignTokens.backgroundContent.light
            ),
            "활성 탭이 bg-content 로 채워지지 않았다"
        )
    }

    @Test("활성 탭 위에 accent 라인이 그려진다")
    func theActiveTabCarriesItsAccentLine() {
        let tabs = [tab("a"), tab("b")]
        guard let rendered = render(tabs, active: tabs[0].id) else {
            Issue.record("래스터화 실패")
            return
        }
        // 상단 2pt = @2x 4px 안에서 accent 를 찾는다.
        let topStrip = (0..<4).contains { y in
            PixelAssertions.matches(
                rendered, atX: 60, y: y, token: DesignTokens.accent.light, tolerance: 0.08
            )
        }
        #expect(topStrip, "활성 탭 상단 accent 라인이 없다")
    }

    @Test("더티 탭이 깨끗한 탭보다 잉크를 더 남긴다")
    func aDirtyTabDrawsItsDot() {
        // 배경 탭의 저장 안 된 변경은 다른 어디에도 안 보인다 — 점이 안 그려지면
        // 사용자는 알 길이 없다.
        let clean = [tab("a"), tab("b")]
        let dirty = [tab("a"), tab("b", dirty: 2)]

        guard let cleanShot = render(clean, active: clean[0].id),
              let dirtyShot = render(dirty, active: dirty[0].id)
        else {
            Issue.record("래스터화 실패")
            return
        }
        #expect(
            PixelAssertions.inkPixelCount(dirtyShot, band: fullBand)
                > PixelAssertions.inkPixelCount(cleanShot, band: fullBand),
            "더티 점이 그려지지 않았다"
        )
    }

    @Test("한글 프로젝트 이름이 실제로 그려진다")
    func koreanTabLabelsAreDrawn() {
        // 오늘 에디터에서 한글이 한 획도 안 그려진 채 모든 테스트가 초록이었다.
        // 탭 라벨도 같은 함정 위에 있다 — "어디에 있나"가 아니라 "있기는 한가"를 묻는다.
        //
        // 라벨이 놓이는 좁은 띠만 잰다. 바 전체를 재면 활성 탭의 흰 채움이 지배색을
        // 바꿔 버려서 글자 몇 백 픽셀이 3만 픽셀 안에 묻힌다 — 처음에 그렇게 썼다가
        // 한글이 정상인데도 실패했다.
        guard let korean = render([tab("한글프로젝트")]),
              let empty = render([tab("")])
        else {
            Issue.record("래스터화 실패")
            return
        }

        let koreanInk = PixelAssertions.inkPixelCount(korean, band: Self.labelBand)
        let emptyInk = PixelAssertions.inkPixelCount(empty, band: Self.labelBand)

        #expect(emptyInk < 200, "빈 라벨 자리에 잉크 \(emptyInk) — 기준이 무너졌다")
        #expect(koreanInk > emptyInk, "한글 탭 라벨이 한 획도 안 그려졌다 (한글 \(koreanInk) · 빈 \(emptyInk))")
    }

    @Test("영문 라벨과 비슷한 양의 잉크를 남긴다")
    func koreanDrawsAsMuchAsLatin() {
        // 일부 글자만 폴백에 걸리는 경우를 잡으려면 양을 비교해야 한다.
        guard let korean = render([tab("한글프로")]), let latin = render([tab("abcd")]) else {
            Issue.record("래스터화 실패")
            return
        }
        let koreanInk = PixelAssertions.inkPixelCount(korean, band: Self.labelBand)
        let latinInk = PixelAssertions.inkPixelCount(latin, band: Self.labelBand)

        #expect(latinInk > 0, "영문조차 안 그려졌다 — 기준 자체가 무너졌다")
        #expect(Double(koreanInk) > Double(latinInk) * 0.5, "한글 \(koreanInk) 가 영문 \(latinInk) 의 절반 미만")
    }

    @Test("고정 높이 32pt 를 넘지 않는다")
    func theBarKeepsItsFixedHeight() {
        // ADR-0108. 잔여 높이를 요구하면 에디터가 상태바를 밀어냈던 그 메커니즘이 된다.
        let bar = ProjectTabBarPresentation.make(
            tabs: (0..<6).map { tab("p\($0)") }, activeTabID: nil, barWidth: 900
        )
        let hosting = NSHostingView(rootView: ProjectTabBarView(bar: bar) { _ in })
        hosting.frame = CGRect(x: 0, y: 0, width: 900, height: ShellLayout.Metrics.tabBarHeight)
        hosting.layoutSubtreeIfNeeded()

        #expect(hosting.fittingSize.height <= ShellLayout.Metrics.tabBarHeight)
    }

    @Test("탭이 없으면 아무것도 그리지 않는다")
    func noTabsDrawsNothing() {
        let bar = ProjectTabBarPresentation.make(tabs: [], activeTabID: nil, barWidth: 900)
        let hosting = NSHostingView(rootView: ProjectTabBarView(bar: bar) { _ in })
        hosting.frame = CGRect(x: 0, y: 0, width: 900, height: ShellLayout.Metrics.tabBarHeight)
        hosting.layoutSubtreeIfNeeded()

        #expect(hosting.fittingSize.height == 0, "탭 0개인데 바가 자리를 차지했다")
    }
}
