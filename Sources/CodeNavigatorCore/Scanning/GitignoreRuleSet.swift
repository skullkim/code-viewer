import Foundation

/// The patterns from one `.gitignore` file, together with the directory it governs.
///
/// `baseDirectory` is project-root-relative and empty for the root file. A rule set only ever
/// applies to paths beneath its own directory, which is what makes nested `.gitignore` files work.
struct GitignoreRuleSet {
    let baseDirectory: String
    let patterns: [GitignorePattern]

    init(baseDirectory: String, patternText: String) {
        self.baseDirectory = baseDirectory.trimmingTrailingSlash()
        self.patterns = patternText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { GitignorePattern(line: String($0)) }
    }

    /// The name git itself looks for. Named once, here, because two walkers now read it.
    private static let gitignoreFileName = ".gitignore"

    /// Reads the `.gitignore` governing one directory, or nil when the directory has none.
    ///
    /// Both walkers load through this: `ProjectScanner` descends the whole tree, while
    /// `DirectoryTreeLister` climbs to a single directory. Two copies of this five-line read
    /// would eventually drift, and a drift here means the tree shows a file that search and the
    /// index refuse to touch.
    static func load(inDirectoryAt directoryURL: URL, relativeDirectory: String) -> GitignoreRuleSet? {
        let gitignoreURL = directoryURL.appendingPathComponent(gitignoreFileName)
        guard let patternText = try? String(contentsOf: gitignoreURL, encoding: .utf8) else {
            return nil
        }
        return GitignoreRuleSet(baseDirectory: relativeDirectory, patternText: patternText)
    }

    /// How deep this rule set sits, so deeper files can take precedence over shallower ones.
    var depth: Int {
        baseDirectory.isEmpty ? 0 : baseDirectory.split(separator: "/").count
    }

    /// The path rewritten relative to this rule set's directory, or `nil` when the path lies
    /// outside it and the rules therefore do not apply.
    func pathRelativeToBase(_ relativePath: String) -> String? {
        guard !baseDirectory.isEmpty else { return relativePath }
        let prefix = baseDirectory + "/"
        guard relativePath.hasPrefix(prefix) else { return nil }
        return String(relativePath.dropFirst(prefix.count))
    }
}

extension String {
    func trimmingTrailingSlash() -> String {
        var value = self
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
