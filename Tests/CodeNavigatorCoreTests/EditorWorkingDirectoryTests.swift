import Testing
import Foundation
@testable import CodeNavigatorCore

/// The editor must not inherit whatever directory the application happened to be launched from.
///
/// Without an explicit working directory the child gets the app's, so `:pwd`, relative paths and
/// anything Neovim reads relative to the current directory are anchored to an accident of how the
/// user started the app. It is also a directory we do not control being handed to an editor, which
/// is the opposite of what INV-6 asks for.
@Suite("편집기 작업 디렉토리 — 앱의 것을 물려받지 않는다", .serialized)
struct EditorWorkingDirectoryTests {

    /// The child's own working directory, as the operating system reports it — not what Neovim
    /// says about itself. `:cd` would change Neovim's answer and hide an inherited spawn.
    private func workingDirectory(ofProcess pid: Int32) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        try? task.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("n") })
            .map { String($0.dropFirst()) }
    }

    @Test("기동한 편집기의 작업 디렉토리가 지정한 프로젝트 루트다")
    func theEditorStartsInTheProjectDirectory() async throws {
        let fixture = TemporaryProjectFixture()
        let executable = try NeovimExecutableLocator().locate()
        let channel = NeovimChannel()

        // `--cmd cd` 를 일부러 주지 않는다. 그걸 주면 물려받은 cwd 를 나중에 덮어써서
        // 검사가 통과하고, 정작 재려던 것(spawn 시점의 디렉토리)은 못 잰다.
        try await channel.start(executableURL: executable, workingDirectory: fixture.rootURL)
        let pid = try #require(await channel.processIdentifier)

        let observed = workingDirectory(ofProcess: pid)
        // `realpath`, not `resolvingSymlinksInPath()`: the latter leaves `/var` unresolved while
        // the operating system reports `/private/var`, so the two would disagree about the same
        // directory. That difference is what let a path check pass on an unresolved path earlier
        // today, so the expectation is computed with the same tool the observation uses.
        let expected = realpath(fixture.rootURL.path, nil).map { pointer -> String in
            defer { free(pointer) }
            return String(cString: pointer)
        }
        #expect(observed == expected, "관측 \(observed ?? "nil") · 기대 \(expected)")

        await channel.terminate()
    }
}
