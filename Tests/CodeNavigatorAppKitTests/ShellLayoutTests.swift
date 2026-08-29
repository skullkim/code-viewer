import Testing
import CoreGraphics
@testable import CodeNavigatorAppKit

// Swift Testing caveat, measured on Swift 6.3.3: `#expect(someCGFloat == 820 - 240)` fails
// even when the values are bit-identical, because the macro captures the integer-literal
// arithmetic separately from the CGFloat. Plain Swift compares the same two values as
// equal. It is a false red, never a false green — a genuinely wrong expectation still
// fails — but it wastes time and tempts people to "fix" correct code. Wrap expected
// values in CGFloat(...) or write them as decimal literals.

/// Design §4.3 fixes the chrome heights and §4.4 the window-width behaviour.
/// The status bar is the only permanent surface for the input mode (REQ-010 AC-3) and the
/// index state (REQ-009), so the cases that keep it alive in a cramped window are the
/// point of this suite, not an afterthought.
@Suite("ShellLayout — 창 크기에 따른 셸 치수 (REQ-011 AC-3, 02 §4.4)")
struct ShellLayoutTests {

    // MARK: Fixed chrome

    @Test("상태바는 어떤 창 크기에서도 26pt를 유지한다")
    func statusBarKeepsItsHeight() {
        let sizes: [CGSize] = [
            CGSize(width: 1600, height: 1000),
            CGSize(width: 1280, height: 800),
            CGSize(width: 1000, height: 700),
            CGSize(width: 820, height: 620),
            CGSize(width: 720, height: 480),
        ]
        for size in sizes {
            let layout = ShellLayout.resolve(windowSize: size)
            #expect(layout.statusBarHeight == 26, "창 \(size)에서 상태바가 26pt가 아니다")
        }
    }

    @Test("좁은 창에서도 에디터가 상태바를 밀어내지 않는다")
    func editorNeverEatsTheStatusBar() {
        // The prototype failed exactly here: the editor grew vertically and covered the
        // status bar at 820x620.
        let layout = ShellLayout.resolve(windowSize: CGSize(width: 820, height: 620))
        #expect(layout.statusBarHeight == 26)
        #expect(layout.titleBarHeight == 48)
        #expect(layout.contentHeight == CGFloat(620 - 48 - 26))
        #expect(layout.contentHeight > 0)
    }

    @Test("창이 크롬 높이보다 작아도 콘텐츠 높이가 음수가 되지 않는다")
    func contentHeightNeverGoesNegative() {
        let layout = ShellLayout.resolve(windowSize: CGSize(width: 720, height: 60))
        #expect(layout.contentHeight >= 0)
        #expect(layout.statusBarHeight == 26)
    }

    // MARK: Three-column widths

    @Test("큰 창에서는 트리·패널이 기본 폭을 갖고 에디터가 잔여를 갖는다")
    func largeWindowUsesDefaultWidths() {
        let layout = ShellLayout.resolve(windowSize: CGSize(width: 1600, height: 1000))
        #expect(layout.treeWidth == 240)
        #expect(layout.panelWidth == 340)
        #expect(layout.editorWidth == CGFloat(1600 - 240 - 340))
        #expect(layout.treePlacement == .column)
        #expect(layout.panelPlacement == .column)
    }

    @Test("작은 창 1000pt에서 에디터가 정확히 최소치 420pt가 된다")
    func smallWindowPinsEditorToItsMinimum() {
        // The designer measured this exact case in the prototype: 240 + 420 + 340 = 1000.
        let layout = ShellLayout.resolve(windowSize: CGSize(width: 1000, height: 700))
        #expect(layout.treeWidth == 240)
        #expect(layout.panelWidth == 340)
        #expect(layout.editorWidth == 420)
    }

    @Test("900~1000pt 사이에서는 패널을 먼저, 그다음 트리를 최소치까지 줄인다")
    func columnsShrinkTowardsTheirMinimumsBeforeTheEditorDoes() {
        let layout = ShellLayout.resolve(windowSize: CGSize(width: 900, height: 700))
        #expect(layout.panelPlacement == .column, "900pt는 3영역 동시 표시 구간이다")
        #expect(layout.treeWidth >= 180)
        #expect(layout.panelWidth >= 280)
        #expect(layout.editorWidth >= 420, "에디터 최소 폭이 다른 두 영역보다 우선한다")
        #expect(layout.treeWidth + layout.editorWidth + layout.panelWidth == 900)
    }

    @Test("패널을 줄이는 것이 트리를 줄이는 것보다 앞선다")
    func panelShrinksBeforeTheTree() {
        // At 960 only 40pt has to be found; it must come out of the panel alone.
        let layout = ShellLayout.resolve(windowSize: CGSize(width: 960, height: 700))
        #expect(layout.treeWidth == 240, "트리는 아직 줄지 않아야 한다")
        #expect(layout.panelWidth == 300)
        #expect(layout.editorWidth == 420)
    }

    // MARK: Overlay transitions

    @Test("900pt 미만에서 패널이 에디터 위 오버레이로 전환되고 트리는 남는다")
    func panelBecomesAnOverlayBelowNineHundred() {
        let layout = ShellLayout.resolve(windowSize: CGSize(width: 820, height: 620))
        #expect(layout.panelPlacement == .overlay)
        #expect(layout.panelWidth == 320)
        #expect(layout.treePlacement == .column)
        #expect(layout.treeWidth == 240)
        #expect(layout.editorWidth == CGFloat(820 - 240), "오버레이는 에디터 폭을 빼앗지 않는다")
    }

    @Test("720pt 미만에서는 트리도 오버레이가 된다")
    func treeBecomesAnOverlayBelowSevenTwenty() {
        let layout = ShellLayout.resolve(windowSize: CGSize(width: 640, height: 480))
        #expect(layout.treePlacement == .overlay)
        #expect(layout.treeWidth == 220)
        #expect(layout.panelPlacement == .overlay)
        #expect(layout.editorWidth == 640, "두 오버레이 아래에서 에디터가 전 폭을 갖는다")
    }

    // MARK: Progressive disclosure in the chrome

    @Test("1100pt 미만에서 툴바 단축키 라벨이 숨는다")
    func toolbarShortcutLabelsHideBelowElevenHundred() {
        #expect(ShellLayout.resolve(windowSize: CGSize(width: 1280, height: 800)).showsToolbarShortcutLabels)
        #expect(!ShellLayout.resolve(windowSize: CGSize(width: 1000, height: 700)).showsToolbarShortcutLabels)
    }

    @Test("720pt 미만에서 툴바 버튼이 아이콘만 남는다")
    func toolbarButtonsBecomeIconOnlyBelowSevenTwenty() {
        #expect(ShellLayout.resolve(windowSize: CGSize(width: 820, height: 620)).showsToolbarButtonTitles)
        #expect(!ShellLayout.resolve(windowSize: CGSize(width: 640, height: 480)).showsToolbarButtonTitles)
    }

    @Test("900pt 미만에서 상태바 힌트가 숨는다")
    func statusBarHintsHideBelowNineHundred() {
        #expect(ShellLayout.resolve(windowSize: CGSize(width: 1000, height: 700)).showsStatusBarHint)
        #expect(!ShellLayout.resolve(windowSize: CGSize(width: 820, height: 620)).showsStatusBarHint)
    }

    @Test("720pt 미만에서 언어·커서 위치가 숨지만 모드와 인덱스 칩은 절대 숨지 않는다")
    func statusBarKeepsModeAndIndexChipAtEveryWidth() {
        for width in [1600.0, 1280, 1000, 900, 820, 720, 640, 480] {
            let layout = ShellLayout.resolve(windowSize: CGSize(width: width, height: 600))
            #expect(layout.showsInputModeSegment, "폭 \(width)에서 모드 세그먼트가 숨었다")
            #expect(layout.showsIndexChip, "폭 \(width)에서 인덱스 칩이 숨었다")
        }
        #expect(ShellLayout.resolve(windowSize: CGSize(width: 820, height: 620)).showsCursorPosition)
        #expect(!ShellLayout.resolve(windowSize: CGSize(width: 640, height: 480)).showsCursorPosition)
    }
}
