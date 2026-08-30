import Foundation

/// What the render surface decided about one resource reference (INV-6).
public enum RenderResourceDecision: Sendable, Hashable {
    /// A local file inside the project root, given as an absolute path for the app to read
    /// and inline as a `data:` URI (ADR-0109).
    case allow(path: String)
    /// Already inline. Carries no fetch, so there is nothing to confine.
    case inlineData
    /// Refused, with why — the reason reaches the user (W-15), because a silently empty
    /// space reads as the application being broken.
    case blocked(reason: RenderBlockReason)
}

/// Why a resource was refused. Shown in the blocked-resource popover (02b W-15).
public enum RenderBlockReason: Sendable, Hashable {
    /// A network fetch. The host is kept so the popover can name it.
    case remote(host: String)
    /// A local path that resolves outside the open project.
    case outsideProjectRoot
    /// Neither a readable local reference nor a scheme we serve.
    case unsupported
}

public extension RenderResourceDecision {
    var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }

    var isInlineData: Bool { self == .inlineData }

    var allowedPath: String? {
        if case .allow(let path) = self { return path }
        return nil
    }
}

/// Decides what the render surface may read (INV-6, ADR-0109).
///
/// The content rule list blocks the network outright, so nothing here is the last line
/// against a remote fetch. What this *is* the last line for is the second half of INV-6:
/// local access stays inside the open project. Every local resource the renderer draws
/// passes through here and comes out as an absolute path the app reads itself.
///
/// It is a pure function over strings and the filesystem's own answer about symlinks, so
/// the escape cases — `..`, an absolute path, a symlink out, a sibling whose name merely
/// starts with the root — are testable without a WebView.
public enum RenderResourcePolicy {

    /// Schemes that mean "fetch this from somewhere else".
    ///
    /// Listed to *name the host* in the refusal, not to decide it: anything that is not a
    /// resolvable path inside the root is refused regardless of whether it appears here.
    /// A blocklist that decides would only stop the schemes someone thought of.
    private static let remoteSchemes: Set<String> = ["http", "https", "ftp", "ftps", "ws", "wss", "file"]

    public static func decide(reference: String, projectRoot: String) -> RenderResourceDecision {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .blocked(reason: .unsupported)
        }

        if trimmed.lowercased().hasPrefix("data:") {
            return .inlineData
        }

        // `//host/path` inherits the page's scheme, so it is a network reference wearing
        // the shape of a path.
        if trimmed.hasPrefix("//") {
            let host = String(trimmed.dropFirst(2).prefix { $0 != "/" })
            return .blocked(reason: .remote(host: host))
        }

        if let scheme = scheme(of: trimmed) {
            guard remoteSchemes.contains(scheme) else {
                return .blocked(reason: .unsupported)
            }
            let host = URL(string: trimmed)?.host ?? scheme
            return .blocked(reason: .remote(host: host))
        }

        return decideLocal(path: trimmed, projectRoot: projectRoot)
    }

    private static func decideLocal(path: String, projectRoot: String) -> RenderResourceDecision {
        let rootURL = URL(fileURLWithPath: projectRoot).resolvingSymlinksInPath()
        let candidate = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : rootURL.appendingPathComponent(path)

        // The filesystem is asked, not the string: a name inside the root may be a symlink
        // pointing anywhere, and the string alone cannot tell.
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL

        guard isDescendant(resolved, of: rootURL.standardizedFileURL) else {
            return .blocked(reason: .outsideProjectRoot)
        }
        return .allow(path: resolved.path)
    }

    /// Whether one path lies inside another, compared component by component.
    ///
    /// String prefixes are the trap here: `/tmp/root-evil` begins with `/tmp/root` and is a
    /// different directory, so a prefix test lets an attacker walk out by choosing a folder
    /// name. The root itself is not a descendant — it is a directory, not a resource.
    private static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let candidateParts = candidate.pathComponents
        let rootParts = root.pathComponents
        guard candidateParts.count > rootParts.count else { return false }
        return Array(candidateParts.prefix(rootParts.count)) == rootParts
    }

    /// The scheme of a reference, if it has one.
    ///
    /// Read by hand rather than through `URL(string:)` so the rule is explicit and pinned
    /// by tests. `URL(string:)` agrees on the cases here — measured: `images/c:logo.png`
    /// and `//host/x.png` both give it no scheme — but it decides that through parsing
    /// rules this code does not control and does not want to depend on across OS versions.
    /// A path is refused when it leaves the root regardless, so the only job here is
    /// naming a remote reference well enough for the refusal to say where it pointed.
    private static func scheme(of reference: String) -> String? {
        guard let colon = reference.firstIndex(of: ":") else { return nil }
        let candidate = reference[reference.startIndex..<colon]
        guard !candidate.isEmpty, !candidate.contains("/") else { return nil }
        let isSchemeShaped = candidate.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
        guard isSchemeShaped, candidate.first?.isLetter == true else { return nil }
        return candidate.lowercased()
    }
}
