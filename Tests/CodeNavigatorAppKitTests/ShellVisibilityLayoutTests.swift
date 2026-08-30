import Testing
import CoreGraphics
@testable import CodeNavigatorAppKit

/// REQ-011 AC-3's other half: ⌥⌘1 and ⌥⌘0 hide the side areas, and those choices survive a
/// restart (design §3 W-9, §4.4).
///
/// The case worth pinning is the one a naive implementation gets wrong: hiding one area has
/// to give the *other* one room back. A tree squeezed by the panel stays squeezed if the
/// hidden layout is derived from widths computed while the panel was still showing.
@Suite("ShellVisibilityLayout — 영역 표시/숨김 (REQ-011 AC-3)")
struct ShellVisibilityLayoutTests {

    private let editorMinimum = ShellLayout.Metrics.editorMinimumWidth
    private let treeMinimum = ShellLayout.Metrics.treeMinimumWidth

    private func resolve(
        windowWidth: CGFloat,
        tree: CGFloat? = nil,
        panel: CGFloat? = nil,
        isTreeVisible: Bool = true,
        isPanelVisible: Bool = true
    ) -> ShellVisibilityLayout {
        ShellVisibilityLayout.resolve(
            windowSize: CGSize(width: windowWidth, height: 800),
            preferredTreeWidth: tree,
            preferredPanelWidth: panel,
            isTreeVisible: isTreeVisible,
            isPanelVisible: isPanelVisible
        )
    }

    // MARK: 둘 다 보일 때는 기존 규칙 그대로

    @Test("둘 다 보이면 기존 레이아웃과 완전히 같다")
    func showingBothMatchesTheExistingLayout() {
        // 위임이 실제로 위임인지 확인한다. 여기가 어긋나면 창 하나에 답이 두 개가 된다.
        for windowWidth in [CGFloat(1600), 1280, 1000, 900, 820, 720] {
            let size = CGSize(width: windowWidth, height: 800)
            let expected = ShellLayout.resolve(windowSize: size, preferredTreeWidth: 300, preferredPanelWidth: 380)
            let actual = resolve(windowWidth: windowWidth, tree: 300, panel: 380)

            #expect(actual.layout == expected, "창 \(windowWidth)")
            #expect(actual.isTreeMounted)
            #expect(actual.isPanelMounted)
        }
    }

    // MARK: 숨김

    @Test("트리를 숨기면 폭이 0이고 에디터가 그만큼 넓어진다")
    func hidingTheTreeGivesItsWidthToTheEditor() {
        let shown = resolve(windowWidth: 1600)
        let hidden = resolve(windowWidth: 1600, isTreeVisible: false)

        #expect(hidden.layout.treeWidth == CGFloat(0))
        #expect(!hidden.isTreeMounted)
        #expect(hidden.layout.editorWidth == shown.layout.editorWidth + shown.layout.treeWidth)
    }

    @Test("패널을 숨기면 폭이 0이고 에디터가 그만큼 넓어진다")
    func hidingThePanelGivesItsWidthToTheEditor() {
        let shown = resolve(windowWidth: 1600)
        let hidden = resolve(windowWidth: 1600, isPanelVisible: false)

        #expect(hidden.layout.panelWidth == CGFloat(0))
        #expect(!hidden.isPanelMounted)
        #expect(hidden.layout.editorWidth == shown.layout.editorWidth + shown.layout.panelWidth)
    }

    @Test("둘 다 숨기면 에디터가 창을 전부 갖는다")
    func hidingBothLeavesOnlyTheEditor() {
        let layout = resolve(windowWidth: 1280, isTreeVisible: false, isPanelVisible: false)

        #expect(layout.layout.treeWidth == CGFloat(0))
        #expect(layout.layout.panelWidth == CGFloat(0))
        #expect(layout.layout.editorWidth == CGFloat(1280))
    }

    @Test("패널을 숨기면 눌려 있던 트리가 선호 폭을 되찾는다")
    func hidingThePanelLetsTheTreeGrowBackToWhatWasChosen() {
        // 1000pt 창에서 패널(340)과 에디터 최소(420) 때문에 트리 400은 300으로 눌린다.
        // 패널이 사라지면 그 제약도 사라지므로 400이 그대로 그려져야 한다.
        // 눌린 폭을 그대로 물려받는 구현은 여기서 300을 내놓는다.
        let squeezed = resolve(windowWidth: 1000, tree: 400)
        #expect(squeezed.layout.treeWidth == CGFloat(300))

        let freed = resolve(windowWidth: 1000, tree: 400, isPanelVisible: false)
        #expect(freed.layout.treeWidth == CGFloat(400))
        #expect(freed.layout.editorWidth == CGFloat(600))
    }

    @Test("트리를 숨기면 눌려 있던 패널도 선호 폭을 되찾는다")
    func hidingTheTreeLetsThePanelGrowBack() {
        let freed = resolve(windowWidth: 1000, panel: 500, isTreeVisible: false)

        #expect(freed.layout.panelWidth == CGFloat(500))
        #expect(freed.layout.editorWidth == CGFloat(500))
    }

    // MARK: 에디터 최소는 어떤 조합에서도 지켜진다

    @Test("한쪽만 보여도 에디터 최소가 지켜진다")
    func theEditorKeepsItsMinimumWithOneAreaShowing() {
        // 900 창에 트리를 최대(480)로 끌면 에디터가 420에 못 미친다. 트리가 양보한다.
        let layout = resolve(windowWidth: 900, tree: 480, isPanelVisible: false)

        #expect(layout.layout.editorWidth >= editorMinimum)
        #expect(layout.layout.treeWidth == CGFloat(480) - (editorMinimum - (CGFloat(900) - CGFloat(480))))
    }

    @Test("양보해도 자기 최소 밑으로는 내려가지 않는다")
    func theSoleAreaNeverGoesUnderItsOwnMinimum() {
        // 창이 트리 최소 + 에디터 최소보다 좁으면 둘 다 만족시킬 수 없다. 그때도 트리는
        // 자기 최소를 지키고, 부족분은 에디터가 떠안는다 — 폭이 음수가 되지는 않는다.
        let layout = resolve(windowWidth: 560, tree: 300, isPanelVisible: false)

        #expect(layout.layout.treeWidth >= treeMinimum)
        #expect(layout.layout.editorWidth >= CGFloat(0))
    }

    @Test("모든 조합에서 폭이 음수가 되지 않는다")
    func noCombinationProducesNegativeWidths() {
        for windowWidth in [CGFloat(1600), 1280, 1000, 900, 820, 720, 640, 480] {
            for treeVisible in [true, false] {
                for panelVisible in [true, false] {
                    let layout = resolve(
                        windowWidth: windowWidth,
                        isTreeVisible: treeVisible,
                        isPanelVisible: panelVisible
                    ).layout

                    #expect(layout.treeWidth >= 0, "창 \(windowWidth) 트리 \(treeVisible) 패널 \(panelVisible)")
                    #expect(layout.panelWidth >= 0, "창 \(windowWidth) 트리 \(treeVisible) 패널 \(panelVisible)")
                    #expect(layout.editorWidth >= 0, "창 \(windowWidth) 트리 \(treeVisible) 패널 \(panelVisible)")
                }
            }
        }
    }

    // MARK: 오버레이

    @Test("오버레이인 영역을 숨겨도 에디터 폭은 그대로다")
    func hidingAnOverlayDoesNotChangeTheEditorsWidth() {
        // 오버레이는 에디터 위에 뜨므로 원래 폭을 먹지 않는다. 숨긴다고 넓어질 것이 없다.
        let windowWidth = CGFloat(820)   // <900 이라 패널이 오버레이
        let shown = resolve(windowWidth: windowWidth)
        let hidden = resolve(windowWidth: windowWidth, isPanelVisible: false)

        #expect(shown.layout.panelPlacement == .overlay)
        #expect(hidden.layout.editorWidth == shown.layout.editorWidth)
        #expect(hidden.layout.panelWidth == CGFloat(0))
    }

    // MARK: 절대 사라지지 않는 것

    @Test("어떤 조합에서도 모드 세그먼트와 인덱스 칩은 남는다")
    func theModeSegmentAndIndexChipSurviveEveryCombination() {
        // REQ-010 AC-3 · REQ-009. 영역을 다 숨겨도 이 둘은 상태바에 남아야 한다.
        for windowWidth in [CGFloat(1600), 900, 720, 480] {
            for treeVisible in [true, false] {
                for panelVisible in [true, false] {
                    let layout = resolve(
                        windowWidth: windowWidth,
                        isTreeVisible: treeVisible,
                        isPanelVisible: panelVisible
                    ).layout

                    #expect(layout.showsInputModeSegment, "창 \(windowWidth)")
                    #expect(layout.showsIndexChip, "창 \(windowWidth)")
                    #expect(layout.statusBarHeight > 0, "창 \(windowWidth)")
                }
            }
        }
    }

    // MARK: 드래그와의 정합

    @Test("한쪽을 숨긴 상태에서 끌어낸 폭도 그대로 그려진다")
    func aDraggedWidthSurvivesWhileTheOtherAreaIsHidden() {
        // ShellSplitDrag의 왕복 불변식이 숨김 상태에서도 성립해야 한다. 숨김 때문에
        // 여유가 늘었는데 클램프가 예전 여유로 자르면 구분선이 다시 뒤처진다.
        let windowWidth = CGFloat(1000)

        let dragged = ShellSplitDrag.treeWidth(
            draggedTo: 400,
            windowWidth: windowWidth,
            panelWidth: 0,
            panelPlacement: .column
        )
        let resolved = resolve(windowWidth: windowWidth, tree: dragged, isPanelVisible: false)

        #expect(resolved.layout.treeWidth == dragged)
    }
}
