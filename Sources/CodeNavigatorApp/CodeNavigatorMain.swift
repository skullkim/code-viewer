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
            // The graph crosses an actor boundary to build, so the check is async — and a
            // semaphore here would deadlock: waiting on the main thread starves the very
            // main actor the task needs to run on. Measured, and it hung the gate for
            // eighteen minutes.
            //
            // The run loop keeps the main thread serving instead of blocking it, and the
            // check ends the process itself when it is done.
            Task { @MainActor in
                await CodeNavigatorApplication.reportSelfCheck()
                exit(0)
            }
            RunLoop.main.run()
            return
        }
        CodeNavigatorApplication.run()
    }
}
