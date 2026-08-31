import Foundation

/// A document rewritten so that nothing the author wrote can reach the network.
public struct SanitizedDocument: Sendable, Hashable {
    /// The HTML handed to the web view. Every resource reference in it was written by us.
    public let html: String
    /// What was refused, for the chip and the popover (W-15).
    public let blocked: [BlockedResource]
    /// Local resources that could not be read — missing or unreadable. **Not blocks.**
    /// Separate so the sandbox notice does not claim credit for someone's typo.
    public let unavailable: [UnavailableResource]
}

/// Rewrites a document's resource references before the web view ever sees it (INV-6,
/// ADR-0109 as amended).
///
/// This is layer one of two. It rewrites **every** reference it finds: an allowed local file
/// becomes a `data:` URI *we* built from bytes we read, and everything else becomes a
/// placeholder. The property that buys is narrow and important — **after this pass, every
/// `data:` in the document is ours** — which is what lets the CSP backstop be simple.
///
/// It is layer one *because it cannot be complete*. Recognising resource references in HTML
/// means knowing every construct that carries one, and a hand-written scanner will miss
/// some. That is not a reason to skip the pass; it is the reason layer two exists. A CSP
/// meta tag catches what this misses, and this catches what CSP cannot see — the media type
/// inside a `data:` URI, which is where the SVG ruling lives.
public enum RenderDocumentSanitizer {

    /// The backstop. Allows nothing but the `data:` images this pass produced.
    ///
    /// `img-src data:` is only safe because of the rewrite above: no author-supplied
    /// `data:` survives it. Written as one line so it cannot drift out of step with the
    /// rewriting rules it depends on.
    public static let contentSecurityPolicy =
        "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src 'none'; "
        + "script-src 'none'; frame-src 'none'; connect-src 'none'"

    /// Attributes that carry a single resource reference.
    ///
    /// `xlink:href` is here because SVG still uses it and WebKit still honours it —
    /// `<svg><image xlink:href="https://…"/></svg>` fetches. The boundary rule that keeps
    /// `href` from matching inside `data-href` also keeps it from matching inside
    /// `xlink:href`, so the older spelling is invisible unless named outright.
    ///
    /// The CSP would stop such a fetch anyway, which is the second layer doing its job —
    /// but silently. Catching it here is what puts it in the blocked list, and therefore in
    /// front of the user in the W-15 chip. A block nobody can see is the failure mode the
    /// whole notice exists to prevent.
    private static let singleReferenceAttributes = ["src", "href", "xlink:href", "poster", "data"]

    /// Reads an allowed local file. Injected so the pass can be tested without a disk, and
    /// so the real read can come from the engine's render-specific path when it lands —
    /// notably *not* from the indexer's reader, whose 1MiB cap is half the render limit.
    /// Reads an allowed local file, or says why it could not.
    ///
    /// `Result`, not `Data?`. The optional collapsed every failure into one event at exactly
    /// the point where the reason was still known, and the chip downstream then had nothing to
    /// report but "blocked". Injected so the pass can be tested without a disk.
    public typealias FileLoader = (String) -> Result<Data, RenderResourceFailure>

    public static func sanitize(
        html: String,
        projectRoot: String,
        loadFile: FileLoader
    ) -> SanitizedDocument {
        var blocked: [BlockedResource] = []
        var unavailable: [UnavailableResource] = []
        var output = html

        // Script elements go first and whole. Emptying the `src` would leave an element
        // that inline content could still fill.
        output = removingElements(named: "script", from: output, blocked: &blocked)

        // `<base href="file:///Users/victim/.ssh/">` re-points every relative reference in
        // the document. The path check would still say "inside the root" — it is reasoning
        // about a base the browser has been told to ignore. There is no allowlist here,
        // only removal: an allowance cannot rest on a premise we do not control.
        output = removingVoidElements(named: "base", from: output, kind: .frame, blocked: &blocked)

        // `<meta http-equiv="refresh" content="0;url=https://evil.com">` navigates with no
        // script and no resource reference of the kind the attribute pass looks for.
        output = removingVoidElements(
            named: "meta", from: output, kind: .frame, blocked: &blocked,
            matching: { $0.range(of: "http-equiv", options: .caseInsensitive) != nil
                && $0.range(of: "refresh", options: .caseInsensitive) != nil }
        )

        output = rewritingAttributes(
            in: output,
            projectRoot: projectRoot,
            loadFile: loadFile,
            blocked: &blocked,
            unavailable: &unavailable
        )

        output = rewritingCSSURLs(
            in: output,
            projectRoot: projectRoot,
            loadFile: loadFile,
            blocked: &blocked,
            unavailable: &unavailable
        )

        return SanitizedDocument(
            html: injectingPolicy(into: output), blocked: blocked, unavailable: unavailable
        )
    }

    // MARK: 요소 제거

    /// Removes an element and its content entirely.
    private static func removingElements(
        named name: String,
        from html: String,
        blocked: inout [BlockedResource]
    ) -> String {
        var result = ""
        var rest = Substring(html)

        while let open = rest.range(of: "<\(name)", options: [.caseInsensitive]) {
            result += rest[rest.startIndex..<open.lowerBound]
            let afterOpen = rest[open.lowerBound...]

            guard let close = afterOpen.range(of: "</\(name)>", options: [.caseInsensitive]) else {
                // An unclosed script swallows the rest of the document rather than leaving
                // a fragment whose meaning depends on the browser's recovery.
                blocked.append(BlockedResource(kind: .script, detail: RenderSandboxPolicy.inlineDetail))
                return result
            }

            let element = afterOpen[afterOpen.startIndex..<close.upperBound]
            blocked.append(BlockedResource(kind: .script, detail: sourceAttribute(in: String(element))
                ?? RenderSandboxPolicy.inlineDetail))
            rest = afterOpen[close.upperBound...]
        }

        return result + rest
    }

    /// Removes elements that have no closing tag, optionally only those matching a test.
    private static func removingVoidElements(
        named name: String,
        from html: String,
        kind: BlockedResourceKind,
        blocked: inout [BlockedResource],
        matching predicate: ((String) -> Bool)? = nil
    ) -> String {
        var result = ""
        var rest = Substring(html)

        while let open = rest.range(of: "<\(name)", options: [.caseInsensitive]) {
            guard let close = rest[open.lowerBound...].firstIndex(of: ">") else {
                break
            }
            let element = String(rest[open.lowerBound...close])

            // `<basefont>` starts with `<base` too; only a real tag boundary counts.
            let afterName = element.dropFirst(name.count + 1).first
            let isWholeTag = afterName.map { $0.isWhitespace || $0 == ">" || $0 == "/" } ?? false

            guard isWholeTag, predicate?(element) ?? true else {
                result += rest[rest.startIndex...close]
                rest = rest[rest.index(after: close)...]
                continue
            }

            result += rest[rest.startIndex..<open.lowerBound]
            blocked.append(BlockedResource(
                kind: kind,
                detail: attributeValue(named: "href", in: element)
                    ?? attributeValue(named: "content", in: element)
                    ?? "<\(name)>"
            ))
            rest = rest[rest.index(after: close)...]
        }

        return result + rest
    }

    private static func sourceAttribute(in element: String) -> String? {
        guard let value = attributeValue(named: "src", in: element) else {
            return nil
        }
        return RenderSandboxPolicy.host(of: value) ?? value
    }

    // MARK: 속성 재작성

    private static func rewritingAttributes(
        in html: String,
        projectRoot: String,
        loadFile: FileLoader,
        blocked: inout [BlockedResource],
        unavailable: inout [UnavailableResource]
    ) -> String {
        var output = html

        for attribute in singleReferenceAttributes {
            output = rewritingAttribute(
                named: attribute,
                in: output,
                projectRoot: projectRoot,
                loadFile: loadFile,
                blocked: &blocked,
                unavailable: &unavailable
            )
        }
        // `srcset` carries a comma-separated list; one bad entry is enough, so the whole
        // attribute is dropped rather than partly rewritten.
        output = strippingAttribute(named: "srcset", in: output, blocked: &blocked)
        // `<iframe srcdoc="...">` is a whole document inside an attribute. Frames are
        // blocked anyway, but the attribute would carry its content past a pass that only
        // looks at URLs.
        output = strippingAttribute(named: "srcdoc", in: output, blocked: &blocked)
        return output
    }

    private static func rewritingAttribute(
        named attribute: String,
        in html: String,
        projectRoot: String,
        loadFile: FileLoader,
        blocked: inout [BlockedResource],
        unavailable: inout [UnavailableResource]
    ) -> String {
        rewritingAttributeValues(named: attribute, in: html) { element, value in
            // An anchor's href is navigation, not a fetch — nothing is loaded until the
            // user clicks, and W-14 defines what a click does (open in this tab, hand to
            // the browser, or refuse with a status message). Inlining it as `data:` would
            // destroy the link, and blanking it would break in-document anchors. The web
            // view must intercept navigation instead; that is the render view's job, and
            // the CSP forbids the page loading anything on its own regardless.
            guard tagName(of: element) != "a" else {
                return .value(value)
            }

            // A bare fragment points inside this document and fetches nothing —
            // `<a href="#top">`, `<use href="#icon">`. Running it through the path rules
            // resolves it against the project root, finds no such file, and blanks a
            // working in-document link.
            guard !value.hasPrefix("#") else {
                return .value(value)
            }

            let decision = RenderSandboxPolicy.decide(
                elementKind(for: element, attribute: attribute, value: value),
                projectRoot: projectRoot
            )

            switch decision {
            case .allowInlineData:
                // Ours only after this pass: an author's `data:` reaches here too, and it
                // is allowed only because `decide` already checked the media type.
                return .value(value)

            case .allowFile(let resolvedPath):
                switch loadFile(resolvedPath) {
                case .success(let data):
                    return .value(
                        "data:\(mediaType(forPath: resolvedPath));base64,\(data.base64EncodedString())"
                    )

                case .failure(let failure):
                    // The reason decides what the reader is told. Before this, every failure
                    // was recorded as `outsideProjectRoot` — so a 3MB image *inside* the
                    // project reported that it was outside it.
                    if let kind = blockedKind(for: failure) {
                        blocked.append(BlockedResource(kind: kind, detail: value))
                        if kind.showsInlinePlaceholder, tagName(of: element) == "img" {
                            return .element(BlockedResourceBox.html(
                                kind: kind,
                                detail: value,
                                alternativeText: attributeValue(named: "alt", in: element)
                            ))
                        }
                    } else {
                        unavailable.append(UnavailableResource(path: value, failure: failure))
                        // Not blocked, but not silent either. Vanishing is the failure W-15
                        // exists to prevent; claiming we blocked it is the opposite lie.
                        if tagName(of: element) == "img" {
                            return .element(BlockedResourceBox.unavailableHTML(
                                detail: value,
                                alternativeText: attributeValue(named: "alt", in: element)
                            ))
                        }
                    }
                    return .value("")
                }

            case .unavailable(let detail):
                // 못 읽은 것이지 막은 것이 아니다. 칩에는 안 오르고, 자리에는 남는다.
                unavailable.append(UnavailableResource(path: detail, failure: .notFound))
                if tagName(of: element) == "img" {
                    return .element(BlockedResourceBox.unavailableHTML(
                        detail: detail,
                        alternativeText: attributeValue(named: "alt", in: element)
                    ))
                }
                return .value("")

            case .block(let kind, let detail):
                blocked.append(BlockedResource(kind: kind, detail: detail))

                // An image that occupied space leaves a box saying what stood there (W-15).
                // Only `img`: it is void, so the element is the whole thing and replacing it
                // leaves nothing dangling. `iframe` and `object` have closing tags that this
                // scanner does not pair, and a box followed by a stray `</iframe>` would make
                // the frame's fallback content visible — a limit recorded in the limit tests.
                if kind.showsInlinePlaceholder, tagName(of: element) == "img" {
                    return .element(BlockedResourceBox.html(
                        kind: kind,
                        detail: detail,
                        alternativeText: attributeValue(named: "alt", in: element)
                    ))
                }

                // Emptied rather than left alone. A reference we refuse must not survive in
                // any form the web view could act on.
                return .value("")
            }
        }
    }

    /// Which sandbox question this attribute asks, from the element it sits on.
    private static func elementKind(for element: String, attribute: String, value: String) -> RenderedElement {
        let tag = tagName(of: element)
        switch tag {
        case "img", "source", "video", "audio", "input":
            return .image(source: value)
        case "iframe", "object", "embed", "frame":
            return .frame(source: value)
        case "link":
            // `rel="stylesheet"` is the common case; anything else linked is treated the
            // same way, because a link we do not understand is not one to follow.
            return element.range(of: "font", options: .caseInsensitive) != nil
                ? .font(source: value)
                : .stylesheet(source: value)
        case "a":
            // Unreachable: `a` is excluded before we get here. Kept exhaustive so adding a
            // tag cannot silently fall into the default.
            return .image(source: value)
        default:
            return .image(source: value)
        }
    }

    // MARK: CSS url()

    private static func rewritingCSSURLs(
        in html: String,
        projectRoot: String,
        loadFile: FileLoader,
        blocked: inout [BlockedResource],
        unavailable: inout [UnavailableResource]
    ) -> String {
        var result = ""
        var rest = Substring(html)

        while let open = rest.range(of: "url(", options: [.caseInsensitive]) {
            result += rest[rest.startIndex..<open.lowerBound]
            let afterOpen = rest[open.upperBound...]

            guard let close = afterOpen.firstIndex(of: ")") else {
                blocked.append(BlockedResource(kind: .remoteStylesheet, detail: "url("))
                return result
            }

            let raw = String(afterOpen[afterOpen.startIndex..<close])
            let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            let decision = RenderSandboxPolicy.decide(
                .image(source: value),
                projectRoot: projectRoot
            )

            switch decision {
            case .allowInlineData:
                result += "url(\(raw))"
            case .allowFile(let resolvedPath):
                switch loadFile(resolvedPath) {
                case .success(let data):
                    result += "url(data:\(mediaType(forPath: resolvedPath));base64,\(data.base64EncodedString()))"
                case .failure(let failure):
                    if let kind = blockedKind(for: failure) {
                        blocked.append(BlockedResource(kind: kind, detail: value))
                    } else {
                        unavailable.append(UnavailableResource(path: value, failure: failure))
                    }
                    result += "url()"
                }
            case .unavailable(let detail):
                unavailable.append(UnavailableResource(path: detail, failure: .notFound))
                result += "url()"
            case .block(let kind, let detail):
                blocked.append(BlockedResource(kind: kind, detail: detail))
                result += "url()"
            }

            rest = afterOpen[afterOpen.index(after: close)...]
        }

        return result + rest
    }

    /// Which W-15 row a read failure belongs on, or `nil` when it belongs on none.
    ///
    /// `nil` is not "ignore it" — the caller records those as `unavailable` instead. The split
    /// is the point: **W-15 lists what the sandbox refused.** A file that is missing was not
    /// refused, and putting it on that list tells the reader we blocked something we did not,
    /// which is the mirror image of the silent blocking W-15 exists to prevent.
    ///
    /// ⚠ Where `notFound`/`notReadable` are shown in the document is an open decision
    /// (asked 2026-08-31). Until it lands they are carried, not classified — assigning them a
    /// row now would bury the question inside a value nobody would think to re-examine.
    private static func blockedKind(for failure: RenderResourceFailure) -> BlockedResourceKind? {
        switch failure {
        case .tooLarge:
            return .tooLarge
        case .invalidPath:
            // The engine refused the path itself, which is exactly INV-6's root restriction.
            return .outsideProjectRoot
        case .notFound, .notReadable:
            return nil
        }
    }

    // MARK: CSP

    private static func injectingPolicy(into html: String) -> String {
        let meta = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(contentSecurityPolicy)\">"

        if let head = html.range(of: "<head>", options: .caseInsensitive) {
            return html.replacingCharacters(in: head, with: "<head>" + meta)
        }
        // A fragment without a head still gets the policy — markdown renders to one.
        return meta + html
    }

    // MARK: 스캐닝

    /// Rewrites every value of `attribute`, letting the caller decide each new value.
    ///
    /// A scanner rather than a parser, and that limit is the whole reason for the CSP
    /// backstop.
    ///
    /// What it does handle, measured rather than assumed: quoted and unquoted values,
    /// whitespace around `=`, uppercase tags, newlines inside a tag, `>` inside a quoted
    /// value, and references written inside comments or CDATA (those are rewritten too,
    /// which is harmless). `RenderDocumentSanitizerLimitTests` records what it does not.
    /// What the caller wants done with the element it was shown.
    ///
    /// Blanking an attribute is not always enough. A blocked `<img src="">` is a broken-image
    /// icon — the reference is gone but the hole it leaves says "this app is broken" rather
    /// than "this was blocked", which is the confusion W-15 exists to prevent. For those the
    /// caller replaces the whole element with a box that says what was there.
    enum Rewrite {
        case value(String)
        case element(String)
    }

    private static func rewritingAttributeValues(
        named attribute: String,
        in html: String,
        transform: (_ element: String, _ value: String) -> Rewrite
    ) -> String {
        var result = ""
        var rest = Substring(html)

        while let tagOpen = rest.firstIndex(of: "<") {
            // The closing `>` is found with quote state tracked. Taking the first `>`
            // stops the element early on `<img alt="a>b" src="…">`, and everything after
            // the fake end — including the real `src` — is never examined. Measured: that
            // reference survived the pass untouched.
            guard let tagClose = closingBracket(in: rest, from: tagOpen) else {
                break
            }
            let element = String(rest[tagOpen...tagClose])
            result += rest[rest.startIndex..<tagOpen]

            if let value = attributeValue(named: attribute, in: element) {
                switch transform(element, value) {
                case .element(let replacement):
                    result += replacement
                case .value(let replacement):
                    // Replaced by range rather than by string: the same value can appear in two
                    // attributes (`src` and `data-src`), and a blind substitution would rewrite
                    // whichever came first.
                    result += replacingAttribute(named: attribute, in: element, with: replacement) ?? element
                }
            } else {
                result += element
            }

            rest = rest[rest.index(after: tagClose)...]
        }

        return result + rest
    }

    /// The `>` that actually ends this tag, skipping any inside quoted values.
    private static func closingBracket(in text: Substring, from start: Substring.Index) -> Substring.Index? {
        var index = text.index(after: start)
        var quote: Character?

        while index < text.endIndex {
            let character = text[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func strippingAttribute(
        named attribute: String,
        in html: String,
        blocked: inout [BlockedResource]
    ) -> String {
        rewritingAttributeValues(named: attribute, in: html) { _, value in
            // Not parsed into candidates: a partly-rewritten list is a list with a hole in
            // it, and the browser picks the entry it likes.
            blocked.append(BlockedResource(kind: .remoteImage, detail: value))
            return .value("")
        }
    }

    /// Replaces just this attribute's value, leaving every other occurrence alone.
    private static func replacingAttribute(
        named attribute: String,
        in element: String,
        with replacement: String
    ) -> String? {
        guard let found = attributeRange(named: attribute, in: element) else {
            return nil
        }
        return element.replacingCharacters(
            in: found.whole,
            with: "\(attribute)=\"\(replacement)\""
        )
    }

    static func attributeValue(named attribute: String, in element: String) -> String? {
        guard let found = attributeRange(named: attribute, in: element) else {
            return nil
        }
        return String(element[found.value])
    }

    /// Finds an attribute by name, as a whole word.
    ///
    /// The name has to start at an attribute boundary. Searching for `src="` alone also
    /// matches inside `data-src="`, and that is not a cosmetic slip: with
    /// `<img data-src="https://evil.com/x" src="https://evil.com/x">` the pass rewrote the
    /// decoy and **left the real `src` remote**. A document chooses its own attribute names,
    /// so the scanner cannot assume they are the ones it expects.
    private static func attributeRange(
        named attribute: String,
        in element: String
    ) -> (whole: Range<String.Index>, value: Range<String.Index>)? {
        var searchStart = element.startIndex

        while let nameRange = element.range(
            of: attribute, options: .caseInsensitive, range: searchStart..<element.endIndex
        ) {
            searchStart = nameRange.upperBound

            // A real attribute starts at a boundary. `src` also occurs inside `data-src`,
            // and rewriting the decoy while leaving the real one remote is a bypass, not a
            // cosmetic slip — measured on `<img data-src="…" src="…">`.
            let precedes = nameRange.lowerBound == element.startIndex
                ? nil
                : element[element.index(before: nameRange.lowerBound)]
            guard precedes.map({ $0.isWhitespace }) ?? false else {
                continue
            }

            // Whitespace is legal on both sides of `=`; `src = "…"` is the same attribute.
            var cursor = nameRange.upperBound
            while cursor < element.endIndex, element[cursor].isWhitespace {
                cursor = element.index(after: cursor)
            }
            guard cursor < element.endIndex, element[cursor] == "=" else {
                continue
            }
            cursor = element.index(after: cursor)
            while cursor < element.endIndex, element[cursor].isWhitespace {
                cursor = element.index(after: cursor)
            }
            guard cursor < element.endIndex else {
                continue
            }

            let quote = element[cursor]
            if quote == "\"" || quote == "'" {
                let valueStart = element.index(after: cursor)
                guard let valueEnd = element[valueStart...].firstIndex(of: quote) else {
                    continue
                }
                return (nameRange.lowerBound..<element.index(after: valueEnd), valueStart..<valueEnd)
            }

            // Unquoted: runs to whitespace or the tag's end. HTML allows it, and an author
            // writing `src=https://evil.com/x` was invisible to a quote-only scanner.
            let valueEnd = element[cursor...].firstIndex { $0.isWhitespace || $0 == ">" }
                ?? element.endIndex
            return (nameRange.lowerBound..<valueEnd, cursor..<valueEnd)
        }
        return nil
    }

    static func tagName(of element: String) -> String {
        let withoutBracket = element.dropFirst()
        let name = withoutBracket.prefix { $0.isLetter || $0.isNumber }
        return name.lowercased()
    }

    /// The media type for an inlined file, from its extension.
    ///
    /// Only the types the ruling allows. Anything else never reaches here — `decide` has
    /// already refused it — and defaulting to `application/octet-stream` keeps a mistake
    /// from becoming a rendered image of an unexpected kind.
    static func mediaType(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "css": return "text/css"
        default: return "application/octet-stream"
        }
    }
}
