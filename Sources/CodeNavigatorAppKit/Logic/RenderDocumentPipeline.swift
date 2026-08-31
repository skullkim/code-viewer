import Foundation

/// Turns a document into the sandboxed HTML the web view is given (REQ-013, INV-6).
///
/// **Two passes, because the two halves disagree about time.** Preprocessing is synchronous
/// and pure — that is what makes it testable without a disk, and what keeps the sandbox rules
/// in plain functions. Reading a file is asynchronous, because it crosses into the engine.
///
/// The tempting bridge is to block the synchronous side until the read finishes. That is a
/// semaphore on the main thread, and it deadlocks: the work being waited on needs the very
/// thread that is waiting. It happened on this project the same day this was written — a
/// `--self-check` waited on a `@MainActor` task and the gate sat still for eighteen minutes.
///
/// So neither side is bent. The document is scanned once to learn *which* resources it wants,
/// those are read concurrently with `await`, and the scan runs again against what came back.
/// The cost is one extra pass over a document that is capped at 2MB.
public enum RenderDocumentPipeline {

    public static func prepare(
        html: String,
        projectRoot: String,
        loadResource: (String) async -> Result<Data, RenderResourceFailure>
    ) async -> SanitizedDocument {
        // Pass one: what does this document actually ask for? The sandbox decides that, not a
        // separate scanner — asking twice with two implementations is how the two answers
        // drift, and here the second answer would decide what gets read from disk.
        var requested: [String] = []
        _ = RenderDocumentSanitizer.sanitize(html: html, projectRoot: projectRoot) { path in
            requested.append(path)
            // The result is discarded; only the question mattered.
            return .failure(.notFound)
        }

        // Read each distinct path once. A document that shows the same logo twenty times
        // should touch the disk once, not twenty times.
        var loaded: [String: Result<Data, RenderResourceFailure>] = [:]
        for path in NSOrderedSet(array: requested).compactMap({ $0 as? String }) {
            loaded[path] = await loadResource(path)
        }

        // Pass two: the real one. Every answer is already in hand, so the loader cannot block.
        return RenderDocumentSanitizer.sanitize(html: html, projectRoot: projectRoot) { path in
            // A path that reaches here but was not requested in pass one would mean the two
            // passes disagreed about the same document — treat it as unreadable rather than
            // inventing bytes.
            loaded[path] ?? .failure(.notFound)
        }
    }
}
