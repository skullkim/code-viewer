import AppKit
import SwiftUI
import CodeNavigatorAppKit

/// The application entry point.
///
/// Not `main.swift`: top-level code cannot carry a global actor, which puts it at odds
/// with the strict concurrency the rest of the shell is written under (ADR-0105).
@main
struct CodeNavigatorMain {
    static func main() {
        if CommandLine.arguments.contains("--self-check") {
            reportBundleIdentity()
            return
        }
        CodeNavigatorApplication.run()
    }

    /// Reports bundle identity and exits, so `scripts/verify-bundle.sh` can check that the
    /// assembled bundle actually runs without needing a window server session. A `.app`
    /// directory existing is not evidence that anything works.
    private static func reportBundleIdentity() {
        let identifier = Bundle.main.bundleIdentifier ?? "(none)"
        let executable = Bundle.main.executableURL?.lastPathComponent ?? "(none)"
        print("bundleIdentifier=\(identifier) executable=\(executable)")
    }
}
