import Foundation

/// The box left in the document where a blocked resource sat (design 02b §3 W-15).
///
/// **HTML, not a view.** The document is drawn inside a web view (ADR-0109), so a SwiftUI box
/// has no place to be — not "no place yet", no place in principle. An earlier SwiftUI version
/// of this box could never have appeared, and the gate recorded that as an unmounted view,
/// which read as a wiring debt rather than as the design error it was.
///
/// The space is not left empty. An image that vanishes takes the layout with it and gives no
/// reason; blanking the reference instead leaves a broken-image icon, which reads as "this app
/// is broken" rather than "this was blocked". W-15 exists so the reader can tell those apart.
///
/// Everything placed in the box comes from the document being rendered, so everything placed
/// in the box is escaped. A notice that says "we blocked this" must not be the thing that gets
/// through.
public enum BlockedResourceBox {

    /// The box for a resource we could **not read** — missing or unreadable.
    ///
    /// A different sign on the same box (leader ruling 2026-08-31). Two wrong directions sit
    /// on either side of this: saying nothing, so the reader thinks the app dropped their
    /// image; and saying "blocked", so they think we refused it. The truth is neither — we
    /// tried and could not — and it is the one thing that lets them go fix the path.
    public static func unavailableHTML(detail: String, alternativeText: String?) -> String {
        box(
            glyph: "⚠",
            title: "이미지를 표시할 수 없습니다",
            accessibleKind: "표시할 수 없는 이미지",
            detail: detail,
            alternativeText: alternativeText
        )
    }

    public static func html(
        kind: BlockedResourceKind,
        detail: String,
        alternativeText: String?
    ) -> String {
        // A blocked script never had a box on the page. Drawing one invents a hole the
        // document never had.
        guard kind.showsInlinePlaceholder else {
            return ""
        }

        return box(
            glyph: "🛡",
            title: title(for: kind),
            accessibleKind: "차단된 \(kind.label)",
            detail: detail,
            alternativeText: alternativeText
        )
    }

    /// The shared box. One component, two signs — the difference is what happened, not how it
    /// is drawn, and drawing them differently would make the reader learn two shapes.
    private static func box(
        glyph: String,
        title: String,
        accessibleKind: String,
        detail: String,
        alternativeText: String?
    ) -> String {
        let alternative = (alternativeText?.isEmpty == false) ? alternativeText : nil
        // The alt text is what the author wrote *for* this slot, so it names the thing better
        // than the URL does. The URL is the fallback.
        let accessibleName = HTMLText.escapedAttribute("\(accessibleKind): \(alternative ?? detail)")

        var content = "<span style=\"\(Style.title)\">\(glyph) \(HTMLText.escaped(title))</span>"
        content += "<code style=\"\(Style.detail)\">\(HTMLText.escaped(detail))</code>"
        if let alternative {
            content += "<span style=\"\(Style.alternative)\">alt: \(HTMLText.escaped(alternative))</span>"
        }

        // Inline-level: this stands where an `<img>` stood, and an `<img>` can sit inside a
        // paragraph. A block element there splits the paragraph around it.
        return "<span class=\"cn-blocked-resource\" role=\"img\" aria-label=\"\(accessibleName)\""
            + " style=\"\(Style.box)\">\(content)</span>"
    }

    private static func title(for kind: BlockedResourceKind) -> String {
        guard kind != .outsideProjectRoot else {
            // "차단되었습니다" alone would leave the reader looking for a setting to change.
            // This one is about where the file is, and saying so is the whole explanation.
            return "프로젝트 폴더 밖의 파일은 표시하지 않습니다"
        }
        return "\(kind.label)\(subjectParticle(after: kind.label)) 차단되었습니다"
    }

    /// `이` after a final consonant, `가` otherwise.
    ///
    /// Not decoration. The earlier version always wrote `가`, so a blocked frame announced
    /// itself as "프레임가 차단되었습니다" — and nobody caught it, because that view was never
    /// mounted and so the sentence was never once read on screen. Text that no one has seen is
    /// text no one has proofread.
    private static func subjectParticle(after word: String) -> String {
        guard let last = word.unicodeScalars.last else {
            return "가"
        }
        let syllables: ClosedRange<UInt32> = 0xAC00...0xD7A3
        guard syllables.contains(last.value) else {
            // Not a Hangul syllable — a digit or Latin letter. `가` is the safer default
            // because it is what follows a vowel sound, and most such endings are read that way.
            return "가"
        }
        let hasFinalConsonant = (last.value - 0xAC00) % 28 != 0
        return hasFinalConsonant ? "이" : "가"
    }

    /// Inline styles, because the box has to look right before any host stylesheet exists.
    ///
    /// Each colour is a custom property with a literal fallback: the render host can theme the
    /// box by defining `--cn-*`, and until it does the box is still legible. A variable with no
    /// fallback would render as unstyled text today; a literal with no variable would ignore
    /// the theme forever. The CSP allows this — `style-src 'unsafe-inline'`.
    private enum Style {
        static let box = "display:inline-block;box-sizing:border-box;max-width:100%;"
            + "padding:12px;border:1px dashed var(--cn-border-strong, #9a9a9a);border-radius:6px;"
            + "background:var(--cn-bg-sidebar, #f2f2f2);color:var(--cn-text-secondary, #5f5f5f);"
            + "font:13px/1.5 -apple-system, system-ui, sans-serif;vertical-align:middle"
        static let title = "display:block"
        // The path or host is often long, and a document is not a table cell — wrapping keeps
        // it all readable where truncating would hide the part that identifies it.
        static let detail = "display:block;font-size:11px;opacity:0.85;word-break:break-all"
        static let alternative = "display:block;font-size:11px"
    }
}
