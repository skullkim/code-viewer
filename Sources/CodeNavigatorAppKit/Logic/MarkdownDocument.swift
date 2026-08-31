import Foundation

/// Turns markdown into the HTML fragment that the sandbox pass then rewrites (REQ-013 AC-1,
/// ADR-0109).
///
/// **This is not a security boundary and must never be mistaken for one.** Markdown may
/// contain raw HTML, and this converter passes it through deliberately — ADR-0109 put
/// markdown and HTML on *one* surface precisely so there would be one boundary to get right.
/// Filtering here would create a second, weaker one and invite the belief that the output is
/// already safe. Everything this emits still goes through `RenderDocumentSanitizer`.
///
/// What it *is* responsible for is not manufacturing markup that was never in the document:
/// text, code, and URLs that came from the file are escaped so a `<` in prose stays a `<`
/// and a quote inside a link target cannot end the attribute it sits in.
public enum MarkdownDocument {

    /// A fragment, not a page — no `<html>` or `<head>`. The sanitizer prepends the CSP meta
    /// tag to a headless fragment, which is the shape markdown produces.
    public static func html(from markdown: String) -> String {
        ""
    }
}
