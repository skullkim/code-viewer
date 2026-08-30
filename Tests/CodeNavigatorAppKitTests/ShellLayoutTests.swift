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
        // status bar at 820x620. The tab bar (ADR-0108) adds a third fixed row, so the
        // budget grew — the rule it defends did not.
        let layout = ShellLayout.resolve(windowSize: CGSize(width: 820, height: 620))
        #expect(layout.statusBarHeight == 26)
        #expect(layout.titleBarHeight == 48)
        #expect(layout.tabBarHeight == 32)
        #expect(layout.contentHeight == CGFloat(620 - 48 - 32 - 26))
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

/// The splitters the user drags, and what survives a restart (REQ-011 AC-3).
@Suite("ShellLayout — 분할 비율 복원 (REQ-011 AC-3)")
struct ShellLayoutSplitterTests {

    private func layout(width: CGFloat, tree: CGFloat? = nil, panel: CGFloat? = nil) -> ShellLayout {
        ShellLayout.resolve(
            windowSize: CGSize(width: width, height: 900),
            preferredTreeWidth: tree,
            preferredPanelWidth: panel
        )
    }

    @Test("복원된 분할 비율이 그대로 쓰인다")
    func restoredWidthsAreUsed() {
        let resolved = layout(width: 1600, tree: 320, panel: 420)
        #expect(resolved.treeWidth == CGFloat(320))
        #expect(resolved.panelWidth == CGFloat(420))
        #expect(resolved.editorWidth == CGFloat(1600 - 320 - 420))
    }

    @Test("주지 않으면 설계 기본값이다 — 기존 동작이 바뀌지 않는다")
    func theDefaultsAreUnchanged() {
        let resolved = layout(width: 1600)
        #expect(resolved.treeWidth == ShellLayout.Metrics.treeDefaultWidth)
        #expect(resolved.panelWidth == ShellLayout.Metrics.panelDefaultWidth)
    }

    @Test("드래그는 설계가 정한 한계 안에서만 움직인다")
    func draggingIsClamped() {
        #expect(ShellLayout.clampTreeWidth(20) == ShellLayout.Metrics.treeMinimumWidth)
        #expect(ShellLayout.clampTreeWidth(9_000) == ShellLayout.Metrics.treeMaximumWidth)
        #expect(ShellLayout.clampPanelWidth(20) == ShellLayout.Metrics.panelMinimumWidth)
        #expect(ShellLayout.clampPanelWidth(9_000) == ShellLayout.Metrics.panelMaximumWidth)
        #expect(ShellLayout.clampTreeWidth(300) == CGFloat(300))
    }

    @Test("한계를 넘는 저장 폭은 넓은 창에서도 한계까지만 쓰인다")
    func anOversizedStoredWidthIsCappedEvenWhenThereIsRoom() {
        // 3000px leaves the editor 1200px even at both maximums, so the shortfall rule
        // never engages. Anything but the cap surviving here means the cap is not applied.
        let resolved = layout(width: 3000, tree: 900, panel: 900)
        #expect(resolved.treeWidth == ShellLayout.Metrics.treeMaximumWidth)
        #expect(resolved.panelWidth == ShellLayout.Metrics.panelMaximumWidth)
        #expect(resolved.editorWidth == CGFloat(3000) - ShellLayout.Metrics.treeMaximumWidth - ShellLayout.Metrics.panelMaximumWidth)
    }

    @Test("한계에 못 미치는 저장 폭도 넓은 창에서 최소값까지 올라온다")
    func anUndersizedStoredWidthIsRaisedEvenWhenThereIsRoom() {
        let resolved = layout(width: 3000, tree: 40, panel: 40)
        #expect(resolved.treeWidth == ShellLayout.Metrics.treeMinimumWidth)
        #expect(resolved.panelWidth == ShellLayout.Metrics.panelMinimumWidth)
    }

    @Test("넓은 모니터에서 저장된 폭이 좁은 창의 에디터를 밀어내지 못한다")
    func aStoredWidthCannotSqueezeTheEditorOut() {
        // 480 + 600 leaves 20px in a 1100px window; the editor's floor outranks both.
        let resolved = layout(width: 1100, tree: 480, panel: 600)
        #expect(resolved.editorWidth >= ShellLayout.Metrics.editorMinimumWidth)
        #expect(resolved.treeWidth >= ShellLayout.Metrics.treeMinimumWidth)
        #expect(resolved.panelWidth >= ShellLayout.Metrics.panelMinimumWidth)
        #expect(resolved.statusBarHeight == ShellLayout.Metrics.statusBarHeight)
    }

    @Test("오버레이가 되면 드래그한 폭이 아니라 오버레이 폭을 쓴다")
    func anOverlayHasItsOwnWidth() {
        let narrow = layout(width: 860, tree: 400, panel: 500)
        #expect(narrow.panelPlacement == .overlay)
        #expect(narrow.panelWidth == ShellLayout.Metrics.panelOverlayWidth)
        // The tree is still a column at this width, so its dragged width still applies.
        #expect(narrow.treePlacement == .column)
        #expect(narrow.treeWidth == CGFloat(400))
    }
}

/// Widths the user dragged to (REQ-011 AC-3, design §3 W-1 "비율은 재시작 시 복원").
@Suite("ShellLayout — 사용자가 조절한 폭 (REQ-011 AC-3)")
struct ShellLayoutPreferredWidthTests {

    @Test("드래그한 폭이 반영된다")
    func draggedWidthsAreHonoured() {
        let layout = ShellLayout.resolve(
            windowSize: CGSize(width: 1600, height: 1000),
            preferredTreeWidth: 320,
            preferredPanelWidth: 420
        )
        #expect(layout.treeWidth == 320)
        #expect(layout.panelWidth == 420)
        #expect(layout.editorWidth == CGFloat(1600 - 320 - 420))
    }

    @Test("각 영역의 최소 폭이 드래그보다 우선한다")
    func eachAreasMinimumOutranksTheDrag() {
        let layout = ShellLayout.resolve(
            windowSize: CGSize(width: 1600, height: 1000),
            preferredTreeWidth: 40,
            preferredPanelWidth: 10
        )
        #expect(layout.treeWidth == 180)
        #expect(layout.panelWidth == 280)
    }

    @Test("에디터 최소 폭이 드래그보다 우선한다")
    func theEditorsMinimumOutranksTheDrag() {
        // Dragging the tree wide enough to squeeze the editor below 420 must not work;
        // the editor is the reason the window exists.
        let layout = ShellLayout.resolve(
            windowSize: CGSize(width: 1000, height: 700),
            preferredTreeWidth: 500,
            preferredPanelWidth: 400
        )
        #expect(layout.editorWidth >= 420)
        #expect(layout.treeWidth + layout.editorWidth + layout.panelWidth == 1000)
    }

    @Test("오버레이가 된 영역은 드래그한 폭이 아니라 고정 폭을 쓴다")
    func overlaysKeepTheirOwnWidth() {
        // A dragged width belongs to the column the user dragged. The float has its own
        // size from §4.4 and borrowing the column's would make it cover the editor.
        let layout = ShellLayout.resolve(
            windowSize: CGSize(width: 820, height: 620),
            preferredTreeWidth: 300,
            preferredPanelWidth: 500
        )
        #expect(layout.panelPlacement == .overlay)
        #expect(layout.panelWidth == 320)
        #expect(layout.treeWidth == 300, "트리는 아직 열이므로 드래그한 폭을 쓴다")
    }

    @Test("폭을 주지 않으면 §4.3 기본값 그대로다")
    func omittingThePreferencesKeepsTheDefaults() {
        let withoutPreferences = ShellLayout.resolve(windowSize: CGSize(width: 1600, height: 1000))
        #expect(withoutPreferences.treeWidth == 240)
        #expect(withoutPreferences.panelWidth == 340)
    }
}

/// The tab bar as a fixed chrome row (ADR-0108, design 02b §5.3).
///
/// The rule it defends is the one ADR-0104 exists for: the editor once grew vertically and
/// pushed the status bar off screen. A new fixed row makes that easier to repeat, so the
/// height budget is a value with a test rather than a number typed into three view bodies.
@Suite("셸 레이아웃 — 탭 바 행 (REQ-012 AC-1, ADR-0108)")
struct ShellLayoutTabBarTests {

    @Test("탭 바는 고정 높이 32이고 탭 수와 무관하다")
    func theTabBarIsAFixedHeightRow() {
        // Leader ruling 02b §12-1: the tab bar shows even with one tab, so the chrome
        // budget carries no branch on tab count.
        #expect(ShellLayout.Metrics.tabBarHeight == CGFloat(32))
    }

    @Test("고정 크롬 합계가 106이고 콘텐츠가 잔여를 갖는다")
    func fixedChromeIsSubtractedBeforeTheContent() {
        let layout = ShellLayout.resolve(windowSize: CGSize(width: 1280, height: 800))
        let chrome = layout.titleBarHeight + layout.tabBarHeight + layout.statusBarHeight
        #expect(chrome == CGFloat(106))
        #expect(layout.contentHeight == CGFloat(800 - 106))
    }

    @Test("최소 창 480 에서도 콘텐츠 374 가 남고 상태바가 밀려나지 않는다")
    func theStatusBarSurvivesTheSmallestWindow() {
        // The measured failure this whole rule exists for. 02b §5.3 states 374 explicitly.
        let layout = ShellLayout.resolve(windowSize: CGSize(width: 720, height: 480))
        #expect(layout.contentHeight == CGFloat(374))
        #expect(layout.statusBarHeight == CGFloat(26), "상태바 높이가 0으로 접히면 밀려난 것과 같다")
        #expect(layout.tabBarHeight == CGFloat(32))
    }

    @Test("창이 크롬보다 작아도 콘텐츠 높이가 음수가 되지 않는다")
    func theContentHeightNeverGoesNegative() {
        // The window minimum forbids this, but a negative height propagates into frame
        // maths as a crash rather than a small window.
        let layout = ShellLayout.resolve(windowSize: CGSize(width: 720, height: 40))
        #expect(layout.contentHeight == CGFloat(0))
    }
}
