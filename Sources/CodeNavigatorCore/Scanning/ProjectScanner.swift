import CodeNavigatorContract
import Foundation

/// Walks a project root and lists the files worth showing, indexing and searching.
///
/// The walk is deliberately hand-rolled rather than delegated to `FileManager.enumerator`:
/// we need to read each directory's `.gitignore` *before* descending into it, and to prune an
/// ignored directory without visiting its contents. Pruning is what keeps a repository with a
/// large ignored `vendor` tree cheap to scan.
///
/// Symbolic links are never followed. That is both a symlink-loop guard (REQ-NF-004) and the
/// behaviour git itself has.
///
/// This type only reads. It has no code that writes to the project (INV-3).
struct ProjectScanner {
    private let fileManager = FileManager.default

    func scan(rootPath: URL) throws -> ProjectScan {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootPath.path, isDirectory: &isDirectory) else {
            throw NavigatorError.projectNotFound(path: rootPath.path)
        }
        guard isDirectory.boolValue else {
            throw NavigatorError.projectNotReadable(
                path: rootPath.path,
                reason: "디렉토리가 아닙니다"
            )
        }

        var filePaths: [String] = []
        var indexableFilePaths: [String] = []
        var ruleSets: [GitignoreRuleSet] = []

        // The root is read here rather than inside the walk so that a permission denial on it is
        // an error. Inside the walk an unreadable directory is skipped — one locked folder must
        // not stop the run — but applying that tolerance to the root turns "you cannot read this
        // project" into "this project has no files", which is a lie the user cannot act on.
        guard (try? fileManager.contentsOfDirectory(atPath: rootPath.path)) != nil else {
            throw NavigatorError.projectNotReadable(
                path: rootPath.path,
                reason: "디렉토리를 읽을 권한이 없습니다"
            )
        }

        try walk(
            directoryURL: rootPath,
            relativeDirectory: "",
            rootPath: rootPath,
            ruleSets: &ruleSets,
            filePaths: &filePaths,
            indexableFilePaths: &indexableFilePaths
        )

        return ProjectScan(
            filePaths: filePaths.sorted(),
            indexableFilePaths: indexableFilePaths.sorted()
        )
    }

    // MARK: - Walking

    private func walk(
        directoryURL: URL,
        relativeDirectory: String,
        rootPath: URL,
        ruleSets: inout [GitignoreRuleSet],
        filePaths: inout [String],
        indexableFilePaths: inout [String]
    ) throws {
        // This directory's own .gitignore governs everything below it, so it must be loaded
        // before any child is judged.
        if let ruleSet = GitignoreRuleSet.load(
            inDirectoryAt: directoryURL,
            relativeDirectory: relativeDirectory
        ) {
            ruleSets.append(ruleSet)
        }
        let matcher = GitignoreMatcher(ruleSets: ruleSets)

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            // An unreadable directory is skipped, not fatal — one permission-denied folder must
            // not abort indexing of the whole project (REQ-NF-004).
            return
        }

        for entry in entries {
            let name = entry.lastPathComponent
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                continue
            }
            let isDirectory = values?.isDirectory ?? false
            let relativePath = relativeDirectory.isEmpty ? name : "\(relativeDirectory)/\(name)"

            if isDirectory {
                if ScanExclusions.isExcluded(directoryName: name) {
                    continue
                }
                if matcher.isIgnored(relativePath: relativePath, isDirectory: true) {
                    continue
                }
                var childRuleSets = ruleSets
                try walk(
                    directoryURL: entry,
                    relativeDirectory: relativePath,
                    rootPath: rootPath,
                    ruleSets: &childRuleSets,
                    filePaths: &filePaths,
                    indexableFilePaths: &indexableFilePaths
                )
                continue
            }

            if ScanExclusions.isExcluded(fileName: name) {
                continue
            }
            if matcher.isIgnored(relativePath: relativePath, isDirectory: false) {
                continue
            }

            filePaths.append(relativePath)
            if SourceLanguage(filePath: relativePath) != nil {
                indexableFilePaths.append(relativePath)
            }
        }
    }
}
