import Testing
import CoreGraphics
@testable import CodeNavigatorAppKit

/// REQ-011 AC-3 and design §3 W-1's draggable splitters.
///
/// The test that matters most is the round trip. A drag clamp that disagrees with the
/// layout is not a cosmetic mismatch: the divider stops tracking the pointer, and the width
/// that gets persisted is one that never rendered, so the next launch restores a split the
/// user never chose. Every other case here is a corner of that one rule.
@Suite("ShellSplitDrag — 드래그 폭 클램프 (REQ-011 AC-3)")
struct ShellSplitDragTests {

    private let treeMinimum = ShellLayout.Metrics.treeMinimumWidth
    private let treeMaximum = ShellLayout.Metrics.treeMaximumWidth
    private let panelMinimum = ShellLayout.Metrics.panelMinimumWidth
    private let panelDefault = ShellLayout.Metrics.panelDefaultWidth
    private let editorMinimum = ShellLayout.Metrics.editorMinimumWidth

    private func draggedTreeWidth(
        to proposed: CGFloat,
        windowWidth: CGFloat,
        panelWidth: CGFloat? = nil,
        panelPlacement: ShellAreaPlacement = .column
    ) -> CGFloat {
        ShellSplitDrag.treeWidth(
            draggedTo: proposed,
            windowWidth: windowWidth,
            panelWidth: panelWidth ?? panelDefault,
            panelPlacement: panelPlacement
        )
    }

    // MARK: 트리

    @Test("넓은 창에서는 디자인 최대까지 끌 수 있다")
    func aWideWindowAllowsTheDesignMaximum() {
        // 1600 - 340(패널) - 420(에디터 최소) = 840 여유 → 디자인 최대 480이 먼저 걸린다.
        #expect(draggedTreeWidth(to: 600, windowWidth: 1600) == treeMaximum)
    }

    @Test("좁은 창에서는 에디터 최소를 지키는 지점에서 멈춘다")
    func aNarrowWindowStopsAtTheEditorsMinimum() {
        // 1000 - 340 - 420 = 240. 디자인 최대(480)가 아니라 창이 한계다.
        #expect(draggedTreeWidth(to: 400, windowWidth: 1000) == CGFloat(240))
    }

    @Test("최소 폭 아래로는 내려가지 않는다")
    func theTreeNeverGoesUnderItsMinimum() {
        #expect(draggedTreeWidth(to: 40, windowWidth: 1600) == treeMinimum)
        #expect(draggedTreeWidth(to: -200, windowWidth: 1600) == treeMinimum)
    }

    @Test("패널이 오버레이면 그만큼 더 끌 수 있다")
    func anOverlayPanelFreesTheSpaceItAppearsToOccupy() {
        // 오버레이는 에디터 위에 뜨므로 폭을 잡아먹지 않는다. 같은 창인데 여유가 다르다.
        let asColumn = draggedTreeWidth(to: 600, windowWidth: 1000, panelPlacement: .column)
        let asOverlay = draggedTreeWidth(to: 600, windowWidth: 1000, panelPlacement: .overlay)

        #expect(asColumn == CGFloat(240))
        #expect(asOverlay == CGFloat(580).clampedToTreeMaximum)
        #expect(asOverlay > asColumn)
    }

    @Test("창이 최소조차 담지 못해도 최소 밑으로 내려가지 않는다")
    func animpossiblyNarrowWindowStillReturnsTheMinimum() {
        // 720 - 340 - 420 = -40. 음수 여유를 그대로 쓰면 폭이 음수가 된다.
        // 이 경우는 레이아웃의 축소 규칙이 처리한다 — 여기서 답을 두 개로 만들지 않는다.
        #expect(draggedTreeWidth(to: 300, windowWidth: 720) == treeMinimum)
    }

    // MARK: 패널 (대칭)

    @Test("패널도 에디터 최소를 지키는 지점에서 멈춘다")
    func thePanelStopsAtTheEditorsMinimumToo() {
        // 1000 - 240(트리) - 420 = 340.
        let width = ShellSplitDrag.panelWidth(
            draggedTo: 600,
            windowWidth: 1000,
            treeWidth: 240,
            treePlacement: .column
        )
        #expect(width == CGFloat(340))
    }

    @Test("패널도 최소 폭 아래로는 내려가지 않는다")
    func thePanelNeverGoesUnderItsMinimum() {
        let width = ShellSplitDrag.panelWidth(
            draggedTo: 10,
            windowWidth: 1600,
            treeWidth: 240,
            treePlacement: .column
        )
        #expect(width == panelMinimum)
    }

    // MARK: 왕복 불변식 — 끌어낸 폭이 그대로 그려진다

    @Test("끌어낸 트리 폭은 레이아웃이 그대로 되돌려준다")
    func aDraggedTreeWidthSurvivesTheLayout() {
        // 이것이 "구분선이 포인터를 따라온다"의 기계적 표현이다. 여기가 깨지면
        // 사용자는 끌었는데 화면이 덜 따라오는 것을 본다.
        let windowWidths: [CGFloat] = [1600, 1280, 1000, 940, 900]
        let proposals: [CGFloat] = [100, 180, 240, 320, 400, 600]

        for windowWidth in windowWidths {
            let layout = ShellLayout.resolve(windowSize: CGSize(width: windowWidth, height: 800))
            for proposal in proposals {
                let dragged = ShellSplitDrag.treeWidth(
                    draggedTo: proposal,
                    windowWidth: windowWidth,
                    panelWidth: layout.panelWidth,
                    panelPlacement: layout.panelPlacement
                )
                let resolved = ShellLayout.resolve(
                    windowSize: CGSize(width: windowWidth, height: 800),
                    preferredTreeWidth: dragged,
                    preferredPanelWidth: layout.panelWidth
                )
                #expect(resolved.treeWidth == dragged, "창 \(windowWidth) · 제안 \(proposal)")
            }
        }
    }

    @Test("끌어낸 패널 폭도 레이아웃이 그대로 되돌려준다")
    func aDraggedPanelWidthSurvivesTheLayout() {
        let windowWidths: [CGFloat] = [1600, 1280, 1000, 940, 900]
        let proposals: [CGFloat] = [200, 280, 340, 460, 700]

        for windowWidth in windowWidths {
            let layout = ShellLayout.resolve(windowSize: CGSize(width: windowWidth, height: 800))
            for proposal in proposals {
                let dragged = ShellSplitDrag.panelWidth(
                    draggedTo: proposal,
                    windowWidth: windowWidth,
                    treeWidth: layout.treeWidth,
                    treePlacement: layout.treePlacement
                )
                let resolved = ShellLayout.resolve(
                    windowSize: CGSize(width: windowWidth, height: 800),
                    preferredTreeWidth: layout.treeWidth,
                    preferredPanelWidth: dragged
                )
                #expect(resolved.panelWidth == dragged, "창 \(windowWidth) · 제안 \(proposal)")
            }
        }
    }

    @Test("끌어낸 폭에서도 에디터는 최소 폭을 지킨다")
    func theEditorKeepsItsMinimumUnderEveryDrag() {
        let windowWidths: [CGFloat] = [1600, 1280, 1000, 940, 900]

        for windowWidth in windowWidths {
            let layout = ShellLayout.resolve(windowSize: CGSize(width: windowWidth, height: 800))
            let dragged = ShellSplitDrag.treeWidth(
                draggedTo: 9_999,
                windowWidth: windowWidth,
                panelWidth: layout.panelWidth,
                panelPlacement: layout.panelPlacement
            )
            let resolved = ShellLayout.resolve(
                windowSize: CGSize(width: windowWidth, height: 800),
                preferredTreeWidth: dragged,
                preferredPanelWidth: layout.panelWidth
            )
            #expect(resolved.editorWidth >= editorMinimum, "창 \(windowWidth)")
        }
    }
}

private extension CGFloat {
    /// 오버레이 케이스의 기대값이 디자인 최대에 걸리는지를 읽기 쉽게 적기 위한 보조.
    var clampedToTreeMaximum: CGFloat {
        Swift.min(self, ShellLayout.Metrics.treeMaximumWidth)
    }
}
