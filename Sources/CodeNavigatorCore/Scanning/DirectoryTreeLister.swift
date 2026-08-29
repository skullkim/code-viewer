import CodeNavigatorContract
import Foundation

/// Lists one level of the project file tree (REQ-003).
///
/// Only one level is read per call, because the tree loads lazily as the user expands it
/// (REQ-003 AC-1). Exclusions come from `ScanExclusions` and `GitignoreMatcher` — the very types
/// the scanner uses — rather than from a second copy of the rules: if the tree and the index
/// disagreed about what the project contains, the user would see a file in the tree and then
/// find it unsearchable.
///
/// This type only reads (INV-3).
struct DirectoryTreeLister {
    private let fileManager = FileManager.default

    func list(relativePath: String, rootPath: URL) throws -> [DirectoryEntry] {
        let segments = try validatedSegments(of: relativePath)
        let basePath = segments.joined(separator: "/")
        let directoryURL = segments.reduce(rootPath) { $0.appendingPathComponent($1) }

        try verifyDirectoryExists(at: directoryURL, relativePath: relativePath)

        let matcher = GitignoreMatcher(
            ruleSets: gitignoreRuleSets(downTo: segments, rootPath: rootPath)
        )
        let entryURLs = try readEntries(in: directoryURL, relativePath: relativePath)

        // Directories and files are collected apart so the sort order — directories first, then
        // name ascending (contract §3.1) — falls out of the concatenation.
        var directories: [DirectoryEntry] = []
        var files: [DirectoryEntry] = []

        for entryURL in entryURLs {
            let name = entryURL.lastPathComponent
            let values = try? entryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])

            // Symlinks are neither followed nor shown, exactly as in the scanner.
            if values?.isSymbolicLink == true {
                continue
            }

            let isDirectory = values?.isDirectory ?? false
            let entryPath = basePath.isEmpty ? name : "\(basePath)/\(name)"

            if isDirectory {
                if ScanExclusions.isExcluded(directoryName: name) {
                    continue
                }
                if matcher.isIgnored(relativePath: entryPath, isDirectory: true) {
                    continue
                }
                directories.append(DirectoryEntry(name: name, path: entryPath, isDirectory: true))
                continue
            }

            if ScanExclusions.isExcluded(fileName: name) {
                continue
            }
            if matcher.isIgnored(relativePath: entryPath, isDirectory: false) {
                continue
            }
            files.append(DirectoryEntry(name: name, path: entryPath, isDirectory: false))
        }

        return directories.sorted(by: byName) + files.sorted(by: byName)
    }

    /// Splits the path into segments and rejects anything that could climb out of the project.
    ///
    /// `..` is rejected only as a **whole segment**: a directory honestly named `docs..old` is
    /// not a traversal attempt, and a `contains("..")` check would refuse to list it.
    private func validatedSegments(of relativePath: String) throws -> [String] {
        guard !relativePath.hasPrefix("/") else {
            throw NavigatorError.invalidPath(relativePath)
        }

        let segments = relativePath.split(separator: "/").map(String.init)
        guard !segments.contains("..") else {
            throw NavigatorError.invalidPath(relativePath)
        }

        return segments
    }

    /// A file requested as a directory fails the same way a missing path does: in both cases
    /// there is no directory to list there.
    private func verifyDirectoryExists(at directoryURL: URL, relativePath: String) throws {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)

        guard exists, isDirectory.boolValue else {
            throw NavigatorError.fileNotFound(path: relativePath)
        }
    }

    private func readEntries(in directoryURL: URL, relativePath: String) throws -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            // The directory exists — it just cannot be read. Reporting that as an empty listing
            // would disguise a failure as an empty folder.
            throw NavigatorError.projectNotReadable(
                path: relativePath,
                reason: "디렉토리를 읽을 수 없습니다"
            )
        }
    }

    /// Every `.gitignore` from the project root down to this directory governs its contents, so
    /// all of them are loaded before any entry is judged — the same order the scanner builds
    /// them in on its way down.
    private func gitignoreRuleSets(downTo segments: [String], rootPath: URL) -> [GitignoreRuleSet] {
        var ruleSets: [GitignoreRuleSet] = []
        var directoryURL = rootPath
        var relativeDirectory = ""

        if let ruleSet = GitignoreRuleSet.load(
            inDirectoryAt: directoryURL,
            relativeDirectory: relativeDirectory
        ) {
            ruleSets.append(ruleSet)
        }

        for segment in segments {
            directoryURL.appendPathComponent(segment)
            relativeDirectory = relativeDirectory.isEmpty ? segment : "\(relativeDirectory)/\(segment)"

            if let ruleSet = GitignoreRuleSet.load(
                inDirectoryAt: directoryURL,
                relativeDirectory: relativeDirectory
            ) {
                ruleSets.append(ruleSet)
            }
        }

        return ruleSets
    }

    private func byName(_ left: DirectoryEntry, _ right: DirectoryEntry) -> Bool {
        left.name < right.name
    }
}
