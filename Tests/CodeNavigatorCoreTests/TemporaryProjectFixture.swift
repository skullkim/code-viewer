import Foundation

/// Builds a throwaway directory tree for scanner and watcher tests, and removes it afterwards.
///
/// The root is resolved through `realpath` because macOS reports `/tmp` as `/private/tmp`, and a
/// test that compares unresolved paths would pass or fail for the wrong reason.
final class TemporaryProjectFixture {
    let rootURL: URL

    init(name: String = UUID().uuidString) {
        // Touched here because every test that starts an editor builds a fixture first, and this
        // has to happen before the first spawn. See the type for what it protects.
        NeovimTestStateIsolation.applied

        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("code-navigator-tests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.rootURL = URL(fileURLWithPath: base.path.resolvedRealPath(), isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    @discardableResult
    func write(_ relativePath: String, contents: String = "") -> URL {
        let fileURL = rootURL.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makeDirectory(_ relativePath: String) {
        try? FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent(relativePath),
            withIntermediateDirectories: true
        )
    }

    func remove(_ relativePath: String) {
        try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(relativePath))
    }

    func makeSymbolicLink(at relativePath: String, pointingTo target: String) {
        let linkURL = rootURL.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(
            at: linkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: target)
    }
}

private extension String {
    func resolvedRealPath() -> String {
        guard let resolved = realpath(self, nil) else { return self }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
