import CodeNavigatorContract

/// The symbol index: forward (file to its symbols) and reverse (name to its definition sites).
///
/// The index is a derived product. It lives only in memory and is rebuilt from source, so a
/// stale index cannot outlive a restart (INV-2). Nothing here reads or writes project files.
///
/// This is an `actor` because indexing writes from background tasks while the interface reads.
/// Serialising through the actor is what makes "one writer at a time" a property of the language
/// rather than a rule people have to remember (ADR-0003).
public actor SymbolIndex {
    private var definitionsByFilePath: [String: [SymbolDefinition]] = [:]
    private var definitionsBySymbolName: [String: [SymbolDefinition]] = [:]

    public init() {}

    // MARK: - Mutation

    /// Replaces everything known about one file. This is the only way symbols enter the index:
    /// create, update and rename all reduce to replace and remove, so there is no separate path
    /// that could forget to clean up the reverse map.
    public func replaceFile(_ filePath: String, with symbols: [SymbolDefinition]) {
        removeFile(filePath)
        guard !symbols.isEmpty else { return }

        definitionsByFilePath[filePath] = symbols
        for symbol in symbols {
            definitionsBySymbolName[symbol.name, default: []].append(symbol)
        }
    }

    /// Removes every trace of a file. Removing a file that was never indexed is a no-op.
    public func removeFile(_ filePath: String) {
        guard let removed = definitionsByFilePath.removeValue(forKey: filePath) else { return }

        for symbol in removed {
            guard var remaining = definitionsBySymbolName[symbol.name] else { continue }
            remaining.removeAll { $0.path == filePath }
            // Drop the key entirely rather than leaving an empty array behind, so a name that no
            // longer exists anywhere cannot linger as a phantom result (INV-1).
            if remaining.isEmpty {
                definitionsBySymbolName.removeValue(forKey: symbol.name)
            } else {
                definitionsBySymbolName[symbol.name] = remaining
            }
        }
    }

    /// Drops every indexed file that is no longer in the current scan set.
    ///
    /// A full rescan uses this to restore INV-1 for files that disappeared without an event —
    /// deleted while the app was closed, or lost in a burst the watcher could not itemise.
    public func removeFiles(notIn scannedFilePaths: Set<String>) {
        let vanished = definitionsByFilePath.keys.filter { !scannedFilePaths.contains($0) }
        for filePath in vanished {
            removeFile(filePath)
        }
    }

    public func clear() {
        definitionsByFilePath.removeAll()
        definitionsBySymbolName.removeAll()
    }

    // MARK: - Queries

    /// Definition sites for an exact name, sorted by path then line.
    ///
    /// Always sorted, so no caller can accidentally depend on file-scan order. Same-named
    /// definitions in different files are all returned — picking between them is the user's
    /// job, not the index's (REQ-005 AC-2).
    public func definitions(named name: String) -> [SymbolDefinition] {
        (definitionsBySymbolName[name] ?? []).sorted(by: Self.byPathThenLine)
    }

    public func hasDefinition(named name: String, atPath path: String, line: Int) -> Bool {
        (definitionsBySymbolName[name] ?? []).contains { $0.path == path && $0.line == line }
    }

    public func allDefinitions() -> [SymbolDefinition] {
        definitionsByFilePath.values.flatMap { $0 }
    }

    public func indexedFilePaths() -> Set<String> {
        Set(definitionsByFilePath.keys)
    }

    public func symbolCount() -> Int {
        definitionsByFilePath.values.reduce(0) { $0 + $1.count }
    }

    public func fileCount() -> Int {
        definitionsByFilePath.count
    }

    private static func byPathThenLine(_ left: SymbolDefinition, _ right: SymbolDefinition) -> Bool {
        if left.path != right.path {
            return left.path < right.path
        }
        return left.line < right.line
    }
}
