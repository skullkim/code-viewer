import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-015 AC-1 · AC-2 · AC-6, INV-7, SC-10
@Suite("Vim 모드 gd / gr (REQ-015)", .serialized)
struct NavigationKeyTests {

    private func makeUserConfiguration(_ lua: String) throws -> URL {
        let configurationHome = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("code-navigator-user-config-\(UUID().uuidString)", isDirectory: true)
        let nvimDirectory = configurationHome.appendingPathComponent("nvim", isDirectory: true)
        try FileManager.default.createDirectory(at: nvimDirectory, withIntermediateDirectories: true)
        try lua.write(
            to: nvimDirectory.appendingPathComponent("init.lua"), atomically: true, encoding: .utf8
        )
        return configurationHome
    }

    /// 다음 내비게이션 요청 하나. 시간 제한을 넘기면 `nil`.
    private func nextRequest(
        from stream: AsyncStream<EditorNavigationRequest>, timeout: Duration = .seconds(3)
    ) async -> EditorNavigationRequest? {
        await withTaskGroup(of: EditorNavigationRequest?.self) { group in
            group.addTask {
                for await request in stream {
                    return request
                }
                return nil
            }
            group.addTask { try? await Task.sleep(for: timeout); return nil }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func outcome(
        _ outcomes: [EditorKeyMappingOutcome], forKeys keys: String
    ) -> EditorKeyMappingOutcome? {
        outcomes.first { $0.keys == keys }
    }

    // MARK: - AC-1 · AC-2

    @Test("gd 는 정의 이동을, gr 은 사용처 목록을 앱에 요청한다")
    func theNavigationKeysAskTheApplicationForTheMatchingAction() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/UserService.ts", contents: "export class UserService {}\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 20)
        defer { Task { await session.shutDown() } }
        try await session.openFile(atRelativePath: "src/UserService.ts", line: 1, recordJump: false)
        _ = try await session.currentLineForTesting()

        let definitionStream = await session.navigationRequests()
        try await session.sendKeys("gd")
        #expect(await nextRequest(from: definitionStream) == .goToDefinition)

        let referenceStream = await session.navigationRequests()
        try await session.sendKeys("gr")
        #expect(await nextRequest(from: referenceStream) == .findReferences)
    }

    /// `gr` 은 Neovim 0.12 기본 `gr*` 매핑군의 접두라서, 그것을 그대로 두면 `timeoutlen` 만큼
    /// 기다린 뒤에야 발화한다(실측 1,032ms). 요구가 원한 것은 빠른 키다.
    @Test("gr 이 접두 대기 없이 발화한다")
    func findingReferencesDoesNotWaitOutTheMappingTimeout() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("a.ts", contents: "const UserService = 1;\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 20)
        defer { Task { await session.shutDown() } }

        let timeoutLength = Int(
            try await session.executeLuaForTesting("return tostring(vim.o.timeoutlen)")
        ) ?? 1000

        let stream = await session.navigationRequests()
        let startedAt = Date()
        try await session.sendKeys("gr")
        let request = await nextRequest(from: stream)
        let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)

        #expect(request == .findReferences)
        #expect(
            elapsedMilliseconds < timeoutLength / 2,
            "gr 이 \(elapsedMilliseconds)ms 걸렸다 (timeoutlen \(timeoutLength)ms) — 접두 충돌이 남아 있다"
        )
    }

    @Test("사용자 설정이 없으면 두 키 모두 우리가 심는다")
    func bothKeysAreInstalledOnAStockConfiguration() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("a.ts", contents: "const a = 1;\n")
        let configurationHome = try makeUserConfiguration("-- 아무 매핑도 없다\n")
        defer { try? FileManager.default.removeItem(at: configurationHome) }

        let session = NeovimEditorSession()
        try await session.startWithUserConfigurationForTesting(
            configurationHome: configurationHome, projectRoot: fixture.rootURL, columns: 80, rows: 20
        )
        defer { Task { await session.shutDown() } }

        let outcomes = await session.navigationKeyMappingOutcomes()
        #expect(outcomes.count == 2)
        #expect(outcome(outcomes, forKeys: "gd")?.resolution == .installed)
        #expect(outcome(outcomes, forKeys: "gr")?.resolution == .installed)
        #expect(outcome(outcomes, forKeys: "gd")?.request == .goToDefinition)
        #expect(outcome(outcomes, forKeys: "gr")?.request == .findReferences)
        #expect(outcome(outcomes, forKeys: "gd")?.userScriptPath == nil)
    }

    // MARK: - AC-6

    @Test("사용자가 gd 를 매핑해 뒀으면 우리 것을 심지 않는다")
    func aUserMappingKeepsItsKey() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("a.ts", contents: "const a = 1;\n")
        let configurationHome = try makeUserConfiguration(
            "vim.keymap.set('n', 'gd', function() vim.g.user_gd_ran = true end, { desc = 'mine' })\n"
        )
        defer { try? FileManager.default.removeItem(at: configurationHome) }

        let session = NeovimEditorSession()
        try await session.startWithUserConfigurationForTesting(
            configurationHome: configurationHome, projectRoot: fixture.rootURL, columns: 80, rows: 20
        )
        defer { Task { await session.shutDown() } }

        let outcomes = await session.navigationKeyMappingOutcomes()
        let definitionOutcome = try #require(outcome(outcomes, forKeys: "gd"))
        #expect(definitionOutcome.resolution == .deferredToUserMapping)
        #expect(
            definitionOutcome.userScriptPath?.hasSuffix("init.lua") == true,
            "어느 파일이 이겼는지 남지 않았다: \(String(describing: definitionOutcome.userScriptPath))"
        )

        // gr 은 사용자가 안 건드렸으므로 우리 것이 산다 — 한 키의 양보가 다른 키를 끌고 가지 않는다.
        #expect(outcome(outcomes, forKeys: "gr")?.resolution == .installed)

        // 눌러 보면 사용자 것이 돈다. 판정만 맞고 동작이 다르면 판정이 거짓이다.
        let stream = await session.navigationRequests()
        try await session.sendKeys("gd")
        #expect(await nextRequest(from: stream, timeout: .milliseconds(800)) == nil)
        #expect(try await session.executeLuaForTesting("return tostring(vim.g.user_gd_ran)") == "true")
    }

    @Test("사용자가 gr 계열을 직접 매핑했으면 그것을 지우지 않는다")
    func aUserDefinedPrefixedMappingSurvives() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("a.ts", contents: "const a = 1;\n")
        let configurationHome = try makeUserConfiguration(
            "vim.keymap.set('n', 'grr', function() end, { desc = 'my own grr' })\n"
        )
        defer { try? FileManager.default.removeItem(at: configurationHome) }

        let session = NeovimEditorSession()
        try await session.startWithUserConfigurationForTesting(
            configurationHome: configurationHome, projectRoot: fixture.rootURL, columns: 80, rows: 20
        )
        defer { Task { await session.shutDown() } }

        let description = try await session.executeLuaForTesting(
            "return tostring(vim.fn.maparg('grr', 'n', false, true).desc)"
        )
        #expect(description == "my own grr", "사용자의 grr 이 사라졌다: \(description)")
    }

    /// AC-7·AC-8 의 충돌 지점. 사용자가 `gr` 로 시작하는 자기 매핑을 갖고 있으면:
    ///
    /// - 그것을 지우면 AC-6(사용자 매핑 보호)이 깨진다.
    /// - 두면 우리 `gr` 이 그 접두사라 `timeoutlen` 만큼 멈춘다 — 실측 1,032ms.
    ///
    /// **둘 다 만족하는 길이 없다.** 사용자 것이 이기고, 우리는 `gr` 을 심지 않는다.
    /// 그리고 **조용히 안 하지 않는다** — 왜 없는지가 판정으로 남아야 앱이 말할 수 있다.
    @Test("사용자가 gr 계열을 갖고 있으면 gr 을 심지 않고, 왜인지를 남긴다")
    func aUserPrefixMappingWithholdsOurKeyAndSaysSo() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("a.ts", contents: "const a = 1;\n")
        let configurationHome = try makeUserConfiguration(
            "vim.keymap.set('n', 'grr', function() vim.g.user_grr_ran = true end, { desc = 'mine' })\n"
        )
        defer { try? FileManager.default.removeItem(at: configurationHome) }

        let session = NeovimEditorSession()
        try await session.startWithUserConfigurationForTesting(
            configurationHome: configurationHome, projectRoot: fixture.rootURL, columns: 80, rows: 20
        )
        defer { Task { await session.shutDown() } }

        let outcomes = await session.navigationKeyMappingOutcomes()
        let referenceOutcome = try #require(outcome(outcomes, forKeys: "gr"))

        // "사용자가 이 키를 갖고 있다"와 "사용자가 이 키로 시작하는 다른 키를 갖고 있다"는
        // 다른 사실이다. 하나로 뭉개면 앱이 정확한 이유를 말할 수 없다.
        #expect(referenceOutcome.resolution == .withheldToKeepUserPrefixKeys)
        #expect(referenceOutcome.conflictingKeys == ["grr"])
        #expect(referenceOutcome.userScriptPath?.hasSuffix("init.lua") == true)

        // 사용자의 grr 은 살아 있다 (AC-6).
        #expect(
            try await session.executeLuaForTesting(
                "return tostring(vim.fn.maparg('grr', 'n', false, true).desc)"
            ) == "mine"
        )

        // 우리 gr 은 없다 — 심지 않기로 했으니 눌러도 아무 신호가 없어야 한다.
        let stream = await session.navigationRequests()
        try await session.sendKeys("gr")
        #expect(await nextRequest(from: stream, timeout: .milliseconds(800)) == nil)

        // gd 는 영향받지 않는다. 한 키의 양보가 다른 키를 끌고 가지 않는다.
        #expect(outcome(outcomes, forKeys: "gd")?.resolution == .installed)
    }

    @Test("Neovim 기본 gr 계열만 있으면 그것만 지우고 우리 것을 심는다")
    func onlyTheEditorsOwnPrefixKeysAreRemoved() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("a.ts", contents: "const a = 1;\n")
        let configurationHome = try makeUserConfiguration("-- 사용자 매핑 없음\n")
        defer { try? FileManager.default.removeItem(at: configurationHome) }

        let session = NeovimEditorSession()
        try await session.startWithUserConfigurationForTesting(
            configurationHome: configurationHome, projectRoot: fixture.rootURL, columns: 80, rows: 20
        )
        defer { Task { await session.shutDown() } }

        let referenceOutcome = try #require(
            outcome(await session.navigationKeyMappingOutcomes(), forKeys: "gr")
        )
        #expect(referenceOutcome.resolution == .installed)
        #expect(referenceOutcome.conflictingKeys.isEmpty)
    }

    /// 계약이 "빈 문자열을 돌려주지 않는다"고 적었으니 그것을 고정한다.
    ///
    /// 프론트의 참조 검색 가드가 이 보증 위에 서 있다 — 라우터의 `if let` 만으로는 `""` 가
    /// 통과해 **빈 이름으로 검색이 돌아간다**(결과 0건, 에러 없음, 사용자에게는 침묵).
    /// 계약에 적히지 않은 의존이던 것을 적었으니, 이제 테스트가 지킨다.
    @Test("커서 아래가 비어 있으면 빈 문자열이 아니라 nil 이다")
    func theWordUnderTheCursorIsNeverAnEmptyString() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("blank.ts", contents: "\n\n\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 12)
        defer { Task { await session.shutDown() } }
        try await session.openFile(atRelativePath: "blank.ts", line: 1, recordJump: false)
        _ = try await session.currentLineForTesting()

        let word = try await session.wordUnderCursor()
        #expect(word == nil, "빈 줄에서 '\(word ?? "")' 를 돌려줬다")

        // 반대 방향 — 심볼이 있으면 그것을 돌려준다. 항상 nil 이어도 위 단언은 통과한다.
        fixture.write("named.ts", contents: "const alpha = 1;\n")
        try await session.openFile(atRelativePath: "named.ts", line: 1, recordJump: false)
        _ = try await session.currentLineForTesting()
        _ = try await session.executeLuaForTesting(
            "vim.api.nvim_win_set_cursor(0, { 1, 6 }) return 'moved'"
        )
        #expect(try await session.wordUnderCursor() == "alpha")
    }

    // MARK: - INV-7

    @Test("사용자 설정 파일을 수정하지 않는다")
    func theUsersConfigurationFileIsNeverWritten() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("a.ts", contents: "const a = 1;\n")
        let originalContents = "vim.keymap.set('n', 'gd', function() end)\n-- 한 글자도 바뀌면 안 된다\n"
        let configurationHome = try makeUserConfiguration(originalContents)
        defer { try? FileManager.default.removeItem(at: configurationHome) }

        let configurationFile = configurationHome
            .appendingPathComponent("nvim", isDirectory: true)
            .appendingPathComponent("init.lua")
        let modifiedBefore = try FileManager.default
            .attributesOfItem(atPath: configurationFile.path)[.modificationDate] as? Date

        let session = NeovimEditorSession()
        try await session.startWithUserConfigurationForTesting(
            configurationHome: configurationHome, projectRoot: fixture.rootURL, columns: 80, rows: 20
        )
        try await session.sendKeys("gd")
        _ = try await session.currentLineForTesting()
        await session.shutDown()

        let contentsAfter = try String(contentsOf: configurationFile, encoding: .utf8)
        let modifiedAfter = try FileManager.default
            .attributesOfItem(atPath: configurationFile.path)[.modificationDate] as? Date

        #expect(contentsAfter == originalContents)
        #expect(modifiedBefore == modifiedAfter)
    }

    @Test("매핑은 세션 안에만 있다 — 우리 것이 사용자 설정 디렉토리에 파일을 만들지 않는다")
    func nothingIsWrittenIntoTheConfigurationDirectory() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("a.ts", contents: "const a = 1;\n")
        let configurationHome = try makeUserConfiguration("-- 비어 있다\n")
        defer { try? FileManager.default.removeItem(at: configurationHome) }

        let nvimDirectory = configurationHome.appendingPathComponent("nvim", isDirectory: true)
        let before = try FileManager.default.contentsOfDirectory(atPath: nvimDirectory.path).sorted()

        let session = NeovimEditorSession()
        try await session.startWithUserConfigurationForTesting(
            configurationHome: configurationHome, projectRoot: fixture.rootURL, columns: 80, rows: 20
        )
        try await session.sendKeys("gd")
        _ = try await session.currentLineForTesting()
        await session.shutDown()

        let after = try FileManager.default.contentsOfDirectory(atPath: nvimDirectory.path).sorted()
        #expect(before == after, "설정 디렉토리 내용이 바뀌었다: \(before) → \(after)")
    }
}
