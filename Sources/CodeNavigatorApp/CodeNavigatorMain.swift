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
            // The graph now crosses an actor boundary to build, so the check has to wait
            // for it. A semaphore rather than a `Task` alone: `main` must not return before
            // the check has run, or the gate would see a clean exit and no output.
            let finished = DispatchSemaphore(value: 0)
            Task { @MainActor in
                await CodeNavigatorApplication.reportSelfCheck()
                finished.signal()
            }
            finished.wait()
            return
        }
        CodeNavigatorApplication.run()
    }
}
