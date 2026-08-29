import CodeNavigatorContract
import Foundation

/// Finds the Neovim binary to embed.
///
/// Neovim is an external dependency we deliberately do not bundle (REQ-NF-005 / 가정 A), so its
/// absence must be reported at start-up with something a user can act on — never as a silent
/// failure once editing is already expected to work.
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
    private let fileManager = FileManager.default

    init(wellKnownPaths: [String] = NeovimExecutableLocator.defaultWellKnownPaths) {
        self.wellKnownPaths = wellKnownPaths
    }

    /// An explicit override wins, then `PATH`, then the well-known locations.
    func locate(overridePath: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        if let overridePath {
            guard isExecutable(overridePath) else {
                throw NavigatorError.editorUnavailable(reason: "지정한 경로에 실행 가능한 Neovim이 없습니다: \(overridePath)")
            }
            return URL(fileURLWithPath: overridePath)
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
