import CodeNavigatorContract

/// Decides who owns a key, and what that means for us (REQ-015 AC-6).
///
/// Split from the code that talks to Neovim on purpose. Gathering the facts needs an editor;
/// judging them does not, and it is the judging that has two failure directions — claiming the
/// user's mapping (we never install, so `gd`/`gr` silently do nothing) and disowning it (we
/// overwrite, which AC-6 forbids).
enum NeovimKeyMappingClassifier {

    /// Who holds the key.
    ///
    /// The test is **"did this come from outside Neovim's runtime"**, not "is it under the config
    /// directory". Measured, the config-prefix test fails: `stdpath('config')` answers `/var/…`
    /// while `getscriptinfo` answers `/private/var/…` for the same file, because `/var` is a
    /// symbolic link on macOS. That failure disowns the user's mapping, which is the direction
    /// that ends in overwriting it — and users symlink `~/.config/nvim` into a dotfiles repository
    /// all the time, so it is not an artefact of the test environment.
    ///
    /// `editorRuntimePath` must arrive with symbolic links already resolved, as must the report's
    /// path; this compares them, it does not touch the file system.
    static func owner(
        of report: NeovimKeyMappingReport, editorRuntimePath: String
    ) -> NeovimKeyMappingOwner {
        guard report.isPresent else {
            return .nobody
        }

        // Neovim's own defaults report a non-positive identifier and name no script.
        guard report.scriptIdentifier > 0, let scriptPath = report.scriptPath, !scriptPath.isEmpty else {
            return .editorDefault
        }

        // An empty runtime path is a prefix of every string. Comparing against it would read
        // every user script as the editor's own and turn AC-6 off without a trace.
        if !editorRuntimePath.isEmpty, scriptPath.hasPrefix(editorRuntimePath) {
            return .editorDefault
        }

        return .user(scriptPath: scriptPath)
    }

    /// Whether the session installs its own mapping over this owner.
    static func shouldInstall(for owner: NeovimKeyMappingOwner) -> Bool {
        switch owner {
        case .nobody, .editorDefault: return true
        case .user: return false
        }
    }

    /// What the contract records about the decision.
    static func resolution(for owner: NeovimKeyMappingOwner) -> EditorKeyMappingOutcome.Resolution {
        switch owner {
        case .nobody: return .installed
        case .editorDefault: return .replacedEditorDefault
        case .user: return .deferredToUserMapping
        }
    }

    /// Which file's mapping won, when one did.
    static func userScriptPath(for owner: NeovimKeyMappingOwner) -> String? {
        switch owner {
        case .nobody, .editorDefault: return nil
        case .user(let scriptPath): return scriptPath
        }
    }
}
