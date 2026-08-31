import Foundation

/// Whether the blanket block is actually attached to the web view yet (ADR-0109, INV-6).
///
/// The list compiles **asynchronously**, so there is a window between creating the web view
/// and the rules taking effect. A document loaded in that window runs with no blocking at
/// all — and nothing on screen would look wrong, which is the failure mode ADR-0109 chose
/// the whole design to avoid.
public enum RenderSandboxReadiness: Sendable, Hashable {
    case compiling
    case ready
    case failed(reason: String)
}

/// Decides whether a document may be handed to the web view at all.
///
/// ADR-0109: *"차단이 없는 채로 그리는 경로를 코드에 두지 않는다 — 그 경로는 반드시 언젠가
/// 실행된다."* This is that rule made into a function, so that "load the document" cannot be
/// written without answering "are the rules on yet".
public enum RenderLoadGate {

    /// The document to hand the web view, or `nil` when it must not be handed over.
    ///
    /// Returns the document only from `.ready`. Written as a `switch` over every state rather
    /// than as `guard readiness != .compiling`: a negative check keeps passing when a new
    /// state is added, and the new state silently becomes a loading state.
    public static func documentToLoad(_ html: String, readiness: RenderSandboxReadiness) -> String? {
        switch readiness {
        case .ready:
            return html
        case .compiling, .failed:
            return nil
        }
    }

    /// What the surface shows instead of the document.
    ///
    /// Nothing while compiling — that wait is measured in milliseconds and belongs to the
    /// existing render spinner, not to a card that would flash. A failure is different: it is
    /// terminal, and silence there is a blank screen the reader would read as an empty file.
    public static func notice(for readiness: RenderSandboxReadiness) -> RenderNoticeCard? {
        guard case .failed(let reason) = readiness else {
            return nil
        }
        return RenderNoticeCard(
            glyph: "⚠️",
            title: "안전하게 렌더할 수 없어 표시하지 않았습니다",
            // The reason is named, not masked. "Something went wrong" leaves a reader unable
            // to tell a transient failure from a broken install.
            detail: "렌더 보기는 원격 리소스를 차단한 뒤에만 문서를 그립니다. 차단 규칙을 준비하지 "
                + "못했습니다: \(reason)",
            actions: [.viewSource, .retry]
        )
    }
}

/// The content rule list the render web view runs under (ADR-0109).
public enum RenderContentRules {

    /// Block everything, with no exceptions and no second rule.
    ///
    /// Measured in ADR-0109's spike, and each finding is why this is one line:
    /// - `allowsContentJavaScript = false` does **not** stop network requests — 9 went out
    ///   with scripts disabled. This list is what actually blocks them.
    /// - Regex alternation (`|`) does not compile, so "block these schemes" would need one
    ///   rule per scheme — and a scheme nobody listed is a scheme nobody blocks.
    /// - `ignore-previous-rules` did not bring a custom scheme back, so there is no working
    ///   way to carve an exception even if we wanted one. Local files reach the page as
    ///   `data:` URIs the app built instead.
    public static let blockEverything = """
    [{"trigger": {"url-filter": ".*"}, "action": {"type": "block"}}]
    """
}
