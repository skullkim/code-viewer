/// Directories never worth indexing or searching.
///
/// One shared list, used by the scanner, full-text search and reference search alike. The web
/// version got this consistency by passing one argument array to every ripgrep call; here the
/// shared type plays that role. If these ever diverge, a symbol can be indexed from a file that
/// search refuses to look at, and the two features start disagreeing about what the project is.
enum ScanExclusions {
    static let excludedDirectoryNames: Set<String> = [
        "node_modules", "build", "dist", "target", "out", ".gradle",
    ]

    /// Hidden entries are skipped wholesale, which also covers `.git` without naming it.
    static func isHidden(name: String) -> Bool {
        name.hasPrefix(".")
    }

    static func isExcluded(directoryName name: String) -> Bool {
        isHidden(name: name) || excludedDirectoryNames.contains(name)
    }

    static func isExcluded(fileName name: String) -> Bool {
        isHidden(name: name)
    }
}
