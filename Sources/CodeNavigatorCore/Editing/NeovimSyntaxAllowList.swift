/// Which files the editor is allowed to colour (REQ-016 AC-4).
///
/// Neovim colours far more languages than this application understands — measured, it highlights
/// Python and Go out of the box from its own bundled syntax files. REQ-016 AC-4 asks for the
/// opposite: a file in an unsupported language renders as plain text, so that colour never
/// implies a level of support the rest of the application cannot deliver. Nothing is broken about
/// Neovim's Python colours; they would just promise `gd` and `gr` that do not work there.
///
/// The list is keyed by **Neovim's filetype**, because that is what the side making the decision
/// reports. Extensions are `SourceLanguage`'s business.
enum NeovimSyntaxAllowList {

    /// Neovim filetype → the language this application indexes.
    ///
    /// Kept as a mapping rather than a bare set so the test can prove every `SourceLanguage` is
    /// reachable. Two lists of "what we support" drift, and the drift is silent: a language the
    /// indexer knows but the allow-list forgot is one that finds symbols and shows none of them
    /// in colour.
    private static let languagesByFileType: [String: SourceLanguage] = [
        "java": .java,
        "kotlin": .kotlin,
        "typescript": .typescript,
        "typescriptreact": .typescript,
        "javascript": .javascript,
        "javascriptreact": .javascript,
    ]

    static var highlightedFileTypes: Set<String> {
        Set(languagesByFileType.keys)
    }

    static func supportedLanguage(forFileType fileType: String) -> SourceLanguage? {
        languagesByFileType[fileType]
    }

    static func allowsHighlighting(fileType: String) -> Bool {
        languagesByFileType[fileType] != nil
    }
}
