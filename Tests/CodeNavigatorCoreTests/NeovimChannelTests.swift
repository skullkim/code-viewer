import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// These tests drive a real Neovim process. Neovim is a hard dependency of the product
/// (REQ-NF-005), so its absence is a failure here rather than a silent skip — a skipped
/// integration test is indistinguishable from a passing one.
@Suite("NeovimChannel — 실제 Neovim 통합", .serialized)
struct NeovimChannelTests {

    private func startChannel(
        environment: [String: String]? = nil,
        arguments: [String] = []
    ) async throws -> NeovimChannel {
        let executable = try NeovimExecutableLocator().locate()
        let channel = NeovimChannel()
        try await channel.start(executableURL: executable, arguments: arguments, environment: environment)
        return channel
    }

    @Test("Neovim 실행 파일을 찾는다")
    func locatesTheNeovimExecutable() throws {
        let executable = try NeovimExecutableLocator().locate()
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
    }

    @Test("설치돼 있지 않으면 명확한 에러다 — 조용한 실패가 아니다")
    func reportsMissingNeovimClearly() {
        let locator = NeovimExecutableLocator(wellKnownPaths: ["/nonexistent/bin/nvim"])
        #expect(throws: NavigatorError.editorNotInstalled) {
            try locator.locate(environment: ["PATH": "/nonexistent/bin"])
        }
    }

    @Test("지정한 경로가 실행 불가면 그 사실을 알린다")
    func reportsUnusableOverridePath() {
        #expect(throws: (any Error).self) {
            try NeovimExecutableLocator().locate(overridePath: "/nonexistent/bin/nvim")
        }
    }

    @Test("요청과 응답이 왕복한다")
    func performsRequestAndResponse() async throws {
        let channel = try await startChannel(arguments: ["--clean", "-n"])
        defer { Task { await channel.terminate() } }

        let result = try await channel.request("nvim_eval", [.string("1+1")])
        #expect(result.integerValue == 2)
    }

    @Test("없는 메서드는 에러로 표면화된다")
    func surfacesErrorsFromNeovim() async throws {
        let channel = try await startChannel(arguments: ["--clean", "-n"])
        defer { Task { await channel.terminate() } }

        await #expect(throws: (any Error).self) {
            try await channel.request("nvim_no_such_method", [])
        }
    }

    @Test("UI를 붙이면 렌더에 필요한 redraw 이벤트가 온다")
    func deliversRedrawEventsAfterAttachingTheUserInterface() async throws {
        let channel = try await startChannel(arguments: ["--clean", "-n"])
        defer { Task { await channel.terminate() } }

        let notifications = await channel.notifications()
        try await channel.request("nvim_ui_attach", [
            .unsignedInteger(80), .unsignedInteger(24),
            .map([MessagePackKeyValuePair(key: .string("ext_linegrid"), value: .boolean(true))]),
        ])

        var seenEventNames: Set<String> = []
        for await notification in notifications {
            guard notification.method == "redraw" else { continue }
            for event in notification.parameters {
                if let name = event.arrayValue?.first?.stringValue {
                    seenEventNames.insert(name)
                }
            }
            if seenEventNames.contains("flush") { break }
        }

        #expect(seenEventNames.contains("grid_resize"))
        #expect(seenEventNames.contains("grid_line"))
        #expect(seenEventNames.contains("flush"))
        #expect(seenEventNames.contains("mode_change"))
    }

    // 입력은 UI가 붙은 뒤에만 처리된다. --embed 는 attach 전까지 시동을 멈추므로,
    // attach 없이 보낸 키는 조용히 아무 일도 하지 않는다 (ADR-0006).
    @Test("키 입력이 버퍼에 반영되고 모드가 전이된다")
    func forwardsKeyInputAndTracksMode() async throws {
        let channel = try await startChannel(arguments: ["--clean", "-n"])
        defer { Task { await channel.terminate() } }

        try await channel.request("nvim_ui_attach", [
            .unsignedInteger(80), .unsignedInteger(24),
            .map([MessagePackKeyValuePair(key: .string("ext_linegrid"), value: .boolean(true))]),
        ])
        try await Task.sleep(for: .milliseconds(200))

        try await channel.request("nvim_input", [.string("ihello from swift")])
        try await Task.sleep(for: .milliseconds(200))

        let insertMode = try await channel.request("nvim_get_mode", [])
        #expect(insertMode.mapValue?.contains { $0.key.stringValue == "mode" && $0.value.stringValue == "i" } == true)

        try await channel.request("nvim_input", [.string("<Esc>")])
        try await Task.sleep(for: .milliseconds(200))

        let line = try await channel.request("nvim_get_current_line", [])
        #expect(line.stringValue == "hello from swift")
    }

    @Test("UI를 붙이기 전 보낸 키는 처리되지 않는다 — 기동 순서가 계약이다")
    func doesNotProcessInputBeforeTheUserInterfaceAttaches() async throws {
        let channel = try await startChannel(arguments: ["--clean", "-n"])
        defer { Task { await channel.terminate() } }

        try await channel.request("nvim_input", [.string("ilost input<Esc>")])
        try await Task.sleep(for: .milliseconds(300))

        let line = try await channel.request("nvim_get_current_line", [])
        #expect(line.stringValue == "")
    }

    @Test("INV-3: 버퍼를 고쳐도 디스크는 그대로고, :w 시점에만 파일이 쓰인다")
    func onlyNeovimWritesAndOnlyOnSave() async throws {
        let fixture = TemporaryProjectFixture()
        let target = fixture.rootURL.appendingPathComponent("Written.kt").path
        let channel = try await startChannel(arguments: ["--clean", "-n"])
        defer { Task { await channel.terminate() } }

        try await channel.request("nvim_command", [.string("edit \(target)")])
        try await channel.request("nvim_buf_set_lines", [
            .unsignedInteger(0), .integer(0), .integer(-1), .boolean(false),
            .array([.string("class WrittenByNeovim")]),
        ])

        #expect(FileManager.default.fileExists(atPath: target) == false)

        try await channel.request("nvim_command", [.string("write")])
        try await Task.sleep(for: .milliseconds(200))

        #expect(FileManager.default.fileExists(atPath: target))
        let written = try String(contentsOfFile: target, encoding: .utf8)
        #expect(written.contains("class WrittenByNeovim"))
    }

    @Test("저장하면 Neovim이 저장된 경로를 알려준다 — 재인덱싱의 신호")
    func reportsSavedPathsThroughAutocommand() async throws {
        let fixture = TemporaryProjectFixture()
        let target = fixture.rootURL.appendingPathComponent("Saved.kt").path
        let channel = try await startChannel(arguments: ["--clean", "-n"])
        defer { Task { await channel.terminate() } }

        let apiInfo = try await channel.request("nvim_get_api_info", [])
        let channelIdentifier = try #require(apiInfo.arrayValue?.first?.integerValue)

        let notifications = await channel.notifications()
        try await channel.request("nvim_exec_lua", [
            .string("""
            local channelIdentifier = ...
            vim.api.nvim_create_autocmd('BufWritePost', {
              callback = function(arguments)
                vim.rpcnotify(channelIdentifier, 'code_navigator_saved', vim.api.nvim_buf_get_name(arguments.buf))
              end
            })
            """),
            .array([.integer(Int64(channelIdentifier))]),
        ])

        try await channel.request("nvim_command", [.string("edit \(target)")])
        try await channel.request("nvim_input", [.string("ifun saved() {}<Esc>")])
        try await Task.sleep(for: .milliseconds(200))
        try await channel.request("nvim_command", [.string("write")])

        var savedPath: String?
        for await notification in notifications where notification.method == "code_navigator_saved" {
            savedPath = notification.parameters.first?.stringValue
            break
        }
        #expect(savedPath?.hasSuffix("Saved.kt") == true)
    }

    @Test("INV-4: 사용자 설정이 그대로 적용된다 — 단, UI를 붙인 뒤에 로드된다")
    func loadsUserConfigurationAfterAttachingTheUserInterface() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("nvim/init.lua", contents: """
        vim.g.code_navigator_test_config_loaded = true
        vim.opt.number = true
        """)

        var environment = ProcessInfo.processInfo.environment
        environment["XDG_CONFIG_HOME"] = fixture.rootURL.path
        let channel = try await startChannel(environment: environment)
        defer { Task { await channel.terminate() } }

        // --embed 는 UI가 붙을 때까지 시동을 멈춘다. 이 시점엔 설정이 아직 실행되지 않았다.
        let beforeAttach = try await channel.request(
            "nvim_eval", [.string("get(g:, 'code_navigator_test_config_loaded', v:false)")]
        )
        #expect(beforeAttach.booleanValue == false)

        try await channel.request("nvim_ui_attach", [
            .unsignedInteger(80), .unsignedInteger(24),
            .map([MessagePackKeyValuePair(key: .string("ext_linegrid"), value: .boolean(true))]),
        ])
        try await Task.sleep(for: .milliseconds(500))

        let afterAttach = try await channel.request(
            "nvim_eval", [.string("get(g:, 'code_navigator_test_config_loaded', v:false)")]
        )
        #expect(afterAttach.booleanValue == true)

        let numberOption = try await channel.request("nvim_get_option_value", [.string("number"), .map([])])
        #expect(numberOption.booleanValue == true)
    }

    @Test("프로세스가 죽으면 감지되고 이후 요청이 즉시 실패한다 — 조용한 먹통 금지")
    func detectsProcessDeathAndFailsFast() async throws {
        let channel = try await startChannel(arguments: ["--clean", "-n"])

        let identifier = await channel.processIdentifier
        kill(identifier, SIGKILL)
        try await Task.sleep(for: .milliseconds(600))

        #expect(await channel.isAlive == false)
        await #expect(throws: (any Error).self) {
            try await channel.request("nvim_eval", [.string("1")], timeout: .seconds(2))
        }
    }
}
