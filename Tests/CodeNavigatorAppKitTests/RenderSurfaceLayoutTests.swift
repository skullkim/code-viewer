import Testing
import Foundation
import SwiftUI
import AppKit
import WebKit
@testable import CodeNavigatorAppKit

/// 조립된 렌더 표면이 **자리를 차지하는가** (REQ-013, D-렌더 3차).
///
/// QA 가 본 것: 106바이트 문서가 **완전 백지**. 본문도 문구도 플레이스홀더도 없고 헤더만
/// 정상. 7초를 기다려도 같다. 단위 테스트는 전부 초록이었고 스파이크도 초록이었다 —
/// **파이프라인은 문서를 만들었고 웹뷰는 그것을 로드했는데 그릴 자리가 0 이었다.**
///
/// 크기가 0 인 뷰는 **아무 신호도 내지 않는다.** 에러도 로그도 빈 문구도 없다. 그래서
/// 이 결함은 침묵했고, INV-6 이 금지하는 "조용히 비우는" 화면이 됐다 — 우리가 막으려던
/// 그 상태를 레이아웃이 만들었다.
@MainActor
@Suite("렌더 표면 레이아웃 — 문서가 그려질 자리가 있는가 (REQ-013)")
struct RenderSurfaceLayoutTests {

    private func findWebView(_ view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for child in view.subviews {
            if let found = findWebView(child) { return found }
        }
        return nil
    }

    private func hostedSurface(width: CGFloat, height: CGFloat) -> NSHostingView<RenderSurface> {
        let surface = RenderSurface(
            screen: RenderDocumentPresentation.make(
                fileName: "README.md", phase: .rendered(source: .savedFile),
                hasPreviousDocument: false, elapsedSeconds: nil
            ),
            blocked: BlockedResourcePresentation.make(blocked: []),
            html: "<p>본문이 있는 문서</p>",
            documentRelativePath: "README.md",
            projectRoot: NSTemporaryDirectory(),
            onAction: { _ in },
            onNavigation: { _ in }
        )
        let hosting = NSHostingView(rootView: surface)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test("문서 표면이 높이를 갖는다")
    func theDocumentSurfaceHasHeight() {
        // **이것이 백지의 원인이었다.** 웹뷰를 SwiftUI `ScrollView` 안에 두면 스크롤 축으로
        // **무한 높이가 제안**되고, `WKWebView` 는 고유 크기가 없어 **0 으로 접힌다.**
        // 웹뷰는 자기 스크롤을 스스로 하므로 바깥 스크롤이 애초에 필요 없었다.
        let hosting = hostedSurface(width: 800, height: 600)

        let webView = findWebView(hosting)
        #expect(webView != nil, "표면에 웹뷰가 없다")
        #expect((webView?.frame.height ?? 0) > 0, "문서를 그릴 높이가 0 이다 — 화면은 백지가 된다")
    }

    @Test("헤더를 뺀 나머지를 문서가 채운다")
    func theDocumentFillsWhatTheHeaderLeaves() {
        // 헤더(28pt)와 구분선을 뺀 만큼은 문서 몫이다. 절반만 차지하면 아래가 비어 보이고,
        // 그건 "문서가 짧다"로 읽힌다.
        let hosting = hostedSurface(width: 800, height: 600)
        let height = findWebView(hosting)?.frame.height ?? 0

        #expect(height > 500, "문서 높이가 \(height) 뿐이다 — 헤더를 빼도 이보다 커야 한다")
    }

    @Test("창이 좁아져도 문서 자리가 사라지지 않는다")
    func aNarrowWindowStillLeavesRoomForTheDocument() {
        // 최소 창(720×480)에서도 읽을 자리가 있어야 한다.
        let height = findWebView(hostedSurface(width: 720, height: 480))?.frame.height ?? 0

        #expect(height > 0)
    }
}
