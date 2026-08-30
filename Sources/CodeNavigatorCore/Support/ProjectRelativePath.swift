import CodeNavigatorContract
import Foundation

/// A caller-supplied path, proven to name a file inside the open project.
///
/// INV-6 restricts local file access to the open project root. That rule is enforced here and
/// only here: anything that reads project files for the user — the render view today, whatever
/// wants file bytes tomorrow — resolves through this type. A second place doing its own check is
/// how two rules that were meant to be one drift apart, and the weaker of the two becomes the
/// real one.
///
/// Two different escapes have to be refused, and neither check catches the other:
/// segments that climb (`../`), and segments that are all innocent while the file they name
/// lives elsewhere (a symlink out of the tree).
struct ProjectRelativePath {
    /// The path as the project knows it, with `.` segments removed.
    let relativePath: String

    /// The real file, with every symlink already resolved — proven to be inside the root.
    let url: URL

    static func resolve(_ relativePath: String, inProjectRoot rootPath: URL) throws -> ProjectRelativePath {
        // An absolute path is not a project path at all. Appending it to the root would quietly
        // produce something that looks relative and is not.
        guard !relativePath.hasPrefix("/") else {
            throw NavigatorError.invalidPath(relativePath)
        }

        let segments = relativePath.split(separator: "/").map(String.init).filter { $0 != "." }

        // Rejected as a whole segment, never as a substring: a directory honestly named
        // `docs..old` is not an escape attempt, and refusing it would be a bug the user cannot
        // work around.
        guard !segments.contains("..") else {
            throw NavigatorError.invalidPath(relativePath)
        }
        guard !segments.isEmpty else {
            throw NavigatorError.invalidPath(relativePath)
        }

        let candidate = segments.reduce(rootPath) { $0.appendingPathComponent($1) }

        // The file has to exist before it can be proven to be inside: `realpath` answers about
        // real files. A missing file is reported as missing rather than as a rule violation,
        // because telling a user their typo was a security problem teaches them nothing.
        guard let canonicalFile = canonicalPath(of: candidate.path) else {
            throw NavigatorError.fileNotFound(path: relativePath)
        }
        guard let canonicalRoot = canonicalPath(of: rootPath.path) else {
            throw NavigatorError.projectNotFound(path: rootPath.path)
        }

        // Compared with the separator attached, so a sibling directory whose name merely starts
        // with the root's name (`/repo-backup` beside `/repo`) is not mistaken for a child.
        let rootPrefix = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"
        guard canonicalFile.hasPrefix(rootPrefix) else {
            throw NavigatorError.invalidPath(relativePath)
        }

        return ProjectRelativePath(
            relativePath: segments.joined(separator: "/"),
            url: URL(fileURLWithPath: canonicalFile)
        )
    }

    private static func canonicalPath(of path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
