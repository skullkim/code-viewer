import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// ADR-0010·0011·0012 이 딛고 선 **환경 사실**을 고정한다.
///
/// 세 결정이 전부 "Neovim 이 지금 이렇게 동작한다"에 기대고 있다. 그 사실이 조용히 바뀌면
/// 결정의 근거가 사라지는데, 기능 테스트는 그때도 초록일 수 있다 — 우리 코드는 여전히
/// 우리가 짠 대로 돌기 때문이다. 여기서 깨지는 것이 알림이다.
///
/// ⚠ **그리드를 근거로 판정할 때는 `revision` 기준선을 잡는다.** `gridUpdates()` 는 구독 즉시
/// 마지막 프레임을 replay 하므로(`EventBroadcaster`), 기준선 없이 읽으면 **행동 이전의 프레임**을
/// 보고 "아무것도 안 변했다"고 판정한다. 이 스파이크의 1차 측정이 실제로 그렇게 틀렸고,
/// "앱이 색을 덮어도 안 이긴다"는 **반대 결론**을 냈다. 낡은 프레임은 정확히 "변하지 않음"처럼 보인다.

/// Neovim as it ships, before this application has configured anything.
///
/// The environment assumptions are claims about **Neovim's** behaviour. Measuring them through
/// `NeovimEditorSession` measures us instead — and that is not hypothetical: the moment the
/// allow-list and the `gd`/`gr` installation landed, this suite started reporting "Python is not
/// coloured" and "`grr` does not exist". Both were true *of our session* and false of the editor,
/// and a suite that cannot tell those apart is one that will miss the day Neovim really changes.
private final class BareEditor: Sendable {
    private let channel = NeovimChannel()

    func start(projectRoot: URL, configurationHome: URL? = nil) async throws {
        var environment: [String: String]?
        if let configurationHome {
            var copied = ProcessInfo.processInfo.environment
            copied["XDG_CONFIG_HOME"] = configurationHome.path
            environment = copied
        }

        try await channel.start(
            executableURL: try NeovimExecutableLocator().locate(),
            arguments: ["--cmd", "cd \(projectRoot.path)"],
            environment: environment,
            workingDirectory: projectRoot
        )
        // Without attaching, the user's configuration never runs and input is ignored (ADR-0006).
        _ = try await channel.request("nvim_ui_attach", [
            .integer(80), .integer(24),
            .map([
                MessagePackKeyValuePair(key: .string("ext_linegrid"), value: .boolean(true)),
                MessagePackKeyValuePair(key: .string("rgb"), value: .boolean(true)),
            ]),
        ])
    }

    @discardableResult
    func lua(_ script: String) async throws -> String {
        let value = try await channel.request("nvim_exec_lua", [.string(script), .array([])])
        return value.stringValue ?? ""
    }

    func input(_ keys: String) async throws {
        _ = try await channel.request("nvim_input", [.string(keys)])
    }

    func shutDown() async {
        await channel.terminate()
    }
}

@Suite("증분 3 환경 가정 (ADR-0010·0011·0012)", .serialized)
struct Increment3EnvironmentAssumptionsTests {

    // MARK: - 그리드 관측

    private func currentRevision(_ session: NeovimEditorSession) async -> UInt64 {
        for await snapshot in await session.gridUpdates() {
            return snapshot.revision
        }
        return 0
    }

    /// 기준선 이후에 그려진, 표지를 담은 프레임.
    private func freshSnapshot(
        _ session: NeovimEditorSession,
        containing marker: String,
        newerThan baseline: UInt64,
        performing action: () async throws -> Void
    ) async throws -> EditorGridSnapshot {
        try await action()
        let stream = await session.gridUpdates()
        let found = await withTaskGroup(of: EditorGridSnapshot?.self) { group in
            group.addTask {
                for await snapshot in stream
                where snapshot.revision > baseline
                    && snapshot.lines.contains(where: { $0.plainText.contains(marker) }) {
                    return snapshot
                }
                return nil
            }
            group.addTask { try? await Task.sleep(for: .seconds(8)); return nil }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
        guard let found else {
            throw NavigatorError.editorUnavailable(
                reason: "'\(marker)' 를 담은 revision>\(baseline) 프레임이 오지 않았다"
            )
        }
        return found
    }

    /// 표지가 있는 줄에서 첫 조각의 전경색. 색이 없으면 `nil`.
    private func foreground(
        in snapshot: EditorGridSnapshot, onLineContaining marker: String
    ) -> EditorColor? {
        snapshot.lines
            .first { $0.plainText.contains(marker) }?
            .runs
            .first { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }?
            .style.foreground
    }

    private func backgroundCellCount(_ snapshot: EditorGridSnapshot) -> Int {
        snapshot.lines.reduce(0) { total, line in
            total + line.runs.filter { $0.style.background != nil }.reduce(0) { $0 + $1.cellWidth }
        }
    }

    // MARK: - ADR-0010 구문 강조의 출처

    @Test("nvim 은 지원 3언어의 구문 파일을 갖고 있고, 강조를 이미 켜 둔다")
    func neovimShipsSyntaxForEverySupportedLanguage() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("A.java", contents: "public class A { private int count = 1; }\n")
        fixture.write("B.kt", contents: "class B { private val count: Int = 1 }\n")
        fixture.write("C.ts", contents: "export class C { private count: number = 1; }\n")

        let editor = BareEditor()
        try await editor.start(projectRoot: fixture.rootURL)
        defer { Task { await editor.shutDown() } }

        for (name, expectedFileType) in [("A.java", "java"), ("B.kt", "kotlin"), ("C.ts", "typescript")] {
            let facts = try await editor.lua("""
            vim.cmd('edit \(name)')
            local buffer = vim.api.nvim_get_current_buf()
            return vim.bo[buffer].filetype .. ' '
              .. #vim.api.nvim_get_runtime_file('syntax/' .. vim.bo[buffer].filetype .. '.vim', true)
              .. ' ' .. tostring(vim.g.syntax_on)
            """)
            let parts = facts.split(separator: " ").map(String.init)
            #expect(parts[0] == expectedFileType, "\(name): 파일타입이 \(parts[0])")
            #expect((Int(parts[1]) ?? 0) >= 1, "\(name): 구문 파일이 없다 — ADR-0010 의 ① 이 성립하지 않는다")
            #expect(parts[2] == "1", "\(name): syntax 가 꺼져 있다")
        }
    }

    @Test("nvim 이 판정한 색이 계약의 EditorTextStyle 까지 온다")
    func syntaxColoursReachTheContract() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("c.ts", contents: """
        // MARKERCOMMENT
        const value: string = "MARKERSTRING";
        """)
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 12)
        defer { Task { await session.shutDown() } }

        let baseline = await currentRevision(session)
        let snapshot = try await freshSnapshot(session, containing: "MARKERCOMMENT", newerThan: baseline) {
            try await session.openFile(atRelativePath: "c.ts", line: nil, recordJump: false)
        }

        let commentColour = foreground(in: snapshot, onLineContaining: "MARKERCOMMENT")
        let stringLineColours = Set(
            (snapshot.lines.first { $0.plainText.contains("MARKERSTRING") }?.runs ?? [])
                .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { $0.style.foreground }
        )

        #expect(commentColour != nil, "주석에 색이 붙지 않았다 — 강조가 계약까지 오지 않는다")
        #expect(commentColour != snapshot.defaultForeground, "주석 색이 기본 전경색과 같다")
        #expect(stringLineColours.count >= 2, "한 줄 안에서 색이 갈리지 않는다: \(stringLineColours.count)종")
    }

    @Test("앱이 nvim_set_hl 로 바른 색이 사용자 colorscheme 을 이긴다")
    func applicationPaletteWinsOverTheColourScheme() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("h.ts", contents: "// MARKERHL\nconst a = 1;\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 12)
        defer { Task { await session.shutDown() } }

        let openBaseline = await currentRevision(session)
        let before = try await freshSnapshot(session, containing: "MARKERHL", newerThan: openBaseline) {
            try await session.openFile(atRelativePath: "h.ts", line: nil, recordJump: false)
        }
        let colourBefore = foreground(in: before, onLineContaining: "MARKERHL")

        let overrideBaseline = await currentRevision(session)
        let after = try await freshSnapshot(session, containing: "MARKERHL", newerThan: overrideBaseline) {
            _ = try await session.executeLuaForTesting("""
            vim.api.nvim_set_hl(0, 'Comment', { fg = 0xFF00FF })
            vim.cmd('redraw!')
            return 'applied'
            """)
        }
        let colourAfter = foreground(in: after, onLineContaining: "MARKERHL")

        #expect(colourBefore != nil)
        #expect(
            colourAfter == EditorColor(packedRGB: 0xFF00FF),
            "앱이 바른 색이 화면에 오지 않았다 (\(String(describing: colourAfter))) — ADR-0010 의 AC-3·AC-6 근거가 무너진다"
        )
    }

    /// `synID` 로 잰다 — 그리드의 색이 아니라 **Neovim 자신의 판정**이다. 우리 세션은 허용목록으로
    /// 파이썬의 syntax 를 끄므로, 여기서 그리드를 보면 우리 설정을 재게 된다.
    @Test("파이썬은 기본으로 칠해지고, 버퍼 단위 syntax=OFF 가 그것을 지운다")
    func turningSyntaxOffMakesABufferPlain() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("p.py", contents: "greeting = \"hello\"\n")

        let editor = BareEditor()
        try await editor.start(projectRoot: fixture.rootURL)
        defer { Task { await editor.shutDown() } }

        // 1행 12열은 문자열 리터럴 안이다.
        let asShipped = try await editor.lua("""
        vim.cmd('edit p.py')
        return vim.bo.filetype .. '|' .. tostring(vim.fn.synID(1, 12, 1) ~= 0)
        """)
        #expect(
            asShipped == "python|true",
            "파이썬이 기본으로 안 칠해진다면 AC-4 는 우리가 할 일이 없다는 뜻이다 — 전제가 바뀌었다: \(asShipped)"
        )

        let afterTurningOff = try await editor.lua("""
        vim.bo.syntax = 'OFF'
        return tostring(vim.fn.synID(1, 12, 1) ~= 0)
        """)
        #expect(
            afterTurningOff == "false",
            "syntax=OFF 인데 구문 판정이 남아 있다 — AC-4 를 이 방법으로 만족시킬 수 없다"
        )
    }

    // MARK: - ADR-0011 내비게이션 키

    @Test("사용자 매핑·Neovim 기본 매핑·없음 이 서로 다른 값으로 구별된다")
    func userMappingsAreDistinguishableFromEditorDefaults() async throws {
        let configurationHome = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("code-navigator-assumption-config-\(UUID().uuidString)", isDirectory: true)
        let nvimDirectory = configurationHome.appendingPathComponent("nvim", isDirectory: true)
        try FileManager.default.createDirectory(at: nvimDirectory, withIntermediateDirectories: true)
        try "vim.keymap.set('n', 'gd', function() end, { desc = 'user gd' })\n"
            .write(to: nvimDirectory.appendingPathComponent("init.lua"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configurationHome) }

        let fixture = TemporaryProjectFixture()
        fixture.write("a.ts", contents: "const a = 1;\n")

        let editor = BareEditor()
        try await editor.start(projectRoot: fixture.rootURL, configurationHome: configurationHome)
        defer { Task { await editor.shutDown() } }

        // 판정은 "설정 디렉토리 밑인가"가 아니라 "**Neovim 런타임 밖인가**"로 한다.
        // macOS 에서 설정 경로 접두 비교는 심링크에 걸려 조용히 실패한다 — 실측:
        // stdpath('config')=/var/… 인데 스크립트 이름은 /private/var/… 라 접두가 안 맞았다.
        // 사용자가 dotfiles 를 심링크로 거는 것은 흔한 일이므로 이 실패는 실사용에서도 난다.
        func describe(_ keys: String) async throws -> String {
            try await editor.lua("""
            local map = vim.fn.maparg('\(keys)', 'n', false, true)
            if vim.tbl_isempty(map) then return 'absent' end
            if type(map.sid) ~= 'number' or map.sid <= 0 then return 'editorDefault' end
            local info = vim.fn.getscriptinfo({ sid = map.sid })[1]
            if not info or info.name == '' then return 'editorDefault' end
            local function resolved(path)
              return vim.uv.fs_realpath(path) or path
            end
            local scriptPath = resolved(info.name)
            local runtimePath = resolved(vim.env.VIMRUNTIME or '')
            if runtimePath ~= '' and scriptPath:find(runtimePath, 1, true) == 1 then
              return 'editorDefault'
            end
            return 'user'
            """)
        }

        #expect(try await describe("gd") == "user", "사용자 init.lua 의 gd 가 사용자 것으로 안 읽힌다 — AC-6 이 성립하지 않는다")
        #expect(try await describe("grr") == "editorDefault", "Neovim 기본 grr 이 기본으로 안 읽힌다")
        #expect(try await describe("gr") == "absent", "gr 이 비어 있지 않다")
    }

    @Test("gr 은 Neovim 기본 gr* 접두 때문에 지연되고, 그것을 지우면 즉시 발화한다")
    func theEditorDefaultPrefixFamilyDelaysPlainGr() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("a.ts", contents: "const a = 1;\n")

        let editor = BareEditor()
        try await editor.start(projectRoot: fixture.rootURL)
        defer { Task { await editor.shutDown() } }

        let timeoutLength = Int(try await editor.lua("return tostring(vim.o.timeoutlen)")) ?? 1000
        let defaultFamily = try await editor.lua("""
        local names = {}
        for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
          if map.lhs:sub(1, 2) == 'gr' then names[#names + 1] = map.lhs end
        end
        table.sort(names)
        return table.concat(names, ',')
        """)
        #expect(defaultFamily.contains("grr"), "gr* 기본군이 없다 — 이 지연은 더 이상 존재하지 않는다")

        try await editor.lua("vim.keymap.set('n', 'gr', function() vim.g.fired = 1 end) return 'set'")

        func timeUntilFired() async throws -> Int {
            try await editor.lua("vim.g.fired = nil return 'cleared'")
            let startedAt = Date()
            try await editor.input("gr")
            for _ in 0..<80 {
                if try await editor.lua("return tostring(vim.g.fired)") != "nil" {
                    return Int(Date().timeIntervalSince(startedAt) * 1000)
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
            return -1
        }

        let delayedMilliseconds = try await timeUntilFired()

        try await editor.lua("""
        for _, lhs in ipairs({ 'grr', 'gra', 'gri', 'grn', 'grt', 'grx' }) do
          pcall(vim.keymap.del, 'n', lhs)
        end
        return 'removed'
        """)
        let promptMilliseconds = try await timeUntilFired()

        #expect(
            delayedMilliseconds >= timeoutLength / 2,
            "gr 이 \(delayedMilliseconds)ms 만에 발화했다 — 접두 지연이 사라졌다면 ADR-0011 의 삭제 결정은 근거를 잃는다"
        )
        #expect(
            promptMilliseconds >= 0 && promptMilliseconds < delayedMilliseconds / 2,
            "기본군을 지웠는데도 gr 이 \(promptMilliseconds)ms 걸린다 — 지연의 원인이 접두가 아니다"
        )
        #expect(
            try await editor.lua("return tostring(#vim.lsp.get_clients())") == "0",
            "LSP 클라이언트가 붙어 있다 — 기본 gr* 를 지우는 것이 더 이상 무해하지 않다"
        )
    }

    @Test("낱말 종류별로 nvim 이 어떤 표준 그룹을 주는지 잰다")
    func measureWhichStandardGroupsWordsResolveTo() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("g.ts", contents: """
        class UserService {}
        const alpha: string = "x";
        function beta(gamma: number) { return gamma; }
        """)
        let editor = BareEditor()
        try await editor.start(projectRoot: fixture.rootURL)
        defer { Task { await editor.shutDown() } }

        let report = try await editor.lua("""
        vim.cmd('edit g.ts')
        local targets = {
          { 'class',       1, 1 },
          { 'UserService', 1, 7 },
          { 'const',       2, 1 },
          { 'alpha',       2, 7 },
          { 'string',      2, 14 },
          { 'function',    3, 1 },
          { 'beta',        3, 10 },
          { 'gamma',       3, 15 },
        }
        local lines = {}
        for _, target in ipairs(targets) do
          local name, row, column = target[1], target[2], target[3]
          local group = vim.fn.synIDattr(
            vim.fn.synIDtrans(vim.fn.synID(row, column, 1)), 'name'
          )
          lines[#lines + 1] = name .. '=' .. (group == '' and '<없음>' or group)
        end
        return table.concat(lines, '  ')
        """)
        print("\n═══ 낱말 → 표준 그룹 ═══\n  \(report)\n════════════════════════")
    }

    // MARK: - matchadd 의 합성 규칙 (PD 요청)

    /// `matchadd` 배경이 구문 전경색을 **유지하나 덮나**.
    ///
    /// nvim 문서는 *"a match will always overrule syntax highlighting"* 이라고만 적고
    /// **병합인지 치환인지 가르지 않는다.** 갈리는 것이 크다 — 치환이면 같은 심볼 강조 그룹에
    /// 전경색까지 줘야 하고, 안 주면 강조된 심볼만 색을 잃는다.
    @Test("matchadd 배경이 구문 전경색을 유지하는가 (병합/치환)")
    func matchBackgroundEitherKeepsOrReplacesTheSyntaxForeground() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("m.ts", contents: "const alpha = 1;\nconst bravo = 2;\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 70, rows: 12)
        defer { Task { await session.shutDown() } }

        let keywordColour = EditorColor(packedRGB: 0xC792EA)
        let matchBackground = EditorColor(packedRGB: 0x343438)
        try await session.applySyntaxPalette(
            EditorSyntaxPalette(
                keyword: keywordColour,
                type: EditorColor(packedRGB: 0x57C7B8),
                function: EditorColor(packedRGB: 0x82AAFF),
                string: EditorColor(packedRGB: 0xC3E88D),
                number: EditorColor(packedRGB: 0xF78C6C),
                comment: EditorColor(packedRGB: 0x8B92A0),
                keywordIsBold: true,
                normalForeground: EditorColor(packedRGB: 0xE8E8ED),
                normalBackground: EditorColor(packedRGB: 0x1B1B1F),
                sameSymbolBackground: matchBackground,
                selectionBackground: EditorColor(packedRGB: 0x233043)
            )
        )
        try await session.openFile(atRelativePath: "m.ts", line: 1, recordJump: false)

        // 강조 전: `const` 는 팔레트의 키워드 색이다.
        let beforeBaseline = await currentRevision(session)
        let before = try await freshSnapshot(session, containing: "const", newerThan: beforeBaseline) {
            _ = try await session.executeLuaForTesting("vim.cmd('redraw!') return 'r'")
        }
        let beforeRun = try #require(before.lines
            .flatMap(\.runs).first { $0.text.contains("const") })
        #expect(beforeRun.style.foreground == keywordColour, "전제가 깨졌다 — 팔레트가 안 발렸다")

        // 구문색이 붙은 바로 그 낱말에 match 를 건다.
        let afterBaseline = await currentRevision(session)
        let after = try await freshSnapshot(session, containing: "const", newerThan: afterBaseline) {
            _ = try await session.executeLuaForTesting("""
            vim.fn.matchadd('\(NeovimHighlightScript.sameSymbolGroup)', [[\\<const\\>]], -1)
            vim.cmd('redraw!')
            return 'matched'
            """)
        }
        let afterRun = try #require(after.lines
            .flatMap(\.runs).first { $0.text.contains("const") })

        let keptForeground = afterRun.style.foreground == keywordColour
        print("""

        ═══ matchadd 합성 규칙 ═══
          강조 전 fg=\(String(describing: beforeRun.style.foreground)) bg=\(String(describing: beforeRun.style.background))
          강조 후 fg=\(String(describing: afterRun.style.foreground)) bg=\(String(describing: afterRun.style.background))
          → 전경 \(keptForeground ? "유지(병합)" : "덮임(치환)")
        ══════════════════════════
        """)

        #expect(afterRun.style.background == matchBackground, "match 배경이 화면에 안 왔다")
        #expect(
            keptForeground,
            "matchadd 가 구문 전경색을 덮는다 — 같은 심볼 강조 그룹에 전경색도 줘야 한다 (PD 통지 필요)"
        )
    }

    /// 드래그 선택과 커서 아래 심볼 강조는 **동시에 뜰 수 있다.** 문서가 승자를 안 밝힌다.
    @Test("선택이 같은 심볼 강조를 이기는가")
    func theSelectionOutranksTheSameSymbolHighlight() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("s.ts", contents: "const alpha = 1;\nconst alpha2 = alpha;\nconst gamma = 3;\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 70, rows: 12)
        defer { Task { await session.shutDown() } }

        let matchBackground = EditorColor(packedRGB: 0x343438)
        let selectionBackground = EditorColor(packedRGB: 0x233043)
        try await session.applySyntaxPalette(
            EditorSyntaxPalette(
                keyword: EditorColor(packedRGB: 0xC792EA),
                type: EditorColor(packedRGB: 0x57C7B8),
                function: EditorColor(packedRGB: 0x82AAFF),
                string: EditorColor(packedRGB: 0xC3E88D),
                number: EditorColor(packedRGB: 0xF78C6C),
                comment: EditorColor(packedRGB: 0x8B92A0),
                keywordIsBold: true,
                normalForeground: EditorColor(packedRGB: 0xE8E8ED),
                normalBackground: EditorColor(packedRGB: 0x1B1B1F),
                sameSymbolBackground: matchBackground,
                selectionBackground: selectionBackground
            )
        )
        try await session.openFile(atRelativePath: "s.ts", line: 1, recordJump: false)
        _ = try await session.currentLineForTesting()

        // `alpha` 에 match 를 걸어 두고, 그 위를 드래그로 덮는다.
        _ = try await session.executeLuaForTesting("""
        vim.fn.matchadd('\(NeovimHighlightScript.sameSymbolGroup)', [[\\<alpha\\>]], -1)
        return 'matched'
        """)

        let baseline = await currentRevision(session)
        let snapshot = try await freshSnapshot(session, containing: "alpha", newerThan: baseline) {
            try await session.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 0, column: 6))
            _ = try await session.currentLineForTesting()
            try await session.sendMouse(EditorMouseEvent(button: .left, action: .drag, row: 0, column: 10))
            _ = try await session.currentLineForTesting()
            try await session.sendMouse(EditorMouseEvent(button: .left, action: .release, row: 0, column: 10))
            _ = try await session.currentLineForTesting()
        }

        let selectedCells = snapshot.lines.flatMap(\.runs)
            .filter { $0.style.background == selectionBackground }
            .reduce(0) { $0 + $1.cellWidth }
        let matchedCells = snapshot.lines.flatMap(\.runs)
            .filter { $0.style.background == matchBackground }
            .reduce(0) { $0 + $1.cellWidth }

        print("""

        ═══ 선택 vs 같은 심볼 강조 ═══
          선택 배경 셀 \(selectedCells) · match 배경 셀 \(matchedCells)
          → \(selectedCells > 0 ? "선택이 보인다" : "선택이 안 보인다")
        ═════════════════════════════
        """)

        #expect(selectedCells > 0, "선택한 자리에 선택 배경이 없다 — 같은 심볼 강조가 선택을 가린다")
    }

    // MARK: - ADR-0012 마우스

    @Test("mouse 가 꺼져 있으면 클릭은 살고 드래그 선택만 죽는다")
    func disablingMouseKillsDragButNotClick() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("m.ts", contents: (1...10).map { "line \($0) content here" }.joined(separator: "\n"))
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 60, rows: 14)
        defer { Task { await session.shutDown() } }
        try await session.openFile(atRelativePath: "m.ts", line: 1, recordJump: false)
        _ = try await session.currentLineForTesting()

        func clickThenDrag() async throws -> (cursorLine: Int, selectedLines: Int) {
            _ = try await session.executeLuaForTesting("vim.cmd('normal! gg') return 'reset'")
            try await session.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 2, column: 3))
            _ = try await session.currentLineForTesting()
            let cursorLine = try await session.cursorLineForTesting()
            try await session.sendMouse(EditorMouseEvent(button: .left, action: .drag, row: 4, column: 6))
            _ = try await session.currentLineForTesting()
            try await session.sendMouse(EditorMouseEvent(button: .left, action: .release, row: 4, column: 6))
            _ = try await session.currentLineForTesting()
            let selectedLines = try await session.selectedLineCountForTesting()
            _ = try await session.executeLuaForTesting("vim.api.nvim_input('<Esc>') return 'x'")
            return (cursorLine, selectedLines)
        }

        _ = try await session.executeLuaForTesting("vim.o.mouse = '' return 'off'")
        let withMouseOff = try await clickThenDrag()

        _ = try await session.executeLuaForTesting("vim.o.mouse = 'a' return 'on'")
        let withMouseOn = try await clickThenDrag()

        // 이 비대칭이 ADR-0012 의 이유 전부다. 클릭만 확인하는 테스트는 둘 다 통과한다.
        #expect(withMouseOff.cursorLine == 3, "mouse='' 에서 클릭이 죽었다 — 비대칭이 사라졌다")
        #expect(withMouseOff.selectedLines == 1, "mouse='' 인데 드래그 선택이 살아 있다")
        #expect(withMouseOn.cursorLine == 3, "mouse='a' 에서 클릭이 죽었다")
        #expect(withMouseOn.selectedLines == 3, "mouse='a' 인데 드래그가 선택을 못 만든다")
    }

    @Test("드래그 선택이 배경으로 그리드에 도착한다")
    func mouseSelectionReachesTheGridAsBackground() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("s.ts", contents: (1...10).map { "line \($0) MARKERSEL here" }.joined(separator: "\n"))
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 60, rows: 14)
        defer { Task { await session.shutDown() } }
        try await session.openFile(atRelativePath: "s.ts", line: 1, recordJump: false)
        _ = try await session.currentLineForTesting()
        _ = try await session.executeLuaForTesting("vim.o.mouse = 'a' return 'on'")

        let beforeBaseline = await currentRevision(session)
        let before = try await freshSnapshot(session, containing: "MARKERSEL", newerThan: beforeBaseline) {
            _ = try await session.executeLuaForTesting("vim.cmd('normal! gg') vim.cmd('redraw!') return 'r'")
        }

        let dragBaseline = await currentRevision(session)
        let after = try await freshSnapshot(session, containing: "MARKERSEL", newerThan: dragBaseline) {
            try await session.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 1, column: 2))
            _ = try await session.currentLineForTesting()
            try await session.sendMouse(EditorMouseEvent(button: .left, action: .drag, row: 3, column: 8))
            _ = try await session.currentLineForTesting()
            try await session.sendMouse(EditorMouseEvent(button: .left, action: .release, row: 3, column: 8))
            _ = try await session.currentLineForTesting()
        }

        #expect(
            backgroundCellCount(after) > backgroundCellCount(before),
            "선택 전후로 칠해진 배경 셀이 늘지 않았다 (\(backgroundCellCount(before)) → \(backgroundCellCount(after))) — REQ-017 AC-3 이 계약까지 오지 않는다"
        )
    }
}
