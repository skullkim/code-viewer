import Testing
import AppKit
import SwiftUI
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Puts the real window into a real hosting view and makes SwiftUI evaluate it.
///
/// The mount check in `scripts/check-view-mounts.sh` proves a view is *referenced*; this
/// proves the window can actually be built and laid out without trapping. Neither alone is
/// enough: a view can be referenced from a branch that crashes, and a view that lays out
/// fine can still be referenced from nowhere.
@MainActor
@Suite("CompositionRoot — 창이 실제로 조립되는가 (REQ-001·003·004·011)")
struct CompositionRootTests {

    private func makeModels() -> (AppModel, SearchModel, FakeProjectSession, FakeEditorSession) {
        let project = FakeProjectSession()
        let editor = FakeEditorSession()
        let model = AppModel(
            projectSession: project,
            editorSession: editor,
            workspace: RecordingWorkspace(),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (model, SearchModel(projectSession: project), project, editor)
    }

    /// Builds the window and forces a layout pass, so SwiftUI evaluates every `body` on the
    /// path. Returns the hosting view so a caller can inspect it.
    @discardableResult
    private func layOutWindow(
        model: AppModel,
        search: SearchModel,
        size: CGSize = CGSize(width: 1280, height: 800)
    ) -> NSHostingView<MainWindowView> {
        let hosting = NSHostingView(rootView: MainWindowView(model: model, search: search))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test("프로젝트가 없는 창이 조립되고 레이아웃된다")
    func theWelcomeWindowLaysOut() {
        let (model, search, _, _) = makeModels()
        let hosting = layOutWindow(model: model, search: search)
        #expect(hosting.frame.width == 1280)
        #expect(!hosting.subviews.isEmpty, "호스팅 뷰가 아무것도 그리지 않았다")
    }

    @Test("프로젝트가 열린 창이 조립되고 레이아웃된다")
    func theProjectWindowLaysOut() {
        let (model, search, _, _) = makeModels()
        model.projectRootPath = "/repo"
        let hosting = layOutWindow(model: model, search: search)
        #expect(!hosting.subviews.isEmpty)
    }

    @Test("모든 창 크기에서 조립된다 — 오버레이 전환 경로 포함")
    func everyWindowSizeLaysOut() {
        // Each breakpoint takes a different branch through the pane layout (§4.4). A branch
        // that traps would otherwise only be found by resizing the real window.
        let (model, search, _, _) = makeModels()
        model.projectRootPath = "/repo"
        for size in [CGSize(width: 1600, height: 1000), CGSize(width: 1000, height: 700),
                     CGSize(width: 820, height: 620), CGSize(width: 720, height: 480)] {
            layOutWindow(model: model, search: search, size: size)
        }
    }

    @Test("편집 세션이 끊긴 창도 조립된다")
    func theWindowLaysOutWithALostSession() {
        let (model, search, _, _) = makeModels()
        model.projectRootPath = "/repo"
        model.handle(sessionState: .disconnected(reason: "프로세스 종료"))
        #expect(model.editSessionOverlay != nil, "오버레이가 없으면 이 테스트가 검증할 경로가 없다")
        layOutWindow(model: model, search: search)
    }

    @Test("기동 실패 상태의 창도 조립된다")
    func theWindowLaysOutWithAStartupFailure() {
        let (model, search, _, _) = makeModels()
        model.projectRootPath = "/repo"
        model.handle(sessionState: .startupFailed(EditorStartupFailure(
            kind: .notInstalled,
            reason: "Neovim을 찾을 수 없습니다",
            searchedPaths: ["/opt/homebrew/bin/nvim"],
            requiredVersion: "0.9.0"
        )))
        layOutWindow(model: model, search: search)
    }

    @Test("정의 후보 팝오버가 뜬 창도 조립된다")
    func theWindowLaysOutWithTheDefinitionPicker() async {
        let (model, search, project, editor) = makeModels()
        model.projectRootPath = "/repo"
        editor.wordUnderCursorValue = "handle"
        project.definitionsByName["handle"] = [
            SymbolDefinition(name: "handle", kind: .function, path: "a.swift", line: 1, signature: "func handle()"),
            SymbolDefinition(name: "handle", kind: .function, path: "b.swift", line: 9, signature: "func handle()"),
        ]
        await model.goToDefinition()
        #expect(model.definitionCandidates?.count == 2, "후보가 없으면 이 테스트가 검증할 경로가 없다")
        layOutWindow(model: model, search: search)
    }

    @Test("그리드 프레임이 있는 창도 조립된다")
    func theWindowLaysOutWithAGridFrame() {
        let (model, search, _, _) = makeModels()
        model.projectRootPath = "/repo"
        model.handle(snapshot: EditorGridSnapshot(
            columns: 40, rows: 2,
            lines: [
                EditorGridLine(runs: [EditorTextRun(text: "let x = 1", style: .plain, startColumn: 0, cellWidth: 9)]),
                EditorGridLine(runs: [EditorTextRun(text: "인덱스", style: .plain, startColumn: 0, cellWidth: 6)]),
            ],
            cursor: EditorCursorPosition(row: 0, column: 4),
            mode: .normal,
            defaultForeground: EditorColor(packedRGB: 0xE8E8ED),
            defaultBackground: EditorColor(packedRGB: 0x1B1B1F),
            revision: 1
        ))
        #expect(model.gridFrame != nil)
        layOutWindow(model: model, search: search)
    }

    @Test("심볼 검색 모달이 뜬 창도 조립된다")
    func theWindowLaysOutWithTheSymbolSearchModal() {
        let (model, search, _, _) = makeModels()
        model.projectRootPath = "/repo"
        search.isShowingSymbolSearch = true
        layOutWindow(model: model, search: search)
    }

    @Test("사용자가 조절한 폭이 창에 반영된다")
    func draggedWidthsReachTheWindow() {
        // REQ-011 AC-3. The splitter writes to preferences and the layout reads them, so
        // this checks the round trip rather than either half.
        let (model, search, _, _) = makeModels()
        model.projectRootPath = "/repo"
        model.shell.setTreeWidth(300)
        model.shell.setPanelWidth(400)

        let layout = ShellLayout.resolve(
            windowSize: CGSize(width: 1600, height: 1000),
            preferredTreeWidth: model.shell.treeWidth,
            preferredPanelWidth: model.shell.panelWidth
        )
        #expect(layout.treeWidth == 300)
        #expect(layout.panelWidth == 400)
        layOutWindow(model: model, search: search)
    }

    @Test("트리·패널을 숨긴 창도 조립된다")
    func theWindowLaysOutWithPanesHidden() {
        // ⌥⌘1 · ⌥⌘0 change what is mounted, so each combination is a distinct branch
        // through the pane layout.
        let (model, search, _, _) = makeModels()
        model.projectRootPath = "/repo"
        for (tree, panel) in [(false, true), (true, false), (false, false)] {
            model.shell.isTreeVisible = tree
            model.shell.isPanelVisible = panel
            layOutWindow(model: model, search: search)
        }
    }

    // MARK: What the window is wired to

    @Test("창이 꽂는 화면 영역이 조립 규칙과 일치한다")
    func theWindowMountsWhatTheCompositionSays() {
        // The window reads its panes from ShellComposition, so asserting the rule asserts
        // the window — and the rule is the thing a future edit would have to change.
        let wide = ShellLayout.resolve(windowSize: CGSize(width: 1600, height: 1000))
        #expect(ShellComposition.panes(hasOpenProject: false, layout: wide) == [.projectOpen])
        #expect(ShellComposition.panes(hasOpenProject: true, layout: wide) == [.fileTree, .editorGrid, .referencePanel])
    }
}
