import Foundation

/// Keeps the test suite out of the user's real Neovim state.
///
/// Every Neovim this suite starts is a normal one, so it writes the user's ShaDa file — marks,
/// registers, command history, shared with their terminal editor. And this suite kills editors on
/// purpose: the D-2 checks abandon them, the teardown escalates to SIGKILL when SIGTERM is refused.
/// A process killed mid-write leaves a `main.shada.tmp.X` behind.
///
/// Measured on this machine before the fix: **26 leftover temp files**, at which point Neovim
/// refuses outright — `E138: All main.shada.tmp.X files exist, cannot write ShaDa file!`. The
/// user's own editor had stopped saving marks and history entirely, and each test run added one.
///
/// So the suite gets its own state directory. This is deliberately **test-only**: whether the
/// product should share the user's ShaDa or keep its own is a question about what a user wants
/// from an embedded editor, and that decision is not ours to make from inside a test helper.
enum NeovimTestStateIsolation {

    /// Redirects Neovim's state away from the user's home, once per process.
    ///
    /// `Process` inherits this process's environment when none is set explicitly, so setting it
    /// here reaches every editor the suite starts without any of them having to remember to ask.
    /// A helper each spawn site must opt into is one somebody eventually forgets.
    static let applied: Void = {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("code-navigator-nvim-state", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Both, because which one holds ShaDa moved between Neovim versions and this suite should
        // not depend on which one is installed.
        setenv("XDG_STATE_HOME", base.path, 1)
        setenv("XDG_DATA_HOME", base.path, 1)
    }()
}
