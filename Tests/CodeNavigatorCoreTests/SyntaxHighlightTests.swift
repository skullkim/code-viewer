import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-016 AC-1 · AC-2 · AC-3 · AC-4 · AC-6, INV-8, SC-11, SC-13
@Suite("구문 강조 · 같은 심볼 강조 (REQ-016)", .serialized)
struct SyntaxHighlightTests {

    /// `02_design.md §토큰` 의 다크 값. 앱이 색의 단일 소스라는 것이 계약이므로, 여기서도
    /// 엔진이 아니라 테스트가 색을 정한다.
    private static let palette = EditorSyntaxPalette(
        keyword: EditorColor(packedRGB: 0xC792EA),
        type: EditorColor(packedRGB: 0x57C7B8),
        function: EditorColor(packedRGB: 0x82AAFF),
        string: EditorColor(packedRGB: 0xC3E88D),
        number: EditorColor(packedRGB: 0xF78C6C),
        comment: EditorColor(packedRGB: 0x8B92A0),
        keywordIsBold: true,
        normalForeground: EditorColor(packedRGB: 0xE8E8ED),
        normalBackground: EditorColor(packedRGB: 0x1B1B1F),
        sameSymbolBackground: EditorColor(packedRGB: 0x264F78),
        selectionBackground: EditorColor(packedRGB: 0x0A84FF)
    )

    // MARK: - 그리드 관측

    private func currentRevision(_ session: NeovimEditorSession) async -> UInt64 {
        for await snapshot in await session.gridUpdates() {
            return snapshot.revision
        }
        return 0
    }

    /// 기준선 이후에 그려진, 표지를 담은 프레임.
    ///
    /// ⚠ `gridUpdates()` 는 구독 즉시 마지막 프레임을 되돌려준다. 기준선 없이 읽으면 행동 이전의
    /// 화면을 보고 "안 변했다"는 결론을 낸다 — 이 증분의 스파이크가 실제로 그렇게 틀렸다.
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

    /// 주어진 글자를 담은 런.
    ///
    /// 정확 일치로 찾지 않는다. 한 줄의 런은 강조 식별자가 같은 동안만 이어지므로, 같은 줄에
    /// 다른 강조가 하나라도 끼면 쪼개진다 — 그때 정확 일치는 "색이 틀렸다"가 아니라 "런이
    /// 없다"로 실패해서, 실패 메시지가 원인을 가리키지 않는다.
    private func run(
        in snapshot: EditorGridSnapshot, containing text: String
    ) -> EditorTextRun? {
        for line in snapshot.lines {
            for run in line.runs where run.text.contains(text) {
                return run
            }
        }
        return nil
    }

    private func startedSession(
        _ fixture: TemporaryProjectFixture, applyingPalette shouldApply: Bool = true
    ) async throws -> NeovimEditorSession {
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 90, rows: 16)
        if shouldApply {
            try await session.applySyntaxPalette(Self.palette)
        }
        return session
    }

    // MARK: - AC-1 · AC-3

    @Test("지원 언어의 토큰이 서로 다른, 디자인 토큰에서 온 색을 갖는다")
    func supportedLanguageTokensTakeTheirColoursFromThePalette() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("sample.ts", contents: """
        // MARKERTS a comment
        const alpha = "a string";
        const bravo = 42;
        """)
        let session = try await startedSession(fixture)
        defer { Task { await session.shutDown() } }

        let baseline = await currentRevision(session)
        let snapshot = try await freshSnapshot(session, containing: "MARKERTS", newerThan: baseline) {
            try await session.openFile(atRelativePath: "sample.ts", line: nil, recordJump: false)
        }

        let comment = try #require(run(in: snapshot, containing: "MARKERTS"))
        let string = try #require(run(in: snapshot, containing: "a string"))
        let keyword = try #require(run(in: snapshot, containing: "const"))

        #expect(comment.style.foreground == Self.palette.comment)
        #expect(string.style.foreground == Self.palette.string)
        #expect(keyword.style.foreground == Self.palette.keyword)

        // AC-1 은 "서로 다른 색"이다. 셋이 다 팔레트에서 왔어도 같은 값이면 요구는 미충족이다.
        let distinct = Set([comment.style.foreground, string.style.foreground, keyword.style.foreground])
        #expect(distinct.count == 3, "토큰 색이 서로 구별되지 않는다")
    }

    // MARK: - AC-6

    @Test("사용자 설정에 colorscheme 이 있어도 앱의 토큰이 이긴다")
    func theApplicationPaletteWinsOverAUserColourScheme() async throws {
        let configurationHome = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("code-navigator-colours-\(UUID().uuidString)", isDirectory: true)
        let nvimDirectory = configurationHome.appendingPathComponent("nvim", isDirectory: true)
        try FileManager.default.createDirectory(at: nvimDirectory, withIntermediateDirectories: true)
        try """
        vim.cmd('colorscheme vim')
        vim.api.nvim_set_hl(0, 'Comment', { fg = 0xFF0000 })
        """.write(to: nvimDirectory.appendingPathComponent("init.lua"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configurationHome) }

        let fixture = TemporaryProjectFixture()
        fixture.write("c.ts", contents: "// MARKERUSER comment\nconst a = 1;\n")

        let session = NeovimEditorSession()
        try await session.startWithUserConfigurationForTesting(
            configurationHome: configurationHome, projectRoot: fixture.rootURL, columns: 90, rows: 16
        )
        defer { Task { await session.shutDown() } }
        try await session.applySyntaxPalette(Self.palette)

        let baseline = await currentRevision(session)
        let snapshot = try await freshSnapshot(session, containing: "MARKERUSER", newerThan: baseline) {
            try await session.openFile(atRelativePath: "c.ts", line: nil, recordJump: false)
        }

        let comment = try #require(run(in: snapshot, containing: "MARKERUSER"))
        #expect(comment.style.foreground == Self.palette.comment)
        #expect(comment.style.foreground != EditorColor(packedRGB: 0xFF0000))
    }

    @Test("팔레트를 적용한 뒤 colorscheme 이 바뀌어도 앱의 토큰이 되돌아온다")
    func aLaterColourSchemeChangeDoesNotWin() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("c.ts", contents: "// MARKERLATER comment\nconst a = 1;\n")
        let session = try await startedSession(fixture)
        defer { Task { await session.shutDown() } }
        try await session.openFile(atRelativePath: "c.ts", line: nil, recordJump: false)

        let baseline = await currentRevision(session)
        let snapshot = try await freshSnapshot(session, containing: "MARKERLATER", newerThan: baseline) {
            _ = try await session.executeLuaForTesting("""
            vim.cmd('colorscheme vim')
            vim.cmd('redraw!')
            return 'switched'
            """)
        }

        let comment = try #require(run(in: snapshot, containing: "MARKERLATER"))
        #expect(
            comment.style.foreground == Self.palette.comment,
            "colorscheme 이 바뀐 뒤 앱의 색이 사라졌다 — 재적용이 안 걸렸다"
        )
    }

    // MARK: - AC-4 / SC-13

    @Test("지원하지 않는 언어는 색이 붙지 않는다")
    func anUnsupportedLanguageRendersPlain() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("script.py", contents: "# MARKERPY comment\ngreeting = \"hello\"\n")
        fixture.write("main.go", contents: "// MARKERGO comment\npackage main\n")
        let session = try await startedSession(fixture)
        defer { Task { await session.shutDown() } }

        for (path, marker) in [("script.py", "# MARKERPY comment"), ("main.go", "// MARKERGO comment")] {
            let baseline = await currentRevision(session)
            let snapshot = try await freshSnapshot(session, containing: marker, newerThan: baseline) {
                try await session.openFile(atRelativePath: path, line: nil, recordJump: false)
            }
            let comment = try #require(run(in: snapshot, containing: marker))
            #expect(
                comment.style.foreground == nil,
                "\(path) 에 색이 붙었다 (\(String(describing: comment.style.foreground)))"
            )
        }
    }

    /// SC-13 의 뒷문장 — 색이 없다고 파일이 못 쓰이면 안 된다 (INV-8).
    @Test("지원하지 않는 언어도 열리고 편집된다")
    func anUnsupportedLanguageStillEdits() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("script.py", contents: "greeting = 1\n")
        let session = try await startedSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "script.py", line: 1, recordJump: false)
        try await session.sendKeys("ccfarewell = 2<Esc>")
        _ = try await session.currentLineForTesting()

        #expect(try await session.currentLineForTesting() == "farewell = 2")
        #expect(try await session.isDirtyForTesting())
    }

    // MARK: - AC-2 / SC-11

    @Test("커서 아래 심볼과 같은 이름이 파일 안에서 함께 강조되고, 커서를 옮기면 따라온다")
    func theSymbolUnderTheCursorLightsUpItsTwinsAndReleasesThemOnMoving() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("s.ts", contents: """
        const user = 1;
        const other = user;
        const third = user;
        const fourth = user;
        const fifth = user;
        """)
        let session = try await startedSession(fixture)
        defer { Task { await session.shutDown() } }
        try await session.openFile(atRelativePath: "s.ts", line: 1, recordJump: false)
        _ = try await session.currentLineForTesting()

        func highlightedTexts() async throws -> [String] {
            let baseline = await currentRevision(session)
            let snapshot = try await freshSnapshot(session, containing: "const", newerThan: baseline) {
                _ = try await session.executeLuaForTesting("vim.cmd('redraw!') return 'r'")
            }
            var texts: [String] = []
            for line in snapshot.lines {
                for run in line.runs
                where run.style.background == Self.palette.sameSymbolBackground {
                    texts.append(run.text.trimmingCharacters(in: .whitespaces))
                }
            }
            return texts
        }

        // 커서를 `user` 위로. 1번 줄 7열.
        _ = try await session.executeLuaForTesting(
            "vim.api.nvim_win_set_cursor(0, { 1, 6 }) vim.cmd('doautocmd CursorMoved') return 'moved'"
        )
        let onUser = try await highlightedTexts()
        #expect(onUser.count == 5, "user 5곳이 아니라 \(onUser.count)곳이 강조됐다: \(onUser)")
        #expect(onUser.allSatisfy { $0 == "user" }, "user 아닌 것이 강조됐다: \(onUser)")

        // `other` 로 옮기면 user 강조가 사라지고 other 가 강조된다.
        _ = try await session.executeLuaForTesting(
            "vim.api.nvim_win_set_cursor(0, { 2, 6 }) vim.cmd('doautocmd CursorMoved') return 'moved'"
        )
        let onOther = try await highlightedTexts()
        #expect(onOther == ["other"], "커서를 옮겼는데 강조가 따라오지 않았다: \(onOther)")
    }

    @Test("심볼이 아닌 곳에서는 아무것도 강조하지 않는다")
    func punctuationUnderTheCursorLightsUpNothing() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("s.ts", contents: "const user = 1;\nconst other = user;\n")
        let session = try await startedSession(fixture)
        defer { Task { await session.shutDown() } }
        try await session.openFile(atRelativePath: "s.ts", line: 1, recordJump: false)
        _ = try await session.currentLineForTesting()

        // `=` 위로. 괄호·연산자에까지 강조가 붙으면 화면이 "전부 강조"로 보인다.
        _ = try await session.executeLuaForTesting(
            "vim.api.nvim_win_set_cursor(0, { 1, 11 }) vim.cmd('doautocmd CursorMoved') return 'moved'"
        )
        let baseline = await currentRevision(session)
        let snapshot = try await freshSnapshot(session, containing: "const", newerThan: baseline) {
            _ = try await session.executeLuaForTesting("vim.cmd('redraw!') return 'r'")
        }

        let highlighted = snapshot.lines.flatMap { line in
            line.runs.filter { $0.style.background == Self.palette.sameSymbolBackground }
        }
        #expect(highlighted.isEmpty, "심볼이 아닌데 \(highlighted.count)곳이 강조됐다")
    }

    @Test("지원하지 않는 언어에서는 같은 심볼 강조도 붙지 않는다")
    func unsupportedLanguagesGetNoSameSymbolHighlight() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("s.py", contents: "user = 1\nother = user\n")
        let session = try await startedSession(fixture)
        defer { Task { await session.shutDown() } }
        try await session.openFile(atRelativePath: "s.py", line: 1, recordJump: false)
        _ = try await session.currentLineForTesting()

        _ = try await session.executeLuaForTesting(
            "vim.api.nvim_win_set_cursor(0, { 1, 0 }) vim.cmd('doautocmd CursorMoved') return 'moved'"
        )
        let baseline = await currentRevision(session)
        let snapshot = try await freshSnapshot(session, containing: "user", newerThan: baseline) {
            _ = try await session.executeLuaForTesting("vim.cmd('redraw!') return 'r'")
        }

        let highlighted = snapshot.lines.flatMap { line in
            line.runs.filter { $0.style.background == Self.palette.sameSymbolBackground }
        }
        #expect(highlighted.isEmpty, "미지원 언어에 같은 심볼 강조가 붙었다")
    }

    // MARK: - INV-8

    @Test("팔레트를 한 번도 안 줘도 파일은 열리고 편집된다")
    func editingWorksWithoutAnyPalette() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("a.ts", contents: "const a = 1;\n")
        let session = try await startedSession(fixture, applyingPalette: false)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "a.ts", line: 1, recordJump: false)
        try await session.sendKeys("ccconst b = 2;<Esc>")
        _ = try await session.currentLineForTesting()

        #expect(try await session.currentLineForTesting() == "const b = 2;")
    }
}
