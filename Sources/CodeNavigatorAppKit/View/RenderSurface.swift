import SwiftUI

/// The render view, assembled (REQ-013, design 02b §3 W-14).
///
/// This is the seam between the two halves of the feature: the chrome that says what is being
/// shown (`RenderDocumentView`) and the sandboxed surface that shows it (`RenderWebView`).
/// Keeping the assembly here means the window mounts **one** thing and does not have to know
/// that a web view is involved, or in what order the sandbox has to be ready.
///
/// Presentational on purpose. The document arrives already prepared — `RenderDocumentPipeline`
/// has converted, rewritten, and inlined it — because that work is asynchronous and belongs to
/// a model, not to a `body` that SwiftUI may run at any time.
struct RenderSurface: View {

    let screen: RenderDocumentPresentation
    let blocked: BlockedResourcePresentation
    /// Sandboxed HTML from `RenderDocumentPipeline.prepare`.
    let html: String
    /// Where the document sits, for resolving links and for the root check. Passed in rather
    /// than read from "the active tab": the active tab moves when the user types `gt`, and the
    /// surface would then judge one project's links against another's root.
    let documentRelativePath: String
    let projectRoot: String
    let onAction: (RenderDocumentAction) -> Void
    let onNavigation: (RenderNavigation) -> Void

    /// Owned here because it is a property of this web view instance, not of the document.
    @State private var readiness: RenderSandboxReadiness = .compiling

    var body: some View {
        RenderDocumentView(
            screen: screenReflectingSandbox,
            blocked: blocked,
            onAction: onAction
        ) {
            RenderWebView(
                html: html,
                documentRelativePath: documentRelativePath,
                projectRoot: projectRoot,
                onNavigation: onNavigation,
                onReadinessChange: { readiness = $0 }
            )
        }
    }

    /// The chrome, with a sandbox failure folded in.
    ///
    /// A failed rule compile is not a render failure in the usual sense — the document is fine
    /// and we refused to draw it — but it reaches the reader the same way, as a card that says
    /// what happened and offers the source view. Silence here would be a blank panel the
    /// reader would read as an empty file (AC-6).
    private var screenReflectingSandbox: RenderDocumentPresentation {
        guard let notice = RenderLoadGate.notice(for: readiness) else {
            return screen
        }
        return RenderDocumentPresentation(
            fileName: screen.fileName,
            readOnlyBadge: screen.readOnlyBadge,
            sourceBadge: screen.sourceBadge,
            sourceTooltip: screen.sourceTooltip,
            toggleTitle: screen.toggleTitle,
            progressText: nil,
            showsHeaderSpinner: false,
            notice: notice,
            // Nothing was drawn, so there is no previous document to keep.
            keepsPreviousDocument: false
        )
    }
}
