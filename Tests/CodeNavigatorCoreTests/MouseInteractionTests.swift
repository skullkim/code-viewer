import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-017 AC-1 · AC-2 · AC-3 · AC-4, SC-12, REQ-016 AC-5
///
/// ⚠ 여기서 재는 것은 **엔진 경계까지**다. 실제 앱에서 픽셀이 셀로 바뀌어 이 경로에 닿는지는
/// 프론트엔드 영역이고 라이브로만 확인된다.
@Suite("마우스 클릭·드래그 (REQ-017)", .serialized)
struct MouseInteractionTests {

    private func makeFixture() -> TemporaryProjectFixture {
        let fixture = TemporaryProjectFixture()
        fixture.write("m.ts", contents: (1...12).map { "const line\($0) = \($0);" }.joined(separator: "\n") + "\n")
        return fixture
    }

    private func startedSession(_ fixture: TemporaryProjectFixture) async throws -> NeovimEditorSession {
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 70, rows: 18)
        try await session.openFile(atRelativePath: "m.ts", line: 1, recordJump: false)
        _ = try await session.currentLineForTesting()
        return session
    }

    /// `nvim_input_mouse` 는 큐에 넣고 곧바로 돌아온다. 누름과 끌기를 붙여 보내면 부하 중에
    /// 클릭 하나로 뭉개진다(기존 `NeovimMouseInputTests` 가 실측한 것). 사이에 왕복 요청을
    /// 하나 넣어 앞의 입력이 소화됐음을 확인한다 — 고정 대기보다 확실하다.
    private func settle(_ session: NeovimEditorSession) async throws {
        _ = try await session.currentLineForTesting()
    }

    private func dragFrom(
        _ session: NeovimEditorSession,
        startRow: Int, startColumn: Int, endRow: Int, endColumn: Int
    ) async throws {
        try await session.sendMouse(
            EditorMouseEvent(button: .left, action: .press, row: startRow, column: startColumn)
        )
        try await settle(session)
        try await session.sendMouse(
            EditorMouseEvent(button: .left, action: .drag, row: endRow, column: endColumn)
        )
        try await settle(session)
        try await session.sendMouse(
            EditorMouseEvent(button: .left, action: .release, row: endRow, column: endColumn)
        )
        try await settle(session)
    }

    // MARK: - AC-1

    @Test("클릭하면 그 위치로 커서가 간다 — 노멀 모드")
    func clickingMovesTheCursorInNormalMode() async throws {
        let session = try await startedSession(makeFixture())
        defer { Task { await session.shutDown() } }

        try await session.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 4, column: 6))
        try await settle(session)

        // 셀 행은 0부터, 버퍼 줄은 1부터. 스크롤이 없으므로 행 4 는 5번째 줄이다.
        #expect(try await session.cursorLineForTesting() == 5)
        #expect(try await session.currentLineForTesting() == "const line5 = 5;")
    }

    @Test("클릭하면 그 위치로 커서가 간다 — 삽입 모드")
    func clickingMovesTheCursorInInsertMode() async throws {
        let session = try await startedSession(makeFixture())
        defer { Task { await session.shutDown() } }

        try await session.sendKeys("i")
        try await settle(session)
        #expect(try await session.evaluateForTesting("mode()") == "i")

        try await session.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 3, column: 2))
        try await settle(session)

        #expect(try await session.cursorLineForTesting() == 4)
        // 클릭이 모드를 바꾸지 않는다 — 사용자가 치던 자리를 옮겼을 뿐이다.
        #expect(try await session.evaluateForTesting("mode()") == "i")
    }

    // MARK: - AC-2 · AC-3

    @Test("드래그하면 비주얼 선택이 되고, 놓아도 유지된다")
    func draggingSelectsAndTheSelectionSurvivesTheRelease() async throws {
        let session = try await startedSession(makeFixture())
        defer { Task { await session.shutDown() } }

        try await dragFrom(session, startRow: 2, startColumn: 4, endRow: 4, endColumn: 9)

        #expect(try await session.evaluateForTesting("mode()") == "v")
        #expect(try await session.selectedLineCountForTesting() == 3)
    }


    // MARK: - AC-4 / SC-12


    @Test("복사도 마우스 선택을 그대로 받는다")
    func copyingTakesAMouseMadeSelection() async throws {
        let session = try await startedSession(makeFixture())
        defer { Task { await session.shutDown() } }
        try await session.clearClipboardRegisterForTesting()

        // 거터 폭만큼 민다. `numberwidth` 기본이 4 라 0~3 열은 줄 번호이고, 거기서 시작하면
        // 선택이 코드가 아니라 거터에서 출발한다.
        try await dragFrom(
            session,
            startRow: 1, startColumn: gutterColumns,
            endRow: 1, endColumn: gutterColumns + 10
        )
        try await session.copySelection()
        try await settle(session)

        #expect(try await session.clipboardRegisterForTesting().contains("line2"))
    }

    // MARK: - 사용자가 마우스를 꺼 뒀을 때

    /// 실측: `mouse=''` 면 **클릭은 살고 드래그만 죽는다.** 클릭만 확인하는 테스트는 그 상태에서
    /// 초록이므로, 세션이 옵션을 거는지를 직접 단언한다.
    @Test("사용자 설정이 마우스를 꺼 뒀어도 세션 안에서는 켜진다")
    func theSessionTurnsTheMouseOnEvenWhenTheUserTurnedItOff() async throws {
        let configurationHome = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("code-navigator-mouse-off-\(UUID().uuidString)", isDirectory: true)
        let nvimDirectory = configurationHome.appendingPathComponent("nvim", isDirectory: true)
        try FileManager.default.createDirectory(at: nvimDirectory, withIntermediateDirectories: true)
        try "vim.o.mouse = ''\n".write(
            to: nvimDirectory.appendingPathComponent("init.lua"), atomically: true, encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: configurationHome) }

        let fixture = makeFixture()
        let session = NeovimEditorSession()
        try await session.startWithUserConfigurationForTesting(
            configurationHome: configurationHome, projectRoot: fixture.rootURL, columns: 70, rows: 18
        )
        defer { Task { await session.shutDown() } }
        try await session.openFile(atRelativePath: "m.ts", line: 1, recordJump: false)
        try await settle(session)

        #expect(try await session.executeLuaForTesting("return vim.o.mouse") == "a")

        // 옵션 값만 보면 부족하다 — 그 값이 실제로 드래그를 살리는지까지 본다.
        try await dragFrom(session, startRow: 1, startColumn: 0, endRow: 3, endColumn: 5)
        #expect(try await session.evaluateForTesting("mode()") == "v")
        #expect(try await session.selectedLineCountForTesting() == 3)
    }

    // MARK: - REQ-016 AC-5

    /// 강조가 켜진 채로 타이핑이 강조 없을 때와 체감상 같은지.
    ///
    /// 절대 시간을 재면 기계 성능에 묶이므로, **같은 세션에서 강조를 끄고 켜 비교**한다.
    @Test("강조가 타이핑을 느리게 하지 않는다")
    func highlightingDoesNotSlowTyping() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("t.ts", contents: (1...200).map { "const value\($0) = \($0);" }.joined(separator: "\n"))
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 90, rows: 40)
        defer { Task { await session.shutDown() } }
        try await session.openFile(atRelativePath: "t.ts", line: 1, recordJump: false)
        _ = try await session.currentLineForTesting()

        func timeTyping() async throws -> Double {
            try await session.sendKeys("gg")
            let startedAt = Date()
            for _ in 0..<40 {
                try await session.sendKeys("j")
            }
            _ = try await session.currentLineForTesting()
            return Date().timeIntervalSince(startedAt)
        }

        // 강조를 모두 끈 상태의 기준선.
        _ = try await session.executeLuaForTesting("""
        pcall(vim.api.nvim_del_augroup_by_name, 'CodeNavigatorSameSymbol')
        vim.cmd('syntax off')
        return 'off'
        """)
        let withoutHighlighting = try await timeTyping()

        // 되켜고 같은 일을 한다.
        _ = try await session.executeLuaForTesting("vim.cmd('syntax on') return 'on'")
        _ = try await session.executeLuaForTesting(
            NeovimHighlightScript.installSameSymbolHighlightScript(
                allowedFileTypes: NeovimSyntaxAllowList.highlightedFileTypes.sorted()
            )
        )
        let withHighlighting = try await timeTyping()

        // 체감상 같음의 기준을 넉넉히 잡는다 — 좁게 잡으면 부하 중에 흔들리는 테스트가 된다.
        #expect(
            withHighlighting < max(withoutHighlighting * 3, 1.0),
            "강조가 타이핑을 늦춘다: \(withoutHighlighting)s → \(withHighlighting)s"
        )
    }
}
