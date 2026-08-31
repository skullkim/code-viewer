import Foundation

/// What a click on a link in the rendered document does (design 02b §3 W-14, INV-6).
public enum RenderNavigation: Sendable, Hashable {
    /// Scroll within the document. Fetches nothing.
    case scrollToFragment(String)
    /// Open the file in this tab, exactly as clicking it in the tree would.
    case openInTab(relativePath: String, asRendered: Bool)
    /// Hand it to the default browser. Remote content is never drawn inside the app (INV-6).
    case openInBrowser(url: String)
    case refuse(RenderNavigationRefusal)
}

/// Why a link was not followed.
///
/// Three cases, kept apart on purpose. Collapsing them into one "cannot open" leaves the
/// reader unable to tell whether to fix a typo, move a file, or stop expecting it to work —
/// the same reason masking a failure reason is refused everywhere else in this build.
public enum RenderNavigationRefusal: Sendable, Hashable {
    case outsideProjectRoot
    case notFound
    case unsupportedScheme

    /// Wording from design 02b §3 W-14.
    public var statusMessage: String {
        switch self {
        case .outsideProjectRoot: return "✕ 프로젝트 폴더 밖의 파일은 열 수 없습니다"
        case .notFound: return "✕ 파일을 찾을 수 없습니다"
        case .unsupportedScheme: return "✕ 이 링크는 열 수 없습니다"
        }
    }

    public var displaySeconds: Double { 3 }
}

/// Decides what a link click does, before the web view is allowed to act on it.
///
/// **This is the layer the preprocessing pass promised.** The sanitizer leaves `<a href>`
/// alone and says so in a comment — navigation is not a fetch, and blanking it would break
/// in-document anchors. That comment points here. Until this existed, the pointer led
/// nowhere, and a comment that names a layer that does not exist reads as protection that
/// does not exist either.
public enum RenderNavigationPolicy {

    /// Only these are handed outward. An allowlist, not a list of dangerous schemes —
    /// enumerating the dangerous ones means the one nobody thought of is allowed, and on a
    /// security surface that is the same as having no rule.
    private static let browserSchemes: Set<String> = ["http", "https"]

    public static func decide(
        href: String,
        documentRelativePath: String,
        projectRoot: String
    ) -> RenderNavigation {
        let target = normalised(href)

        guard !target.isEmpty else {
            return .refuse(.unsupportedScheme)
        }
        if target.hasPrefix("#") {
            let fragment = String(target.dropFirst())
            return .scrollToFragment(fragment.removingPercentEncoding ?? fragment)
        }
        // `//host/path` looks like a path and is not one. Read as local it becomes "file not
        // found", and the reader is told the wrong thing about a remote reference.
        if target.hasPrefix("//") {
            return .refuse(.unsupportedScheme)
        }
        if let scheme = scheme(of: target) {
            return browserSchemes.contains(scheme)
                ? .openInBrowser(url: target)
                : .refuse(.unsupportedScheme)
        }
        return local(target, documentRelativePath: documentRelativePath, projectRoot: projectRoot)
    }

    /// The same decision, for the URL the web view hands us instead of the raw attribute.
    ///
    /// WebKit resolves an `href` against the document's base before the navigation delegate
    /// sees it, so what arrives is a `URL`, not what the author typed. A `file:` URL here is
    /// therefore ambiguous — it may be a relative link WebKit resolved, or a `file://` the
    /// author wrote — and it is treated as a local path either way, because **the root check
    /// answers both cases correctly**. The reason reported for an author-written `file://`
    /// outside the root becomes `outsideProjectRoot` rather than `unsupportedScheme`; both
    /// refuse, and the one that survives is the more specific truth.
    ///
    /// ⚠ Which URLs actually arrive here depends on the `baseURL` the document is loaded
    /// with, and that has **not been measured yet** — it needs a running web view. Until it
    /// is, this mapping is a reasoned guess and is written to fail closed either way.
    public static func decide(
        navigationURL url: URL,
        documentRelativePath: String,
        projectRoot: String
    ) -> RenderNavigation {
        // A fragment reaches us attached to the document it came from — the web view resolves
        // `href="#anchor"` against the base before we see it. **Measured** (2026-08-31,
        // `scripts/spike-render-host.swift`): with a file base it arrives as
        // `file:///…/guide.md#anchor`, and with `baseURL: nil` as `about:blank#anchor`.
        //
        // Neither shape can be read as "open this path". The first would reopen the document
        // the reader is already in and throw away their scroll position; the second would be
        // refused as an unknown scheme, so in-document links would simply stop working.
        if let fragment = url.fragment, !fragment.isEmpty, isSameDocument(url, documentRelativePath, projectRoot) {
            // Decoded, because the element id in the document is not encoded. A Korean
            // heading arrives as `%EC%84%A4%EC%B9%98` and would match nothing (measured —
            // and these documents are full of Korean headings).
            return .scrollToFragment(fragment.removingPercentEncoding ?? fragment)
        }
        guard url.isFileURL else {
            return decide(
                href: url.absoluteString,
                documentRelativePath: documentRelativePath,
                projectRoot: projectRoot
            )
        }
        return local(url.path, documentRelativePath: documentRelativePath, projectRoot: projectRoot)
    }

    /// Whether this URL addresses the document currently on screen.
    ///
    /// Compared through the same resolver the sandbox uses, not by spelling: the base the web
    /// view hands back can differ from the path we passed in (`/tmp` against `/private/tmp`),
    /// and comparing strings would call the same file two different files — the exact mistake
    /// `resolvedPathInsideRoot` exists to prevent.
    private static func isSameDocument(
        _ url: URL,
        _ documentRelativePath: String,
        _ projectRoot: String
    ) -> Bool {
        // `baseURL: nil` leaves the web view no document to resolve against, so it uses
        // `about:blank`. There is no other document it could mean.
        if url.absoluteString.hasPrefix("about:blank") {
            return true
        }
        guard url.isFileURL else {
            return false
        }
        let documentPath = (projectRoot as NSString).appendingPathComponent(documentRelativePath)
        guard
            let target = RenderSandboxPolicy.resolvedPathInsideRoot(path: url.path, projectRoot: projectRoot),
            let current = RenderSandboxPolicy.resolvedPathInsideRoot(path: documentPath, projectRoot: projectRoot)
        else {
            return false
        }
        return target == current
    }

    // MARK: 로컬 경로

    private static func local(
        _ target: String,
        documentRelativePath: String,
        projectRoot: String
    ) -> RenderNavigation {
        // A query or fragment addresses a position, not a different file.
        let path = String(target.prefix { $0 != "#" && $0 != "?" })
        guard !path.isEmpty else {
            return .refuse(.unsupportedScheme)
        }
        let decoded = path.removingPercentEncoding ?? path

        // Relative to the document, not to the root: `OTHER.md` beside `docs/guide.md` is
        // `docs/OTHER.md`, and resolving against the root would look for it in the wrong place.
        let absolute: String
        if decoded.hasPrefix("/") {
            absolute = decoded
        } else {
            let directory = (projectRoot as NSString)
                .appendingPathComponent((documentRelativePath as NSString).deletingLastPathComponent)
            absolute = (directory as NSString).appendingPathComponent(decoded)
        }

        // Containment is decided **before** the file system is touched, and the order is the
        // point. Asking "does it exist" first turns the refusal message into an oracle: a
        // document could link to `../../etc/shadow`, read `찾을 수 없습니다` or
        // `프로젝트 폴더 밖`, and learn what exists outside the project one link at a time.
        // A refusal reason is output, and output from a check on an untrusted path is a
        // channel. So a path that does not even claim to be inside the root is refused
        // without ever being looked up.
        //
        // Purely lexical — no `realpath` — because `realpath` has no answer for a path that
        // does not exist, which is exactly the case being decided here.
        let normalisedRoot = lexicallyNormalised(projectRoot)
        let boundary = normalisedRoot.hasSuffix("/") ? normalisedRoot : normalisedRoot + "/"
        guard lexicallyNormalised(absolute).hasPrefix(boundary) else {
            return .refuse(.outsideProjectRoot)
        }

        // Only now, and only for paths that claim to be inside the project. Whether a file
        // exists inside your own project is not a secret.
        guard FileManager.default.fileExists(atPath: absolute) else {
            return .refuse(.notFound)
        }

        // The lexical check above cannot see symlinks — `docs/link.md` may sit inside the root
        // and point anywhere. This is the same containment check the resource sandbox uses,
        // with `realpath` on both sides, so navigation and fetching cannot disagree about
        // where the root is.
        guard
            let resolved = RenderSandboxPolicy.resolvedPathInsideRoot(path: absolute, projectRoot: projectRoot),
            let resolvedRoot = RenderSandboxPolicy.resolvedRoot(projectRoot)
        else {
            return .refuse(.outsideProjectRoot)
        }

        let relative = String(resolved.dropFirst(resolvedRoot.count).drop { $0 == "/" })
        // Asked, not decided here. "Can this be rendered" is one question with one answer
        // (`RenderableDocument`), and the toolbar asks it too.
        return .openInTab(relativePath: relative, asRendered: RenderableDocument.isRenderable(relativePath: relative))
    }

    /// `.` and `..` folded away without asking the file system anything.
    ///
    /// Deliberately not `standardizingPath`: that one resolves symlinks for paths that exist,
    /// which would make this check's answer depend on what is on disk — the dependency this
    /// step exists to avoid.
    private static func lexicallyNormalised(_ path: String) -> String {
        var components: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                }
            default:
                components.append(String(part))
            }
        }
        return "/" + components.joined(separator: "/")
    }

    // MARK: 정규화

    /// The href as a browser would read it before deciding the scheme.
    ///
    /// Tabs, newlines and carriage returns are **dropped** from URLs by browsers rather than
    /// rejected, which is what makes `java&#10;script:` a classic bypass: a checker that reads
    /// the raw text sees no `javascript:` scheme, and the browser does. Our answer and the
    /// browser's must come from the same string, so the same characters are removed here.
    private static func normalised(_ href: String) -> String {
        href
            .filter { $0 != "\n" && $0 != "\r" && $0 != "\t" && $0 != "\0" }
            .trimmingCharacters(in: .whitespaces)
    }

    /// The scheme, if the string starts with one. `[A-Za-z][A-Za-z0-9+.-]*:` per RFC 3986.
    private static func scheme(of target: String) -> String? {
        guard let first = target.first, first.isLetter else {
            return nil
        }
        var scheme = ""
        for character in target {
            if character == ":" {
                return scheme.lowercased()
            }
            guard character.isLetter || character.isNumber || "+-.".contains(character) else {
                // A `/` or anything else before a colon means this was a path all along —
                // `docs/a:b.md` is a file, not a `docs` scheme.
                return nil
            }
            scheme.append(character)
        }
        return nil
    }
}
