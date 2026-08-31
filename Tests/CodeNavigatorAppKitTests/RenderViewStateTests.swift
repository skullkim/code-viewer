import Testing
import Foundation
import CoreGraphics
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 02b F-14 1 — 렌더 보기는 **세 곳에 동시에** 그려진다.
///
/// 툴바 `렌더` 버튼 눌림 · 렌더 헤더 바 · 상태바 `[읽기 전용] 렌더 보기`. 셋이 어긋나면
/// 사용자는 어느 것이 진짜인지 알 방법이 없다 — 화면 셋이 서로를 반증하는데 어느 쪽도
/// 자기가 틀렸다고 말하지 않는다.
@Suite("렌더 보기 3중 표시는 한 출처에서 나온다 (REQ-013 AC-3)")
struct RenderViewStateTests {

    // MARK: 파일별 기억 (F-14 2, D-C)

    @Test("렌더 가능한 파일은 렌더로 열린다")
    func renderableFilesOpenRendered() {
        let selection = RenderViewSelection()
        #expect(selection.mode(forPath: "README.md", isRenderable: true) == .rendered)
    }

    @Test("렌더할 수 없는 파일은 언제나 소스다")
    func nonRenderableFilesAreAlwaysSource() {
        var selection = RenderViewSelection()
        #expect(selection.mode(forPath: "main.swift", isRenderable: false) == .source)
        // 전환을 눌러도 기억할 선택이 없다 — F-14 4 는 이 경우를 상태바 메시지로 처리한다.
        selection.toggle(path: "main.swift", isRenderable: false)
        #expect(selection.mode(forPath: "main.swift", isRenderable: false) == .source)
    }

    @Test("전환은 그 파일에 대해 기억된다 — 다른 파일에 번지지 않는다")
    func theChoiceIsRememberedPerFile() {
        var selection = RenderViewSelection()
        selection.toggle(path: "README.md", isRenderable: true)

        #expect(selection.mode(forPath: "README.md", isRenderable: true) == .source)
        // 문서를 고치려는 사람은 한 번만 전환한다. 이 값이 다른 파일까지 바꾸면
        // 그 사람은 매번 되돌려야 한다.
        #expect(selection.mode(forPath: "CHANGELOG.md", isRenderable: true) == .rendered)
    }

    @Test("파일이 없으면 렌더 보기도 없다")
    func noDocumentMeansNoRenderView() {
        let selection = RenderViewSelection()
        #expect(selection.state(forPath: nil, isRenderable: true).isShowingRender == false)
    }

    // MARK: 🔑 세 표시가 서로를 반증하지 않는다

    @Test("툴바·상태바·헤더가 같은 답을 낸다 — 네 조합 전부")
    func allThreeSurfacesAgree() {
        for isRenderable in [true, false] {
            for mode in [DocumentViewMode.source, .rendered] {
                let state = RenderViewState(isRenderable: isRenderable, mode: mode)
                let truth = state.isShowingRender

                let toolbar = ToolbarPresentation.make(
                    projectName: "proj",
                    editorStatus: nil,
                    availability: MenuAvailability(inputMode: .vim, sessionState: .connected, hasOpenProject: true),
                    layout: ShellLayout.resolve(windowSize: CGSize(width: 1280, height: 800)),
                    renderView: state
                )
                let toolbarPressed = toolbar.buttons.first { $0.command == .toggleRenderView }?.isOn

                let statusBar = StatusBarPresentation.make(
                    sessionState: .connected,
                    editorStatus: nil,
                    indexState: .ready,
                    inputMode: .vim,
                    message: nil,
                    projectRoot: "/tmp/proj",
                    layout: ShellLayout.resolve(windowSize: CGSize(width: 1280, height: 800)),
                    renderView: state
                )
                let statusSaysRender = statusBar.modeSegment.secondaryLabel == "렌더 보기"

                #expect(toolbarPressed == truth,
                        "툴바 눌림이 어긋난다 (renderable=\(isRenderable) mode=\(mode))")
                #expect(statusSaysRender == truth,
                        "상태바가 어긋난다 (renderable=\(isRenderable) mode=\(mode))")
            }
        }
    }

    @Test("렌더할 수 없는 파일에서 툴바 버튼은 비활성이다")
    func theToolbarButtonIsDisabledForNonRenderableFiles() {
        // F-14 4: 누를 수 있게 두고 에러를 띄우는 것보다, 애초에 못 누르게 하는 쪽이
        // 왜 안 되는지를 누르기 전에 말해 준다.
        let toolbar = ToolbarPresentation.make(
            projectName: "proj",
            editorStatus: nil,
            availability: MenuAvailability(inputMode: .vim, sessionState: .connected, hasOpenProject: true),
            layout: ShellLayout.resolve(windowSize: CGSize(width: 1280, height: 800)),
            renderView: RenderViewState(isRenderable: false, mode: .source)
        )
        #expect(toolbar.buttons.first { $0.command == .toggleRenderView }?.isEnabled == false)
    }

    @Test("렌더 보기에서는 Vim 모드를 표시하지 않는다 — 거짓말이 된다")
    func renderViewDoesNotClaimAVimMode() {
        // 02b C-6. 렌더 보기에서 키는 nvim 에 전달되지 않는다. NORMAL 이라고 적으면
        // 사용자는 키가 먹힐 것으로 읽는다.
        let statusBar = StatusBarPresentation.make(
            sessionState: .connected,
            editorStatus: nil,
            indexState: .ready,
            inputMode: .vim,
            message: nil,
            projectRoot: "/tmp/proj",
            layout: ShellLayout.resolve(windowSize: CGSize(width: 1280, height: 800)),
            renderView: RenderViewState(isRenderable: true, mode: .rendered)
        )
        #expect(statusBar.modeSegment.primaryLabel == "읽기 전용")
        #expect(statusBar.modeSegment.secondaryLabel == "렌더 보기")
    }

    @Test("세션이 끊기면 그것이 렌더 보기보다 앞선다")
    func aDeadSessionOutranksTheRenderView() {
        // 렌더 보기는 *보기* 선택이고 세션 끊김은 *고장*이다. 소스로 돌아가도 편집이
        // 안 된다는 사실이 더 급하고, 렌더 보기를 벗어나야 알게 되면 늦다.
        let statusBar = StatusBarPresentation.make(
            sessionState: .disconnected(reason: "테스트"),
            editorStatus: nil,
            indexState: .ready,
            inputMode: .vim,
            message: nil,
            projectRoot: "/tmp/proj",
            layout: ShellLayout.resolve(windowSize: CGSize(width: 1280, height: 800)),
            renderView: RenderViewState(isRenderable: true, mode: .rendered)
        )
        #expect(statusBar.modeSegment.primaryLabel == "편집 불가")
    }
}
