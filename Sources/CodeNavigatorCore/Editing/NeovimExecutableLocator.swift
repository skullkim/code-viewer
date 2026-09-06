import CodeNavigatorContract
import Foundation

/// Finds the Neovim binary to embed.
///
/// The application ships its own Neovim (REQ-NF-005), so the bundled copy is preferred over
/// anything installed on the machine. That ordering is the point rather than a detail: the whole
/// reason for carrying a 47MB editor is that installing the app is the entire installation, and a
/// machine that happens to have some other Neovim on `PATH` must not quietly swap the editor for
/// a version this application was never measured against.
///
/// An explicit override still wins, so choosing your own build stays possible.
///
/// The search does not stop at the bundle: a corrupt or unsigned nested binary would otherwise
/// take the editor down with it, and the copies already installed are a better answer than an
/// error. Whatever the outcome, absence is reported at start-up with something a user can act on
/// — never as a silent failure once editing is already expected to work.
///
/// `PATH` is not consulted the way a shell would: a GUI application launched from Finder inherits
/// a minimal environment, so the usual install locations are checked directly.
struct NeovimExecutableLocator {
    static let defaultWellKnownPaths = [
        "/opt/homebrew/bin/nvim",
        "/usr/local/bin/nvim",
        "/usr/bin/nvim",
        "/run/current-system/sw/bin/nvim",
    ]

    /// Injectable so a test can describe a machine without Neovim. Without this the fallback
    /// would always find the real binary and the "not installed" path would never be exercised.
    private let wellKnownPaths: [String]

    /// Injectable for the same reason, and for the opposite case: a test that wants to prove the
    /// bundled copy is chosen cannot rely on the real one being present in every environment.
    private let bundledPath: String?

    private let fileManager = FileManager.default

    init(
        wellKnownPaths: [String] = NeovimExecutableLocator.defaultWellKnownPaths,
        bundledPath: String? = NeovimExecutableLocator.bundledExecutablePath()
    ) {
        self.wellKnownPaths = wellKnownPaths
        self.bundledPath = bundledPath
    }

    /// The Neovim carried inside the application, if it is there and can run.
    ///
    /// Two locations, because the application is run two ways. `Bundle.main` is the assembled
    /// `.app` a user launches; the source-relative path is how the tests and `swift run` see the
    /// world, where there is no bundle at all.
    static func bundledExecutablePath() -> String? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("nvim/bin/nvim"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // Editing
                .deletingLastPathComponent()   // CodeNavigatorCore
                .deletingLastPathComponent()   // Sources
                .deletingLastPathComponent()   // repository root
                .appendingPathComponent("Resources/nvim/bin/nvim"),
        ]
        return candidates
            .compactMap { $0?.path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Every place this locator would look, for the failure message.
    func candidatePaths(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        let fromPath = (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/nvim" }
        return [bundledPath].compactMap { $0 } + fromPath + wellKnownPaths
    }

    /// Reads the version by running the binary, because that is the only thing that reports the
    /// build actually installed — a path name tells us nothing.
    func version(of executableURL: URL) -> NeovimVersion? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8),
              let firstLine = output.split(separator: "\n").first
        else {
            return nil
        }
        return NeovimVersion(versionOutput: String(firstLine))
    }

    /// An explicit override wins, then the bundled copy, then `PATH`, then the well-known locations.
    func locate(overridePath: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        if let overridePath {
            guard isExecutable(overridePath) else {
                throw NavigatorError.editorUnavailable(reason: "지정한 경로에 실행 가능한 Neovim이 없습니다: \(overridePath)")
            }
            return URL(fileURLWithPath: overridePath)
        }

        if let bundledPath, isExecutable(bundledPath) {
            return URL(fileURLWithPath: bundledPath)
        }

        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = "\(directory)/nvim"
            if isExecutable(candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        for candidate in wellKnownPaths where isExecutable(candidate) {
            return URL(fileURLWithPath: candidate)
        }

        throw NavigatorError.editorNotInstalled
    }

    private func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return fileManager.isExecutableFile(atPath: path)
    }
}
