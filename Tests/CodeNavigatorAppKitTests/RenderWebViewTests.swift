import Testing
import WebKit
@testable import CodeNavigatorAppKit

/// 웹뷰 호스트가 **실제로** 델리게이트로 동작하는지 (REQ-013, INV-6).
///
/// 화면 없이 잴 수 있는 것만 여기서 잰다. 원격 차단·규칙 컴파일 시간·링크 URL 해석은
/// 도는 웹뷰가 필요해서 `scripts/spike-render-host.swift` 가 잰다.
@MainActor
@Suite("RenderWebView — 호스트 계약")
struct RenderWebViewTests {

    private func makeCoordinator() -> RenderWebView.Coordinator {
        RenderWebView.Coordinator(
            documentRelativePath: "docs/guide.md",
            projectRoot: "/tmp",
            onNavigation: { _ in },
            onReadinessChange: { _ in }
        )
    }

    @Test("내비게이션 판정 메서드가 프로토콜을 실제로 만족한다")
    func theNavigationDelegateMethodIsActuallyWired() {
        // **이 테스트가 실제 결함을 잡았다.** `WKNavigationDelegate` 의 메서드는 전부
        // 옵셔널이라, 시그니처가 *비슷하기만* 하면 컴파일러는 **경고**만 내고 빌드는
        // 초록으로 남는다. 그리고 그 메서드는 **한 번도 불리지 않는다** — 문서의 모든
        // 링크가 자유롭게 이동하는데 이 파일은 가로채는 것처럼 보인다.
        //
        // `@MainActor` 하나가 빠져서 그랬다. 타입이 아니라 **런타임이 이 객체를 어떻게
        // 보는지**를 물어야 잡힌다.
        let selector = Selector("webView:decidePolicyForNavigationAction:decisionHandler:")

        #expect(
            makeCoordinator().responds(to: selector),
            "델리게이트 메서드가 프로토콜과 어긋나 있다 — 가로채기가 통째로 죽는다"
        )
    }

    @Test("설정이 스크립트를 끈다")
    func theConfigurationDisablesScripts() {
        // 네트워크를 막는 건 콘텐츠 룰이고 이건 인라인 스크립트 몫이다(ADR-0109).
        // 둘을 헷갈리면 "JS 껐으니 안전"이 되고, 실측은 그때 원격 요청 9건이었다.
        let configuration = RenderWebView.sandboxedConfiguration()

        #expect(configuration.defaultWebpagePreferences.allowsContentJavaScript == false)
    }

    @Test("데이터 저장소가 비영속이다")
    func theDataStoreIsNotPersistent() {
        // 신뢰하지 않는 저장소의 문서가 공유 캐시·쿠키에 흔적을 남기지 않는다.
        #expect(RenderWebView.sandboxedConfiguration().websiteDataStore.isPersistent == false)
    }
}
