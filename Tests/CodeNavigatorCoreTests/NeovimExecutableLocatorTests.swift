import Testing
import Foundation
@testable import CodeNavigatorCore

/// The application bundles Neovim so that installing the app is the whole installation. That only
/// holds if the bundled copy is the one actually started — a machine that happens to have another
/// Neovim on `PATH` must not silently switch the editor to a version we never tested against.
@Suite("Neovim 실행 파일 탐색 — 번들된 것을 먼저 쓴다")
struct NeovimExecutableLocatorTests {

    /// A file that passes the "exists and is executable" test without being a real editor. The
    /// locator only decides *which path*; running it is somebody else's job.
    private func makeExecutableStub(named name: String, in directory: URL) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(name).path
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("locator-\(UUID().uuidString)")
    }

    @Test("번들된 Neovim 이 PATH 의 것보다 먼저 선택된다")
    func prefersTheBundledExecutable() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundled = try makeExecutableStub(named: "nvim", in: root.appendingPathComponent("bundled"))
        let onPath = root.appendingPathComponent("on-path")
        _ = try makeExecutableStub(named: "nvim", in: onPath)

        let locator = NeovimExecutableLocator(
            wellKnownPaths: [],
            bundledPath: bundled
        )
        let located = try locator.locate(environment: ["PATH": onPath.path])

        #expect(located.path == bundled)
    }

    @Test("번들된 것이 없으면 예전처럼 PATH 를 본다 — 번들 도입이 기존 경로를 끊지 않는다")
    func fallsBackToPathWithoutABundledCopy() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let onPath = root.appendingPathComponent("on-path")
        let expected = try makeExecutableStub(named: "nvim", in: onPath)

        let locator = NeovimExecutableLocator(wellKnownPaths: [], bundledPath: nil)
        let located = try locator.locate(environment: ["PATH": onPath.path])

        #expect(located.path == expected)
    }

    @Test("지정 경로는 번들보다 우선한다 — 자기 Neovim 을 쓰겠다는 선택을 막지 않는다")
    func overrideStillWinsOverTheBundledCopy() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundled = try makeExecutableStub(named: "nvim", in: root.appendingPathComponent("bundled"))
        let chosen = try makeExecutableStub(named: "nvim", in: root.appendingPathComponent("chosen"))

        let locator = NeovimExecutableLocator(wellKnownPaths: [], bundledPath: bundled)
        let located = try locator.locate(overridePath: chosen, environment: [:])

        #expect(located.path == chosen)
    }

    @Test("실행 불가한 번들 경로는 건너뛴다 — 서명이나 권한이 깨진 번들에서 앱이 멈추지 않는다")
    func skipsABundledPathThatCannotRun() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let onPath = root.appendingPathComponent("on-path")
        let expected = try makeExecutableStub(named: "nvim", in: onPath)

        let locator = NeovimExecutableLocator(
            wellKnownPaths: [],
            bundledPath: root.appendingPathComponent("missing/nvim").path
        )
        let located = try locator.locate(environment: ["PATH": onPath.path])

        #expect(located.path == expected)
    }

    @Test("찾은 곳 목록에 번들 경로가 들어간다 — 실패 메시지가 어디를 봤는지 말해야 한다")
    func reportsTheBundledPathAmongCandidates() {
        let locator = NeovimExecutableLocator(wellKnownPaths: [], bundledPath: "/somewhere/nvim")
        #expect(locator.candidatePaths(environment: [:]).contains("/somewhere/nvim"))
    }

    /// The unit tests above all inject a path, so none of them would notice if the real discovery
    /// stopped finding anything. This one asks the question the user's machine asks.
    @Test("기본 생성자가 실제로 조립된 Resources/nvim 을 찾는다")
    func discoversTheVendoredTree() throws {
        let discovered = try #require(
            NeovimExecutableLocator.bundledExecutablePath(),
            "Resources/nvim 이 없다 — scripts/vendor-neovim.sh 를 먼저 실행하라"
        )
        #expect(discovered.hasSuffix("/nvim/bin/nvim"))
        #expect(FileManager.default.isExecutableFile(atPath: discovered))
    }
}
