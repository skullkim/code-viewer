import Foundation

/// Reads a source file's text, refusing the ones that are not worth parsing.
///
/// Reading is where a project's pathological files show up: a generated bundle, a checked-in
/// binary with a source extension, a file that vanished between the scan and now. Each of those
/// returns `nil` rather than throwing, because one bad file must never stop an indexing run
/// (REQ-002 AC-4, REQ-NF-004).
///
/// 🔴 **Not for rendering, and not for anything the user reads.** Every refusal here collapses
/// into the same `nil`: too large, binary, vanished, undecodable. Indexing wants that — one bad
/// file must not stop a run — but a reader that cannot say *why* turns a file it declined into an
/// empty document, which is the blank screen REQ-013 AC-6 forbids. The limit is wrong for that
/// job too: it is half the render limit, so every file between the two would come back as if it
/// were empty. Reading for the user goes through `ProjectRelativePath` and reports named errors.
///
/// Contents are never retained. They are handed to the parser and dropped, which is what keeps
/// idle memory to the index itself (REQ-NF-002).
enum SourceFileReader {
    /// Past this size a file is almost certainly generated or vendored, and parsing it costs more
    /// than the symbols are worth.
    static let maximumFileSizeInBytes = 1_048_576

    /// Git's own heuristic: a NUL byte in the first chunk means binary.
    static let binarySniffLength = 8_192

    static func readText(at url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int,
              size <= maximumFileSizeInBytes
        else {
            return nil
        }
        guard let data = try? Data(contentsOf: url), !containsNulByte(data) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func containsNulByte(_ data: Data) -> Bool {
        data.prefix(binarySniffLength).contains(0)
    }
}
