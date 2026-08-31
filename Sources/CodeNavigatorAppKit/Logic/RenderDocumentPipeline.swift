import Foundation

/// Turns a document into the sandboxed HTML the web view is given (REQ-013, INV-6).
///
/// **Two passes, because the two halves disagree about time.** Preprocessing is synchronous
/// and pure — that is what makes it testable without a disk, and what keeps the sandbox rules
/// in plain functions. Reading a file is asynchronous, because it crosses into the engine.
///
/// The tempting bridge is to block the synchronous side until the read finishes. That is a
/// semaphore on the main thread, and it deadlocks: the work being waited on needs the very
/// thread that is waiting. It happened on this project the same day this was written — a
/// `--self-check` waited on a `@MainActor` task and the gate sat still for eighteen minutes.
///
/// So neither side is bent. The document is scanned once to learn *which* resources it wants,
/// those are read concurrently with `await`, and the scan runs again against what came back.
/// The cost is one extra pass over a document that is capped at 2MB.
public enum RenderDocumentPipeline {

    /// The document's own typography (design 02b §3 W-14).
    ///
    /// Lives with the document, not with the SwiftUI view around it, for two reasons found
    /// the hard way. The view-side modifiers that used to impose this **collapsed the web
    /// view to zero height**, and they never applied to `.html` files at all — those arrive
    /// as whole documents and never passed through them. Measure and prose size are
    /// properties of the document; the surface only decides how much room it gets.
    ///
    /// No `url()` anywhere: a stylesheet **we** inject that pulled a font or an image would
    /// be our own document breaking INV-6, and the sandbox would rightly block it.
    static let documentStyle = """
    <style>
    :root { color-scheme: light dark; }
    body {
      margin: 0 auto;
      /* 본문 최대 폭. 창이 아무리 넓어도 한 줄이 길어지면 읽기가 무너진다. */
      max-width: 720px;
      padding: 32px 24px;
      /* 산문 14px — 아래 깔린 13px 모노 코드 그리드와 확연히 달라야 한다. */
      font: 14px/1.7 -apple-system, system-ui, sans-serif;
      color: var(--cn-text-primary, #1d1d1f);
      background: transparent;
      word-break: break-word;
    }
    img, table, iframe { max-width: 100%; }
    /* 긴 코드 한 줄이 문서 전체를 가로로 밀지 않게, 코드블록 자신이 스크롤한다. */
    pre { overflow-x: auto; }
    code { font-size: 12px; }
    /* 색 단독 금지(§4.5) — 색각 이상에서 링크가 본문과 같아 보이면 안 된다. */
    a { color: var(--cn-accent-text, #0b5fff); text-decoration: underline; }
    blockquote { margin-inline: 0; padding-inline-start: 16px;
                 border-inline-start: 3px solid var(--cn-border, #d0d0d5); }
    table { border-collapse: collapse; }
    th, td { border: 1px solid var(--cn-border, #d0d0d5); padding: 4px 8px; }
    @media (prefers-color-scheme: dark) {
      body { color: var(--cn-text-primary, #f2f2f7); }
      a { color: var(--cn-accent-text, #6ea8ff); }
    }
    </style>
    """

    public static func prepare(
        html: String,
        projectRoot: String,
        loadResource: (String) async -> Result<Data, RenderResourceFailure>
    ) async -> SanitizedDocument {
        // Pass one: what does this document actually ask for? The sandbox decides that, not a
        // separate scanner — asking twice with two implementations is how the two answers
        // drift, and here the second answer would decide what gets read from disk.
        // 서식을 붙인 뒤 **같은 새니타이저를 지난다.** 우리가 넣은 것이라고 검사를 건너뛰면
        // 그 예외가 곧 우회로가 된다 — 통과하는 것을 확인하는 편이 낫다.
        let html = documentStyle + html

        var requested: [String] = []
        _ = RenderDocumentSanitizer.sanitize(html: html, projectRoot: projectRoot) { path in
            requested.append(path)
            // The result is discarded; only the question mattered.
            return .failure(.notFound)
        }

        // Read each distinct path once. A document that shows the same logo twenty times
        // should touch the disk once, not twenty times.
        var loaded: [String: Result<Data, RenderResourceFailure>] = [:]
        for path in NSOrderedSet(array: requested).compactMap({ $0 as? String }) {
            loaded[path] = await loadResource(path)
        }

        // Pass two: the real one. Every answer is already in hand, so the loader cannot block.
        return RenderDocumentSanitizer.sanitize(html: html, projectRoot: projectRoot) { path in
            // A path that reaches here but was not requested in pass one would mean the two
            // passes disagreed about the same document — treat it as unreadable rather than
            // inventing bytes.
            loaded[path] ?? .failure(.notFound)
        }
    }
}
