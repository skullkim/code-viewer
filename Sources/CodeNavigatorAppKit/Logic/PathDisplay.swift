import Foundation

/// Turns file paths into what the shell shows, and reconciles the two path shapes the
/// engine hands out.
///
/// The edit session reports absolute paths; the file tree reports project-relative ones.
/// The status bar and the tree's current-file highlight need them to agree, and a
/// mismatch here fails quietly — the highlight simply never appears — so normalisation is
/// done deliberately rather than left to string comparison.
public enum PathDisplay {

    /// The ellipsis that marks directories dropped from the front of a path.
    private static let leadingEllipsis = "…/"

    /// macOS reports the same file with and without this prefix depending on which API
    /// produced the path, because /tmp and /var are symlinks into /private.
    private static let privatePrefix = "/private"

    /// The project-relative form of an absolute path, or nil when the path is not inside
    /// the project.
    public static func relativePath(ofAbsolutePath absolutePath: String, projectRoot: String) -> String? {
        let path = normalised(absolutePath)
        let root = normalised(projectRoot)

        if path == root {
            return ""
        }

        let rootWithSeparator = root.hasSuffix("/") ? root : root + "/"
        // A prefix check alone would accept "/a/broader" as being inside "/a/b", so the
        // separator has to be part of the comparison.
        guard path.hasPrefix(rootWithSeparator) else {
            return nil
        }
        return String(path.dropFirst(rootWithSeparator.count))
    }

    /// Drops leading directories until the path fits, keeping the file name whole.
    ///
    /// A path that has lost its directories still identifies the file; one that has lost
    /// its file name identifies nothing, so the file name is never shortened even when it
    /// alone exceeds the budget.
    public static func truncatedFromStart(_ path: String, maximumCharacters: Int) -> String {
        guard path.count > maximumCharacters else {
            return path
        }

        var components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count > 1 else {
            return path
        }

        while components.count > 1 {
            components.removeFirst()
            let candidate = leadingEllipsis + components.joined(separator: "/")
            if candidate.count <= maximumCharacters {
                return candidate
            }
        }
        return components.joined(separator: "/")
    }

    /// The last component of a path.
    public static func fileName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }

    private static func normalised(_ path: String) -> String {
        var result = (path as NSString).standardizingPath
        if result.hasPrefix(privatePrefix) {
            result = String(result.dropFirst(privatePrefix.count))
        }
        // standardizingPath leaves a single trailing slash on a root-level path only.
        if result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
