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
    /// A local file inside the root that is larger than the render limit.
    ///
    /// Its own row rather than folded into another (leader ruling 2026-08-31). Before it, a
    /// 3MB PNG inside the project was recorded as `outsideProjectRoot` — a lie about where the
    /// file was. It is also **the only reason on this list the reader can act on**: the others
    /// describe a policy, this one describes a file they can shrink.
    case tooLarge

    /// The wording W-15's popover uses. The screen and the code say the same words.
    public var label: String {
        switch self {
        case .remoteImage: return "원격 이미지"
        case .script: return "스크립트"
        case .remoteStylesheet: return "원격 스타일시트"
        case .remoteFont: return "원격 폰트"
        case .frame: return "프레임"
        case .outsideProjectRoot: return "프로젝트 밖 파일"
        case .tooLarge: return "크기 초과 파일"
        }
    }

    /// Whether a placeholder is drawn where the element sat.
    ///
    /// Only the ones that occupied space. A blocked script never had a box on the page, and
    /// drawing one for it would invent a hole the document never had (W-15).
    public var showsInlinePlaceholder: Bool {
        switch self {
        case .remoteImage, .outsideProjectRoot, .frame, .tooLarge:
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
/// 참조가 가리키는 자리.
///
/// **"밖에 있다" 와 "거기 없다" 는 다른 사건이다.** 하나로 접으면 문구가 하나를 고르고,
/// QA 라이브에서 그 선택은 **프로젝트 안의 파일을 밖에 있다고 안내**했다. 그리고 안 막은
/// 것이 차단 칩에 실려 **보안 신호가 부풀려졌다** — 부풀려진 신호는 진짜 차단까지 못 믿게
/// 만든다.
public enum ResolvedResourceLocation: Sendable, Hashable {
    case insideRoot(resolvedPath: String)
    case outsideRoot
    /// 루트 안을 가리키는데 거기 없거나 읽을 수 없다. **차단이 아니다.**
    case notFound
}

public enum SandboxDecision: Sendable, Hashable {
    /// A local file proven inside the root. **The loader must open this exact path** and
    /// not the reference it came from: checking one path and opening another leaves a
    /// window in which a file appears between the two, which makes the check meaningless.
    case allowFile(resolvedPath: String)
    /// Already inline. There is nothing to fetch and nothing to confine.
    case allowInlineData
    case block(kind: BlockedResourceKind, detail: String)
    /// 우리가 막은 것이 아니라 우리가 못 읽은 것. 칩에는 안 오르고 자리에는 남는다.
    case unavailable(detail: String)

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
        switch locate(path: path, projectRoot: projectRoot) {
        case .insideRoot(let resolved):
            return .allowFile(resolvedPath: resolved)
        case .outsideRoot:
            return .block(kind: .outsideProjectRoot, detail: source)
        case .notFound:
            // 루트 **안**인데 거기 없다. 우리가 막은 게 아니므로 차단으로 세지 않는다 —
            // 안 막은 것을 막았다고 하면 보안 신호가 부풀려지고, 부풀려진 신호는 진짜
            // 차단까지 못 믿게 만든다.
            return .unavailable(detail: source)
        }
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
    /// 이 경로가 루트 안인지, 밖인지, 아니면 거기 없는지.
    ///
    /// **봉쇄를 파일 시스템보다 먼저 판단한다.** 존재를 먼저 물으면 그 답이 신탁이 된다 —
    /// 문서가 루트 밖 경로를 참조해 놓고 *"밖입니다"* 와 *"없습니다"* 를 구별하면, 차단
    /// 고지가 **프로젝트 밖 파일 목록을 한 칸씩 읽는 도구**가 된다. 그래서 밖으로 판정된
    /// 경로는 **존재를 묻지도 않는다.** 오늘 링크 판정에서 닫은 것과 같은 자리다.
    public static func locate(path: String, projectRoot: String) -> ResolvedResourceLocation {
        guard projectRoot.hasPrefix("/") else {
            return .outsideRoot
        }
        let absolute = path.hasPrefix("/")
            ? path
            : (projectRoot as NSString).appendingPathComponent(path)

        // 1단계 — 어휘적 봉쇄. 파일 시스템을 만지지 않는다.
        guard lexicallyNormalised(absolute).hasPrefix(lexicalBoundary(of: projectRoot)) else {
            return .outsideRoot
        }

        // 2단계 — 루트 안이라고 주장하는 경로만 실제로 찾아본다. 자기 프로젝트 안에 그
        // 파일이 있는지는 비밀이 아니다.
        guard let resolvedRoot = realPath(projectRoot) else {
            return .notFound
        }
        guard let resolvedPath = realPath(absolute) else {
            // leaf 가 없으면 `realpath` 는 아무 답도 못 준다. 그렇다고 **"없는 파일"로
            // 끝내면 D-12 가 되살아난다** — 루트 안의 심링크가 밖을 가리키고 그 대상이
            // 아직 없을 때, 그건 "없는 파일"이 아니라 **탈출 시도**다. 그 둘을 가르려면
            // 존재하는 가장 가까운 조상까지 올라가 거기서 판정해야 한다.
            //
            // 로드는 어느 쪽이든 일어나지 않지만 **보고가 달라진다**: 탈출을 "없는 파일"로
            // 적으면 차단 칩이 실제 공격을 안 센다.
            return locationOfNearestExistingAncestor(of: absolute, resolvedRoot: resolvedRoot)
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

        // 3단계 — 심링크. 루트 안에 있으면서 밖을 가리킬 수 있다(D-12).
        // The root directory is not a file inside itself.
        guard file != root else {
            return .outsideRoot
        }
        // The separator is part of the check, or `/repo-secrets` counts as inside `/repo`.
        guard file.hasPrefix(root.hasSuffix("/") ? root : root + "/") else {
            return .outsideRoot
        }
        // The resolved spelling is returned, not the requested one — that is what the
        // loader opens.
        return .insideRoot(resolvedPath: resolvedPath)
    }

    /// leaf 가 없을 때, 존재하는 가장 가까운 조상으로 봉쇄를 판정한다.
    ///
    /// 조상이 루트 밖이면 **경로 전체가 밖**이다 — 심링크가 밖을 가리키는데 대상 파일만
    /// 아직 없는 경우가 정확히 그 모양이고, D-12 가 그것이었다. 조상이 루트 안이면
    /// 그냥 **거기 없는 파일**이다.
    private static func locationOfNearestExistingAncestor(
        of absolute: String,
        resolvedRoot: String
    ) -> ResolvedResourceLocation {
        let boundary = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        var ancestor = (absolute as NSString).deletingLastPathComponent

        while ancestor.count > 1 {
            if let resolved = realPath(ancestor) {
                let inside = resolved == resolvedRoot || resolved.hasPrefix(boundary)
                return inside ? .notFound : .outsideRoot
            }
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }

        // 조상 중 존재하는 것이 하나도 없다 — 판정할 근거가 없으므로 닫는 쪽으로.
        return .outsideRoot
    }

    /// 루트 안으로 해석된 절대 경로, 또는 nil. `locate` 의 얇은 래퍼.
    public static func resolvedPathInsideRoot(path: String, projectRoot: String) -> String? {
        guard case .insideRoot(let resolved) = locate(path: path, projectRoot: projectRoot) else {
            return nil
        }
        return resolved
    }

    /// 루트가 끝나는 자리. 구분자를 포함해야 `/repo-secrets` 가 `/repo` 안으로 안 세어진다.
    static func lexicalBoundary(of projectRoot: String) -> String {
        let normalised = lexicallyNormalised(projectRoot)
        return normalised.hasSuffix("/") ? normalised : normalised + "/"
    }

    /// `.` 과 `..` 를 파일 시스템에 묻지 않고 접는다.
    ///
    /// `standardizingPath` 가 아니다 — 그쪽은 존재하는 경로의 심링크를 풀어서 이 검사의
    /// 답이 **디스크에 무엇이 있느냐에 달리게** 된다. 이 단계가 피하려는 의존이 그것이다.
    static func lexicallyNormalised(_ path: String) -> String {
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

    /// `realpath(3)`: full symlink resolution, and nil when the path does not exist.
    /// The project root as the file system spells it.
    ///
    /// Exposed so that navigation can turn an allowed absolute path back into the relative
    /// one the engine takes, **using the same resolution this file uses everywhere else**. A
    /// second way of resolving the root is a second answer to "where is the root", and the
    /// two drift on exactly the inputs that matter (symlinked or `/private`-prefixed roots).
    public static func resolvedRoot(_ projectRoot: String) -> String? {
        guard projectRoot.hasPrefix("/") else {
            return nil
        }
        return realPath(projectRoot)
    }

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
