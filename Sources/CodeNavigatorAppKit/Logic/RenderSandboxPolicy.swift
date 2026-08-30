import Foundation

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
    case allow
    case block(kind: BlockedResourceKind, detail: String)
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
        projectRoot: String,
        isCaseSensitiveVolume: Bool
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
            return decideResource(source, remoteKind: .remoteImage, projectRoot: projectRoot, isCaseSensitiveVolume: isCaseSensitiveVolume)

        case .stylesheet(let source):
            return decideResource(source, remoteKind: .remoteStylesheet, projectRoot: projectRoot, isCaseSensitiveVolume: isCaseSensitiveVolume)

        case .font(let source):
            return decideResource(source, remoteKind: .remoteFont, projectRoot: projectRoot, isCaseSensitiveVolume: isCaseSensitiveVolume)
        }
    }

    /// Images, stylesheets and fonts differ only in which heading they are reported under.
    private static func decideResource(
        _ source: String?,
        remoteKind: BlockedResourceKind,
        projectRoot: String,
        isCaseSensitiveVolume: Bool
    ) -> SandboxDecision {
        guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // No source at all. Nothing to load and nothing to allow.
            return .block(kind: remoteKind, detail: inlineDetail)
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
                return .allow
            }
            guard scheme == "file" else {
                // Every other non-file scheme is blocked, not only the ones that reach the
                // network. An allowlist that grows by exception stops being one.
                return .block(kind: remoteKind, detail: host(of: source) ?? scheme)
            }
        }

        let path = filePath(from: source)
        guard isInsideProjectRoot(path: path, projectRoot: projectRoot, isCaseSensitiveVolume: isCaseSensitiveVolume) else {
            return .block(kind: .outsideProjectRoot, detail: source)
        }
        return .allow
    }

    /// Whether a path resolves to somewhere inside the project root.
    ///
    /// Symlinks are resolved on both sides before comparing. A link *inside* the root that
    /// points outside it is outside — checking the spelling instead of the destination is
    /// how a document reads `~/.ssh/config` through a file that looks local. `..` segments
    /// are collapsed by the same call.
    public static func isInsideProjectRoot(
        path: String,
        projectRoot: String,
        isCaseSensitiveVolume: Bool
    ) -> Bool {
        // An absolute root, or nothing is inside it.
        //
        // `URL(fileURLWithPath: "")` resolves to the process's working directory, so an
        // unset root would quietly become "wherever the app happens to be running" and
        // allow every file beneath it. A root that is not an absolute path is not a root.
        guard projectRoot.hasPrefix("/") else {
            return false
        }
        let resolvedRoot = ProjectIdentity.canonical(for: projectRoot, isCaseSensitiveVolume: isCaseSensitiveVolume)
        guard resolvedRoot.hasPrefix("/") else {
            return false
        }

        let absolute = path.hasPrefix("/")
            ? path
            : (projectRoot as NSString).appendingPathComponent(path)
        let resolvedPath = ProjectIdentity.canonical(for: absolute, isCaseSensitiveVolume: isCaseSensitiveVolume)

        if resolvedPath == resolvedRoot {
            return true
        }
        // The separator has to be part of the check, or `/repo-secrets` would count as
        // being inside `/repo`.
        return resolvedPath.hasPrefix(resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/")
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
