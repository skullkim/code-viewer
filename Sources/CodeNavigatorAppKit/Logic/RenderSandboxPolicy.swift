import Foundation
import Darwin

/// What kind of thing the render view refused to load (design 02b §3 W-15).
public enum BlockedResourceKind: String, Sendable, Hashable, CaseIterable {
    case remoteImage
    case script
    case remoteStylesheet
    case remoteFont
    case frame
    case outsideProjectRoot

    /// The wording W-15's popover uses. The screen and the code say the same words.
    public var label: String {
        switch self {
        case .remoteImage: return "원격 이미지"
        case .script: return "스크립트"
        case .remoteStylesheet: return "원격 스타일시트"
        case .remoteFont: return "원격 폰트"
        case .frame: return "프레임"
        case .outsideProjectRoot: return "프로젝트 밖 파일"
        }
    }

    /// Whether a placeholder is drawn where the element sat.
    ///
    /// Only the ones that occupied space. A blocked script never had a box on the page, and
    /// drawing one for it would invent a hole the document never had (W-15).
    public var showsInlinePlaceholder: Bool {
        switch self {
        case .remoteImage, .outsideProjectRoot, .frame:
            return true
        case .script, .remoteStylesheet, .remoteFont:
            return false
        }
    }
}

/// An element the renderer found in the document.
public enum RenderedElement: Sendable, Hashable {
    /// `nil` source means inline — a `<script>` with a body rather than a `src`.
    case image(source: String?)
    case script(source: String?)
    case stylesheet(source: String?)
    case font(source: String?)
    /// `iframe`, `object`, `embed`.
    case frame(source: String?)
}

/// Whether an element loads, and if not, under which heading it is reported.
public enum SandboxDecision: Sendable, Hashable {
    /// A local file proven inside the root. **The loader must open this exact path** and
    /// not the reference it came from: checking one path and opening another leaves a
    /// window in which a file appears between the two, which makes the check meaningless.
    case allowFile(resolvedPath: String)
    /// Already inline. There is nothing to fetch and nothing to confine.
    case allowInlineData
    case block(kind: BlockedResourceKind, detail: String)

    public var isBlocked: Bool {
        if case .block = self { return true }
        return false
    }
}

/// INV-6, as a decision per element.
///
/// **Blocking is the default and it is not negotiable** — the requirement says so in those
/// words. So this function is written to fail closed: anything it cannot prove is a local
/// file inside the open project's root is blocked. A rule that has to choose between
/// showing something it does not understand and hiding something harmless hides it, because
/// the two mistakes do not cost the same. A hidden image is visible in the chip, the
/// popover and a placeholder; a loaded one that should not have been is silent.
public enum RenderSandboxPolicy {

    static let inlineDetail = "(인라인)"

    /// The only `data:` media types that load.
    ///
    /// Named individually rather than accepting everything under `image/`. SVG is markup
    /// that can carry script, and whether `<img>` neutralises it depends on the renderer —
    /// a guarantee we do not control. INV-6 makes blocking the default, so an allowance is
    /// not built on a premise we cannot check. A new format joins this list with a reason.
    static let allowedRasterDataMediaTypes: Set<String> = [
        "image/png", "image/jpeg", "image/gif", "image/webp",
    ]

    /// Whether a `data:` URI carries one of the raster types above.
    static func isAllowedRasterDataImage(_ source: String) -> Bool {
        guard let mediaType = dataMediaType(of: source) else {
            // No media type at all defaults to text/plain per RFC 2397 — not an image.
            return false
        }
        return allowedRasterDataMediaTypes.contains(mediaType)
    }

    /// The media type of a `data:` URI, lowercased, without parameters.
    static func dataMediaType(of source: String) -> String? {
        guard let colon = source.firstIndex(of: ":"),
              source[source.startIndex..<colon].lowercased() == "data"
        else {
            return nil
        }
        let rest = source[source.index(after: colon)...]
        guard let comma = rest.firstIndex(of: ",") else {
            return nil
        }
        // `image/png;base64` -> `image/png`
        let header = rest[rest.startIndex..<comma]
        let mediaType = header.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
        return mediaType.trimmingCharacters(in: .whitespaces).lowercased()
    }

    public static func decide(
        _ element: RenderedElement,
        projectRoot: String
    ) -> SandboxDecision {
        switch element {
        case .script(let source):
            // Never loaded, local or not. INV-6 blocks script *execution*, and a local
            // script inside the project executes just as freely as a remote one.
            return .block(kind: .script, detail: detail(for: source))

        case .frame(let source):
            // A frame is a document inside the document; allowing one would hand every rule
            // here to whatever it contains.
            return .block(kind: .frame, detail: detail(for: source))

        case .image(let source):
            return decideResource(source, remoteKind: .remoteImage, projectRoot: projectRoot)

        case .stylesheet(let source):
            return decideResource(source, remoteKind: .remoteStylesheet, projectRoot: projectRoot)

        case .font(let source):
            return decideResource(source, remoteKind: .remoteFont, projectRoot: projectRoot)
        }
    }

    /// Images, stylesheets and fonts differ only in which heading they are reported under.
    private static func decideResource(
        _ source: String?,
        remoteKind: BlockedResourceKind,
        projectRoot: String
    ) -> SandboxDecision {
        guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // No source at all. Nothing to load and nothing to allow.
            return .block(kind: remoteKind, detail: inlineDetail)
        }

        // `//evil.com/x.png` inherits the page's scheme, so it is a network reference that
        // looks exactly like a path. Without this it falls through to the path branch,
        // resolves under the project root and is *allowed* — measured, and the reason this
        // check exists rather than being assumed unnecessary.
        if source.hasPrefix("//") {
            return .block(kind: remoteKind, detail: protocolRelativeHost(of: source))
        }

        if let scheme = scheme(of: source) {
            if scheme == "data" {
                // Leader ruling: raster `data:` images load, everything else does not.
                // INV-6 blocks two things — network and execution — and a raster data URI
                // reaches neither, while inlined diagrams are a real markdown pattern that
                // blocking would break.
                guard remoteKind == .remoteImage, isAllowedRasterDataImage(source) else {
                    return .block(kind: remoteKind, detail: dataMediaType(of: source) ?? scheme)
                }
                return .allowInlineData
            }
            guard scheme == "file" else {
                // Every other non-file scheme is blocked, not only the ones that reach the
                // network. An allowlist that grows by exception stops being one.
                return .block(kind: remoteKind, detail: host(of: source) ?? scheme)
            }
        }

        let path = filePath(from: source)
        guard let resolved = resolvedPathInsideRoot(path: path, projectRoot: projectRoot) else {
            return .block(kind: .outsideProjectRoot, detail: source)
        }
        return .allowFile(resolvedPath: resolved)
    }

    /// The real path of a reference, if it is provably a file inside the project root.
    ///
    /// **This is the security boundary, and it is deliberately separate from tab identity.**
    /// The engine's `ProjectWorkspaceEngine` answers "are these two paths the same project"
    /// (REQ-012 AC-5); this one answers "may this document read this file". They must fail in
    /// opposite directions — identity is forgiving when a path cannot be resolved, security
    /// refuses — so sharing one function made a change for either question silently move the
    /// other, and it hid a real escape.
    ///
    /// Resolution uses `realpath`, which **fails when the path does not exist** and resolves
    /// every symlink on the way, including intermediate ones.
    /// `URL.resolvingSymlinksInPath()` does neither reliably: with a missing leaf it leaves
    /// the link unresolved, so `root/link/later.md` — where `link` points outside — passed a
    /// prefix check and was allowed. Measured, not assumed.
    ///
    /// Requiring existence costs the render surface nothing: it only ever loads files that
    /// are there, and "cannot resolve" collapsing to "blocked" is INV-6's default.
    public static func resolvedPathInsideRoot(
        path: String,
        projectRoot: String
    ) -> String? {
        guard projectRoot.hasPrefix("/") else {
            return nil
        }
        guard let resolvedRoot = realPath(projectRoot) else {
            return nil
        }

        let absolute = path.hasPrefix("/")
            ? path
            : (projectRoot as NSString).appendingPathComponent(path)
        guard let resolvedPath = realPath(absolute) else {
            // Missing, unreadable, or a broken link. Nothing to prove inside the root.
            return nil
        }

        // No case folding, and no flag asking whether to fold.
        //
        // `realpath` already converges on the spelling the volume holds: on a
        // case-insensitive volume `assets/logo.png` comes back as `Assets/Logo.png`, so
        // lowercasing changed nothing; on a case-sensitive one the fold was never applied.
        // Measured on a real case-sensitive volume (QA, `hdiutil`) — the verdict is the
        // same either way.
        //
        // The branch is gone rather than tested because it was **undefended**: a full
        // sandbox escape injected into the `false` side left the whole suite green, and
        // `false` is what every ordinary Mac volume produces. A branch that cannot be
        // absent is better than one guarded by tests that do not discriminate.
        let root = resolvedRoot
        let file = resolvedPath

        // The root directory is not a file inside itself.
        guard file != root else {
            return nil
        }
        // The separator is part of the check, or `/repo-secrets` counts as inside `/repo`.
        guard file.hasPrefix(root.hasSuffix("/") ? root : root + "/") else {
            return nil
        }
        // The resolved spelling is returned, not the requested one — that is what the
        // loader opens.
        return resolvedPath
    }

    /// `realpath(3)`: full symlink resolution, and nil when the path does not exist.
    private static func realPath(_ path: String) -> String? {
        guard let buffer = realpath(path, nil) else {
            return nil
        }
        defer { free(buffer) }
        return String(cString: buffer)
    }

    // MARK: URL 조각

    private static func detail(for source: String?) -> String {
        guard let source, !source.isEmpty else {
            return inlineDetail
        }
        return host(of: source) ?? source
    }

    /// The scheme, when the source names one. A bare or relative path has none.
    static func scheme(of source: String) -> String? {
        guard let separator = source.range(of: "://") else {
            // `data:` and `javascript:` carry no slashes; still schemes, still not files.
            guard let colon = source.firstIndex(of: ":"),
                  source[source.startIndex..<colon].allSatisfy({ $0.isLetter })
            else {
                return nil
            }
            return String(source[source.startIndex..<colon]).lowercased()
        }
        return String(source[source.startIndex..<separator.lowerBound]).lowercased()
    }

    /// The host of a `//host/path` reference.
    static func protocolRelativeHost(of source: String) -> String {
        let withoutSlashes = source.dropFirst(2)
        let host = withoutSlashes.prefix { $0 != "/" }
        return host.isEmpty ? source : String(host)
    }

    static func host(of source: String) -> String? {
        URL(string: source)?.host
    }

    private static func filePath(from source: String) -> String {
        guard scheme(of: source) == "file" else {
            return source
        }
        return URL(string: source)?.path ?? source
    }
}
