import Testing
import Foundation
import CoreGraphics
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 렌더 보기의 화면 신호 (REQ-013, 02b W-14 · 기준물 `render-markdown-large.png`).
@Suite("렌더 보기가 자기 상태를 말한다 (디자인 충실도)")
struct RenderFidelityTests {

    private func layout(_ width: CGFloat = 1600) -> ShellLayout {
        ShellLayout.resolve(windowSize: CGSize(width: width, height: 900))
    }

    private func toolbar(renderView: RenderViewState) -> ToolbarPresentation {
        ToolbarPresentation.make(
            projectName: "proj",
            editorStatus: nil,
            availability: MenuAvailability(inputMode: .vim, sessionState: .connected, hasOpenProject: true),
            layout: layout(),
            renderView: renderView
        )
    }

    private func statusBar(renderView: RenderViewState) -> StatusBarPresentation {
        StatusBarPresentation.make(
            sessionState: .connected,
            editorStatus: EditorStatus(
                filePath: "/tmp/proj/README.md", isDirty: false,
                cursorLine: 5, cursorColumn: 1, mode: .normal, inputMode: .vim
            ),
            indexState: .ready,
            inputMode: .vim,
            message: nil,
            projectRoot: "/tmp/proj",
            layout: layout(),
            renderView: renderView
        )
    }

    // ① 툴바 활성 강조 — 상태 신호이지 장식이 아니다

    @Test("렌더를 보고 있으면 툴바 버튼이 눌린 상태다")
    func theToolbarShowsWhichViewIsOn() {
        // 이게 없으면 **툴바만 보고는 지금 보는 게 렌더인지 소스인지 알 수 없다.**
        // `Vim`/`표준` 세그먼트는 이미 활성을 그린다 — 같은 종류의 신호다.
        let on = toolbar(renderView: RenderViewState(isRenderable: true, mode: .rendered))
        #expect(on.buttons.first { $0.command == .toggleRenderView }?.isOn == true)

        let off = toolbar(renderView: RenderViewState(isRenderable: true, mode: .source))
        #expect(off.buttons.first { $0.command == .toggleRenderView }?.isOn == false)
    }

    // ③ 툴바 순서 — 기준물이 정한 자리

    @Test("툴바 순서가 기준물과 같다")
    func theToolbarOrderMatchesTheReference() {
        // `렌더` 는 편집 대상에 붙는 동작이라 검색 옆이고, `패널` 은 창 배치라 끝이다.
        #expect(toolbar(renderView: .noDocument).buttons.map(\.command)
                == [.symbolSearch, .textSearch, .toggleRenderView, .togglePanel])
    }

    // ② 상태바 — 같은 자리를 두 보기가 다른 뜻으로 쓴다

    @Test("🔑 렌더 보기에서는 커서 위치 대신 문서 형식을 말한다")
    func renderViewNamesTheFormatInsteadOfACursor() {
        // `5:1` 은 읽기 전용 렌더에서 **뜻이 없다.** 없는 정보가 빠진 게 아니라
        // **틀린 정보가 그 자리를 쓰고 있다** — 사용자는 커서가 있다고 읽는다.
        let rendered = statusBar(renderView: RenderViewState(isRenderable: true, mode: .rendered))
        #expect(rendered.cursorText == "Markdown")
    }

    @Test("HTML 은 HTML 이라고 말한다")
    func htmlNamesItself() {
        let bar = StatusBarPresentation.make(
            sessionState: .connected,
            editorStatus: EditorStatus(
                filePath: "/tmp/proj/page.html", isDirty: false,
                cursorLine: 5, cursorColumn: 1, mode: .normal, inputMode: .vim
            ),
            indexState: .ready, inputMode: .vim, message: nil,
            projectRoot: "/tmp/proj", layout: layout(),
            renderView: RenderViewState(isRenderable: true, mode: .rendered)
        )
        #expect(bar.cursorText == "HTML")
    }

    @Test("🔑 소스 보기에서는 커서 위치가 그대로다")
    func sourceViewKeepsTheCursor() {
        // 반대 방향 방어선. 형식 이름으로 **덮어쓰면** 편집 중에 커서를 잃는다 —
        // 두 보기가 같은 자리를 다른 뜻으로 쓰는 것이지, 한쪽이 다른 쪽을 대체하는 게 아니다.
        let source = statusBar(renderView: RenderViewState(isRenderable: true, mode: .source))
        #expect(source.cursorText == "5:1")

        let plain = statusBar(renderView: .noDocument)
        #expect(plain.cursorText == "5:1")
    }
}
