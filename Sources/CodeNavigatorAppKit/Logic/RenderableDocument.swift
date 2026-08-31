import Foundation

/// Which files the render surface can draw (design 02b §3 W-14, REQ-013 AC-1·2).
///
/// **One answer, asked from three places.** The link decision needs it (open a clicked file
/// rendered or as source), the toolbar needs it (the `렌더` button is disabled on a file that
/// cannot be rendered), and the status bar needs it to say why. Three copies of `["md","html"]`
/// would agree today and diverge the day one of them grows — and the symptom would be a link
/// that opens a rendered file the toolbar insists cannot be rendered, with neither side
/// admitting it is the wrong one.
public enum RenderableDocument {

    /// From design 02b: `.md · .html 만 지원`. Lowercased; comparison folds case.
    public static let extensions: Set<String> = ["md", "html"]

    public static func isRenderable(relativePath: String) -> Bool {
        extensions.contains((relativePath as NSString).pathExtension.lowercased())
    }

    /// The status-bar line for a file that cannot be rendered (W-14).
    ///
    /// Built from `extensions` rather than written out. The design's wording *names* the
    /// extensions, so a hand-written copy is a second list — the exact thing this type exists
    /// to prevent, hiding in a string.
    public static var unsupportedMessage: String {
        let named = extensions.sorted().map { ".\($0)" }.joined(separator: " · ")
        return "✕ 이 파일은 렌더할 수 없습니다 (\(named) 만 지원)"
    }
}
