import Testing
import CoreGraphics
@testable import CodeNavigatorAppKit

/// The window's wiring, as an assertion rather than a hope.
///
/// Five views were finished, tested and unreachable at once, because nothing mounted them
/// and nothing checked that anything did. Compiling and passing tests says a view works;
/// it says nothing about whether a user can see it.
@Suite("ShellComposition — 창이 무엇을 꽂는가 (REQ-001·003·004)")
struct ShellCompositionTests {

    private let wide = ShellLayout.resolve(windowSize: CGSize(width: 1600, height: 1000))
    private let narrow = ShellLayout.resolve(windowSize: CGSize(width: 820, height: 620))

    @Test("프로젝트가 없으면 프로젝트 열기 화면만 꽂는다")
    func withoutAProjectOnlyTheWelcomeScreenIsMounted() {
        // Design §3 W-1: the three areas are replaced by the welcome screen, not emptied.
        #expect(ShellComposition.panes(hasOpenProject: false, layout: wide) == [.projectOpen])
    }

    @Test("프로젝트가 열리면 세 영역을 꽂는다")
    func withAProjectAllThreeAreasAreMounted() {
        #expect(ShellComposition.panes(hasOpenProject: true, layout: wide) == [.fileTree, .editorGrid, .referencePanel])
    }

    @Test("좁은 창에서도 세 영역이 전부 꽂힌다 — 패널은 오버레이가 될 뿐 사라지지 않는다")
    func narrowWindowsStillMountEveryPane() {
        // §4.4 turns the panel into an overlay below 900pt. An overlay is still mounted;
        // dropping it would lose the reference and search results entirely.
        #expect(ShellComposition.panes(hasOpenProject: true, layout: narrow) == [.fileTree, .editorGrid, .referencePanel])
        #expect(ShellComposition.placement(of: .referencePanel, layout: narrow) == .overlay)
        #expect(ShellComposition.placement(of: .fileTree, layout: narrow) == .column)
    }

    @Test("에디터는 어떤 창 크기에서도 자기 열을 갖는다")
    func theEditorAlwaysHasAColumn() {
        for width in [1600.0, 1000, 900, 820, 720, 640] {
            let layout = ShellLayout.resolve(windowSize: CGSize(width: width, height: 600))
            #expect(ShellComposition.placement(of: .editorGrid, layout: layout) == .column, "폭 \(width)")
            #expect(ShellComposition.panes(hasOpenProject: true, layout: layout).contains(.editorGrid), "폭 \(width)")
        }
    }

    @Test("트리를 숨기면 꽂지 않는다 — 좁히는 게 아니라 없앤다")
    func hidingTheTreeRemovesIt() {
        // ⌥⌘1. Hiding is for giving the editor the room, so a hidden pane is absent rather
        // than narrow.
        let panes = ShellComposition.panes(hasOpenProject: true, layout: wide, isTreeVisible: false)
        #expect(panes == [.editorGrid, .referencePanel])
    }

    @Test("패널을 숨기면 꽂지 않는다")
    func hidingThePanelRemovesIt() {
        let panes = ShellComposition.panes(hasOpenProject: true, layout: wide, isPanelVisible: false)
        #expect(panes == [.fileTree, .editorGrid])
    }

    @Test("둘 다 숨겨도 에디터는 남는다")
    func theEditorSurvivesEveryToggle() {
        // No menu row offers to hide the editor, and none should: it is the reason the
        // window exists.
        let panes = ShellComposition.panes(
            hasOpenProject: true, layout: wide, isTreeVisible: false, isPanelVisible: false
        )
        #expect(panes == [.editorGrid])
    }

    @Test("숨김은 프로젝트가 없을 때의 화면을 바꾸지 않는다")
    func togglesDoNotAffectTheWelcomeScreen() {
        let panes = ShellComposition.panes(
            hasOpenProject: false, layout: wide, isTreeVisible: false, isPanelVisible: false
        )
        #expect(panes == [.projectOpen])
    }

    @Test("모든 ShellPane이 어떤 상태에선가 꽂힌다")
    func everyShellPaneIsMountedInSomeState() {
        // The name says `ShellPane` on purpose. An earlier version was called "만들어 놓고
        // 안 쓰는 것이 없다", which claims far more than it checks: `ShellSplitter` is not
        // a pane, so it sat unmounted for hours while this test stayed green. A test whose
        // name promises completeness stops the next person from looking further, so the
        // name is kept to exactly what the assertion covers. Views as a whole are the
        // business of `scripts/check-view-mounts.sh`, which discovers them rather than
        // listing them.
        //
        // Called with everything visible: with a pane hidden it is legitimately absent.
        let mounted = Set(
            ShellComposition.panes(hasOpenProject: false, layout: wide)
                + ShellComposition.panes(
                    hasOpenProject: true, layout: wide,
                    isTreeVisible: true, isPanelVisible: true
                )
        )
        #expect(mounted == Set(ShellPane.allCases), "꽂히지 않는 영역: \(Set(ShellPane.allCases).subtracting(mounted))")
    }
}
