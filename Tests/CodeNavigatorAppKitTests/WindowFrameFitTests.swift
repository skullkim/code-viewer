import Testing
import CoreGraphics
@testable import CodeNavigatorAppKit

/// REQ-011 AC-3's riskiest half. Restoring a window is easy; restoring it somewhere the
/// user can see is the part that fails silently — a frame saved on a monitor that is no
/// longer attached names empty space, and the app then looks like it did not launch at all.
///
/// Frames are AppKit's: origin bottom-left, y growing upward, so the window's top is `maxY`.
@Suite("WindowFrameFit — 복원된 창을 보이는 화면으로 (REQ-011 AC-3)")
struct WindowFrameFitTests {

    /// A 1920x1080 main screen with the menu bar removed, at the origin.
    private let mainScreen = CGRect(x: 0, y: 0, width: 1920, height: 1055)
    /// A second display sitting to the right.
    private let secondScreen = CGRect(x: 1920, y: 0, width: 1440, height: 875)

    private let minimum = WindowFrameFit.minimumSize

    private func fit(_ frame: CGRect, screens: [CGRect]? = nil) -> CGRect {
        WindowFrameFit.fit(frame, intoVisibleFrames: screens ?? [mainScreen])
    }

    // MARK: 그대로 두어야 하는 경우

    @Test("화면 안에 있는 프레임은 건드리지 않는다")
    func aFrameFullyOnScreenIsLeftAlone() {
        let frame = CGRect(x: 200, y: 150, width: 1280, height: 800)
        #expect(fit(frame) == frame)
    }

    @Test("가장자리에 걸친 창은 사용자가 그렇게 둔 것이므로 유지한다")
    func aDeliberatelyOverhangingFrameIsKept() {
        // 사람들은 창을 일부러 화면 밖으로 걸쳐 둔다. 잡을 수 있는 만큼 보이면 그대로 둔다.
        let frame = CGRect(x: 1600, y: 100, width: 1280, height: 800)
        #expect(fit(frame) == frame)
    }

    // MARK: 돌아와야 하는 경우

    @Test("사라진 모니터의 좌표는 주 화면 중앙으로 돌아온다")
    func aFrameOnADetachedMonitorComesBack() {
        // 외장 모니터(x=1920~)에 있던 창인데 지금은 주 화면만 있다.
        let frame = CGRect(x: 2400, y: 200, width: 1280, height: 800)
        let fitted = fit(frame)

        #expect(mainScreen.contains(fitted))
        #expect(fitted.midX == mainScreen.midX)
        #expect(fitted.midY == mainScreen.midY)
    }

    @Test("두 화면이 있으면 사라지지 않은 쪽에 그대로 남는다")
    func aFrameOnASecondScreenStaysThere() {
        // 두 번째 화면은 높이가 875뿐이라 y=100·높이 800이면 위로 넘친다. 넘치지 않는
        // 프레임을 써야 "화면이 남아 있으면 그대로 둔다"만 검증된다.
        let frame = CGRect(x: 2000, y: 40, width: 1280, height: 800)
        #expect(fit(frame, screens: [mainScreen, secondScreen]) == frame)
    }

    @Test("타이틀바가 화면 위로 넘어가면 내려온다")
    func aTitleBarPushedAboveTheScreenComesDown() {
        // macOS는 메뉴바 위로 올라간 창을 사용자가 끌어내릴 수 없다. 잡을 수 없는 창은
        // 없는 창과 같다.
        let frame = CGRect(x: 200, y: 900, width: 1280, height: 800)
        let fitted = fit(frame)

        #expect(fitted.maxY <= mainScreen.maxY)
        #expect(fitted.width == frame.width)
        #expect(fitted.height == frame.height)
    }

    @Test("거의 다 나간 창은 잡을 수 있는 만큼 돌아온다")
    func aNearlyOffscreenFrameIsPulledBack() {
        let frame = CGRect(x: 1900, y: 100, width: 1280, height: 800)
        let fitted = fit(frame)

        let visible = mainScreen.intersection(fitted)
        #expect(!visible.isNull)
        #expect(visible.width >= WindowFrameFit.minimumVisibleSize.width)
    }

    // MARK: 크기

    @Test("최소 크기보다 작으면 키운다")
    func aTooSmallFrameGrowsToTheMinimum() {
        // §4.4의 최소 창 720x480.
        let fitted = fit(CGRect(x: 100, y: 100, width: 300, height: 200))

        #expect(fitted.width == minimum.width)
        #expect(fitted.height == minimum.height)
    }

    @Test("화면보다 큰 창은 화면에 맞춘다")
    func anOversizedFrameIsCappedToTheScreen() {
        let fitted = fit(CGRect(x: 0, y: 0, width: 5000, height: 4000))

        #expect(fitted.width <= mainScreen.width)
        #expect(fitted.height <= mainScreen.height)
    }

    @Test("화면이 최소 크기보다 작아도 최소 크기를 지킨다")
    func theDesignMinimumOutranksATinyScreen() {
        // 최소 밑으로 줄이면 §4.4가 깨진다. 그 경우는 윈도우 서버가 처리할 몫이다.
        let tiny = CGRect(x: 0, y: 0, width: 640, height: 400)
        let fitted = WindowFrameFit.fit(CGRect(x: 0, y: 0, width: 1280, height: 800), intoVisibleFrames: [tiny])

        #expect(fitted.width == minimum.width)
        #expect(fitted.height == minimum.height)
    }

    // MARK: 방어

    @Test("화면 목록이 비어도 무너지지 않는다")
    func noScreensAtAllStillReturnsAUsableSize() {
        let fitted = WindowFrameFit.fit(CGRect(x: 10, y: 20, width: 100, height: 100), intoVisibleFrames: [])

        #expect(fitted.width == minimum.width)
        #expect(fitted.height == minimum.height)
    }

    @Test("어떤 입력에도 최소 크기 이상이고 유한하다")
    func everyResultIsUsable() {
        let frames = [
            CGRect(x: -5000, y: -5000, width: 100, height: 100),
            CGRect(x: 9999, y: 9999, width: 4000, height: 3000),
            CGRect(x: 0, y: 0, width: 0, height: 0),
            CGRect(x: 300, y: 300, width: 1280, height: 800),
        ]

        for frame in frames {
            for screens in [[mainScreen], [mainScreen, secondScreen]] {
                let fitted = WindowFrameFit.fit(frame, intoVisibleFrames: screens)

                #expect(fitted.width >= minimum.width, "\(frame)")
                #expect(fitted.height >= minimum.height, "\(frame)")
                #expect(fitted.origin.x.isFinite && fitted.origin.y.isFinite, "\(frame)")
                // 결과는 언제나 어느 화면에서든 잡을 수 있어야 한다.
                let anyVisible = screens.contains { screen in
                    let overlap = screen.intersection(fitted)
                    return !overlap.isNull
                        && overlap.width >= WindowFrameFit.minimumVisibleSize.width
                        && overlap.height >= WindowFrameFit.minimumVisibleSize.height
                }
                #expect(anyVisible, "\(frame) — 어느 화면에서도 잡을 수 없다")
            }
        }
    }
}
