import AppKit
import CodeNavigatorAppKit

/// The application entry point.
///
/// Not `main.swift`: top-level code cannot carry a global actor, which puts it at odds
/// with the strict concurrency the rest of the shell is written under (ADR-0105).
@main
struct CodeNavigatorMain {
    static func main() {
        if CommandLine.arguments.contains("--self-check") {
            CodeNavigatorApplication.reportSelfCheck()
            return
        }
        CodeNavigatorApplication.run()
    }
}
