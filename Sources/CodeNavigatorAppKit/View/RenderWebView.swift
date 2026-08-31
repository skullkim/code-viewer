import SwiftUI
import WebKit

/// The surface that actually draws a rendered document (REQ-013, ADR-0109, INV-6).
///
/// **What is measured and what is not.** The spike measured that a `.*` content rule blocks
/// every remote request while `allowsContentJavaScript = false` alone does not (9 requests
/// still went out), and that the CSP backstop holds for both a full page and a headless
/// fragment. What has **not** been measured is anything that needs a running instance of this
/// view: which URLs reach `decidePolicyFor` for a relative link under a given `baseURL`, and
/// how long the rule list takes to compile. Until those are measured this view is written to
/// fail closed and is not claimed to work.
///
/// The order here is the whole point: rules first, document second, and no path between them.
struct RenderWebView: NSViewRepresentable {

    let html: String
    let documentRelativePath: String
    let projectRoot: String
    /// Called when a link is clicked. The view never follows one itself.
    let onNavigation: (RenderNavigation) -> Void
    /// Called as the sandbox becomes ready or fails, so the surface can show W-14's card.
    let onReadinessChange: (RenderSandboxReadiness) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            documentRelativePath: documentRelativePath,
            projectRoot: projectRoot,
            onNavigation: onNavigation,
            onReadinessChange: onReadinessChange
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: Self.sandboxedConfiguration())
        webView.navigationDelegate = context.coordinator
        // No back/forward gesture: this is a document, and a swipe that navigates away from a
        // page with no history reads as the render breaking.
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")

        context.coordinator.attach(to: webView, html: html)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(documentRelativePath: documentRelativePath, projectRoot: projectRoot)
        context.coordinator.render(html)
    }

    /// The configuration every render web view gets.
    ///
    /// `allowsContentJavaScript = false` is here for inline scripts, which need no network to
    /// change the DOM. It is **not** what stops remote loads — the content rule list is, and
    /// treating this flag as the network defence is the mistake ADR-0109 was written to record.
    static func sandboxedConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        // Nothing this view loads should ever be written to a shared cache or cookie store.
        configuration.websiteDataStore = .nonPersistent()
        return configuration
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {

        private var documentRelativePath: String
        private var projectRoot: String
        private let onNavigation: (RenderNavigation) -> Void
        private let onReadinessChange: (RenderSandboxReadiness) -> Void

        private weak var webView: WKWebView?
        private var readiness: RenderSandboxReadiness = .compiling
        /// The document waiting for the rules to land, if one arrived early.
        private var pendingHTML: String?
        /// The document currently on screen, so an unchanged update does not reload.
        private var loadedHTML: String?
        /// True only across the programmatic load, so the delegate can tell our own navigation
        /// apart from one the document started.
        private var isLoadingOwnDocument = false

        init(
            documentRelativePath: String,
            projectRoot: String,
            onNavigation: @escaping (RenderNavigation) -> Void,
            onReadinessChange: @escaping (RenderSandboxReadiness) -> Void
        ) {
            self.documentRelativePath = documentRelativePath
            self.projectRoot = projectRoot
            self.onNavigation = onNavigation
            self.onReadinessChange = onReadinessChange
        }

        func update(documentRelativePath: String, projectRoot: String) {
            self.documentRelativePath = documentRelativePath
            self.projectRoot = projectRoot
        }

        func attach(to webView: WKWebView, html: String) {
            self.webView = webView
            pendingHTML = html
            compileRules()
        }

        // MARK: 규칙

        /// Compiles the blanket block and attaches it before anything is rendered.
        ///
        /// The list compiles asynchronously, and the window before it lands is a window with no
        /// blocking at all. Nothing is loaded in it — a document that arrives early waits in
        /// `pendingHTML`. **비어 있는 화면이 새는 화면보다 낫다.**
        private func compileRules() {
            Task { [weak self] in
                guard let store = WKContentRuleListStore.default() else {
                    // No store means no way to attach the rules, so there is no safe way to
                    // render. Refusing is the only option that keeps INV-6 true.
                    self?.settle(.failed(reason: "콘텐츠 규칙 저장소를 열 수 없습니다"))
                    return
                }

                do {
                    let list = try await store.compileContentRuleList(
                        forIdentifier: Self.ruleListIdentifier,
                        encodedContentRuleList: RenderContentRules.blockEverything
                    )
                    guard let self, let list else {
                        self?.settle(.failed(reason: "차단 규칙을 만들지 못했습니다"))
                        return
                    }
                    self.webView?.configuration.userContentController.add(list)
                    self.settle(.ready)
                } catch {
                    self?.settle(.failed(reason: error.localizedDescription))
                }
            }
        }

        private func settle(_ state: RenderSandboxReadiness) {
            readiness = state
            onReadinessChange(state)
            if case .ready = state, let pending = pendingHTML {
                pendingHTML = nil
                render(pending)
            }
        }

        // MARK: 문서

        func render(_ html: String) {
            guard html != loadedHTML else {
                return
            }
            // The single gate. There is deliberately no other call to `loadHTMLString` in this
            // file, so "render without rules" is not something a later edit can express by
            // forgetting a check.
            guard let document = RenderLoadGate.documentToLoad(html, readiness: readiness) else {
                pendingHTML = html
                return
            }
            loadedHTML = html
            isLoadingOwnDocument = true
            // The base is the document's own folder, and that choice is measured, not assumed
            // (`scripts/spike-render-host.swift`, 2026-08-31):
            //
            //   baseURL: nil   `./OTHER.md` stays `./OTHER.md` — never resolved, so a click
            //                  has no URL to hand us, and `#anchor` arrives as
            //                  `about:blank#anchor`
            //   file base      `./OTHER.md` → `file:///…/docs/OTHER.md`, `#anchor` →
            //                  `file:///…/guide.md#anchor` — both judgeable
            //
            // And the blocking still holds under it: the same spike measured 6 remote requests
            // without rules and **0** with them under this base, with the document confirmed
            // rendered both times. A base that resolved links but weakened the sandbox would
            // have been the wrong trade; it does not.
            webView?.loadHTMLString(document, baseURL: documentDirectory)
        }

        // MARK: 내비게이션

        /// ⚠ The signature must match the protocol **exactly**, `@MainActor` and all.
        ///
        /// `WKNavigationDelegate`'s methods are optional, so a signature that only *nearly*
        /// matches is not an error — it is simply never called. The compiler says
        /// "nearly matches optional requirement" as a **warning**, the build stays green, and
        /// every link in every rendered document navigates freely while this file appears to
        /// be intercepting them. Caught here by reading a warning; the test below keeps it
        /// caught by asking the runtime whether this object actually answers the selector.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            // Our own `loadHTMLString`, allowed exactly once per load. Allowing every `.other`
            // navigation would also allow the ones a document can start on its own.
            if isLoadingOwnDocument {
                isLoadingOwnDocument = false
                decisionHandler(.allow)
                return
            }

            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let decision = RenderNavigationPolicy.decide(
                navigationURL: url,
                documentRelativePath: documentRelativePath,
                projectRoot: projectRoot
            )

            // Everything except an in-document scroll is cancelled here and handed upward. The
            // web view never navigates: remote content is never drawn inside the app (INV-6),
            // and opening a project file is the app's job, not the renderer's.
            switch decision {
            case .scrollToFragment:
                decisionHandler(.allow)
            case .openInTab, .openInBrowser, .refuse:
                decisionHandler(.cancel)
            }

            onNavigation(decision)
        }

        /// The folder the document lives in — what relative links resolve against.
        private var documentDirectory: URL {
            URL(fileURLWithPath: (projectRoot as NSString)
                .appendingPathComponent((documentRelativePath as NSString).deletingLastPathComponent))
        }

        private static let ruleListIdentifier = "code-navigator-render-block-all"
    }
}
