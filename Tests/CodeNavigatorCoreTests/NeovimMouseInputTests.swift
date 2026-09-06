import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-010 AC-2 (클릭으로 커서 이동, 드래그로 선택)
///
/// 마우스 좌표는 **그리드 셀**이다(계약 `EditorMouseEvent`). 버퍼 라인으로 착각하면 스크롤된
/// 긴 파일에서만 어긋나므로, 짧은 픽스처로는 드러나지 않는다 — 그래서 스크롤된 상태를 만들어 고정한다.
@Suite("NeovimEditorSession — 마우스 입력", .serialized)
struct NeovimMouseInputTests {

    private func startSession(_ fixture: TemporaryProjectFixture) async throws -> NeovimEditorSession {
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        return session
    }

    private func firstValue<Value: Sendable>(
        from stream: AsyncStream<Value>,
        timeout: Duration = .seconds(5),
        where predicate: @escaping @Sendable (Value) -> Bool
    ) async -> Value? {
        await withTaskGroup(of: Value?.self) { group in
            group.addTask {
                for await value in stream where predicate(value) {
                    return value
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// 드래그가 실제로 선택을 만들 때까지 기다린다.
    ///
    /// nvim 은 기동 직후 마우스를 단계적으로 받아들인다 — 실측: 클릭은 첫 시도부터 커서를
    /// 옮기지만(프로브 시도 0회), 같은 시점의 드래그는 선택을 만들지 못하고 400ms 뒤에야
    /// 만든다. 그래서 준비 조건을 "클릭이 먹히는가"로 두면 부족하고, 이 스위트가 실제로
    /// 의존하는 능력 자체 — 드래그가 선택을 만드는가 — 를 조건으로 삼는다.
    ///
    /// 고정 sleep 을 쓰지 않는 이유: 전체 스위트를 병렬로 돌리면(다수의 nvim 이 동시에 뜬다)
    /// 어떤 상수도 언젠가 부족해진다. 실제로 이 스위트만 단독 실행하면 통과하고 전체
    /// 실행에서만 실패하는 형태로 드러났다.
    /// 준비 확인과 본 단언이 **같은 드래그**를 쓴다. 좌표나 간격이 갈라지면 "준비됨" 판정이
    /// 본 단언과 다른 동작을 근거로 내려져 거짓이 된다.
    ///
    /// 세 이벤트 사이의 간격이 필요하다 — 사람의 드래그에는 수십 ms 가 있고, 붙여 보내면
    /// Neovim 이 드래그로 읽지 않는다(실측: 붙여 보내면 4회 중 3회 실패, 80ms 를 두면 안정).
    private func dragAcrossProbeArea(_ session: NeovimEditorSession) async throws {
        try await session.sendMouse(
            EditorMouseEvent(button: .left, action: .press, row: probeStartRow, column: gutterColumns)
        )
        try await waitUntilQueuedInputIsConsumed(session)
        try await session.sendMouse(
            EditorMouseEvent(button: .left, action: .drag, row: probeEndRow, column: gutterColumns + 3)
        )
        try await waitUntilQueuedInputIsConsumed(session)
        try await session.sendMouse(
            EditorMouseEvent(button: .left, action: .release, row: probeEndRow, column: gutterColumns + 3)
        )
    }

    /// `nvim_input_mouse` 는 입력을 **큐에 넣고 곧바로 돌아온다**. 누름과 끌기를 연달아 보내면
    /// 한가할 때는 순서대로 소화되지만 부하 중엔 둘이 클릭 하나로 뭉개진다(backend-senior 실측).
    ///
    /// 그래서 사이에 **왕복 요청**을 하나 넣는다. 응답이 돌아왔다는 것은 앞의 입력이 이미
    /// 소화됐다는 뜻이라, 시간을 재는 것보다 확실하다 — 고정 대기는 부하가 얼마나 걸릴지
    /// 아는 척하는 것이고, 그 짐작은 전체 스위트에서 틀린다.
    private func waitUntilQueuedInputIsConsumed(_ session: NeovimEditorSession) async throws {
        _ = try await session.currentLineForTesting()
    }

    private func waitUntilMouseDragCreatesSelection(_ session: NeovimEditorSession) async throws {
        // 프로브가 훑을 행에 글자가 실제로 그려져 있어야 한다. 빈 화면을 드래그하면 고를 것이
        // 없어 선택이 생기지 않고, 그러면 프로브가 "아직 준비 안 됨"과 "화면이 비었음"을
        // 구분하지 못한 채 시도 횟수만 태운다(전체 스위트 부하에서 실제로 그렇게 됐다).
        let frames = await session.gridUpdates()
        let drawn = await firstValue(from: frames) { snapshot in
            guard snapshot.lines.count > probeEndRow else { return false }
            return !snapshot.lines[probeEndRow].plainText.trimmingCharacters(in: .whitespaces).isEmpty
        }
        try #require(drawn != nil, "프로브 행이 그려지지 않았다 — 마우스 준비 여부를 잴 수 없다")

        for _ in 0..<60 {
            try await dragAcrossProbeArea(session)
            try await Task.sleep(for: .milliseconds(40))

            // 버퍼를 건드리지 않고 모드를 묻는다. 명령으로 물으면 묻는 행위가 모드를 바꾼다.
            let mode = try await session.currentNeovimMode()
            if mode?.hasPrefix("v") ?? false {
                // 확인이 끝났으면 노멀로 되돌린다 — 본 단언은 노멀에서 시작해야 모드 전환이
                // 상태 스트림에 실제 변화로 실린다. 되돌아왔다고 가정하지 않고 확인한다:
                // 여기서 비주얼로 남아 있으면 이어지는 드래그는 모드를 바꾸지 않고, 그러면
                // 스트림에 아무것도 실리지 않아 단언이 이유 없이 실패한다.
                try await session.sendKeys("<Esc>")
                try await waitUntilModeIsNormal(session)
                return
            }
        }
        Issue.record("드래그가 끝내 선택을 만들지 못했다 — 이후 마우스 단언은 의미가 없다")
    }

    private func waitUntilModeIsNormal(_ session: NeovimEditorSession) async throws {
        for _ in 0..<60 {
            if try await session.currentNeovimMode()?.hasPrefix("n") ?? false {
                return
            }
            try await Task.sleep(for: .milliseconds(40))
        }
        Issue.record("노멀 모드로 돌아오지 않았다 — 이후 모드 전환 단언은 의미가 없다")
    }

    /// 프로브가 훑는 화면 행. 맨 위를 피하는 이유는 사용자 설정의 `scrolloff` 가 위쪽 행
    /// 클릭에서 화면을 스크롤시켜, 이어지는 좌표 단언의 전제를 바꿔놓기 때문이다.
    private var probeStartRow: Int { 5 }
    private var probeEndRow: Int { 6 }

    private func makeNumberedFile(_ fixture: TemporaryProjectFixture, lineCount: Int) {
        fixture.write(
            "src/App.kt",
            contents: (1...lineCount).map { "line \($0) text" }.joined(separator: "\n") + "\n"
        )
    }

    @Test("드래그하면 선택이 생긴다 — 비주얼 모드로 들어간다")
    func dragCreatesSelection() async throws {
        let fixture = TemporaryProjectFixture()
        makeNumberedFile(fixture, lineCount: 20)
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await waitUntilMouseDragCreatesSelection(session)

        // 준비 확인이 방금 같은 자리를 눌렀다. `mousetime`(기본 500ms) 안에 다시 누르면
        // Neovim 이 더블클릭으로 읽어 드래그가 되지 않는다 — backend-senior 가 전체 실행
        // 부하에서 찾아낸 조건이라 격리 실행만으로는 드러나지 않는다.
        try await Task.sleep(for: .milliseconds(600))

        let statuses = await session.statusUpdates()
        try await dragAcrossProbeArea(session)

        // 둘을 따로 단언한다. 하나만 보면 마우스 경로가 깨진 건지 모드 전파가 깨진 건지
        // 구분할 수 없다 — 이번 조사에서 실제로 그 구분이 없어 원인을 잘못 짚었다.
        try await Task.sleep(for: .milliseconds(150))
        let neovimMode = try await session.currentNeovimMode()
        #expect(neovimMode?.hasPrefix("v") == true, "Neovim 이 비주얼로 들어가지 않았다 — 마우스 경로 문제다")

        let visual = await firstValue(from: statuses) { $0.mode == .visual }
        #expect(visual != nil, "Neovim 은 비주얼인데 상태 스트림에 실리지 않았다 — 전파 문제다")
    }

    @Test("휠 스크롤이 뷰포트를 움직인다")
    func wheelScrollMovesViewport() async throws {
        let fixture = TemporaryProjectFixture()
        makeNumberedFile(fixture, lineCount: 200)
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await waitUntilMouseDragCreatesSelection(session)

        let frames = await session.gridUpdates()
        try await session.sendMouse(EditorMouseEvent(button: .wheel, action: .wheelDown, row: 10, column: 10))

        // 맨 윗줄이 더 이상 1번 줄이 아니어야 한다 — 커서가 아니라 화면이 움직였다는 뜻이다.
        let scrolled = await firstValue(from: frames) { snapshot in
            guard let topLine = snapshot.lines.first.map(codeText(of:)) else { return false }
            return topLine.hasPrefix("line ") && topLine != "line 1 text"
        }
        #expect(scrolled != nil)
    }

    @Test("수식키가 함께 전달된다 — ⇧클릭이 선택을 넓힌다")
    func modifiersAreForwarded() async throws {
        let fixture = TemporaryProjectFixture()
        makeNumberedFile(fixture, lineCount: 20)
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        // ⇧클릭이 선택을 넓히는 건 popup 계열에서다(실측: 기본값 popup_setpos·popup 은 넓히고,
        // extend 는 ⇧클릭을 "커서 아래 단어 검색"에 쓰므로 넓히지 않는다). 사용자 설정이
        // 무엇이든 이 테스트가 같은 것을 재도록 여기서 명시적으로 고정한다.
        // 수식키가 빠지면 그냥 커서 이동이라 비주얼 모드로 들어가지 않는다 — 그래서 이
        // 단언이 수식키 전달을 가른다.
        try await session.sendKeys(":set mousemodel=popup<CR>")
        try await waitUntilMouseDragCreatesSelection(session)

        let statuses = await session.statusUpdates()
        try await session.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 0, column: 0))
        try await session.sendMouse(
            EditorMouseEvent(button: .left, action: .press, row: 3, column: 4, modifiers: "S")
        )

        let visual = await firstValue(from: statuses) { $0.mode == .visual }
        #expect(visual != nil)
    }

    @Test("좌표는 버퍼 라인이 아니라 그리드 셀이다 — 스크롤된 상태에서 확인")
    func coordinatesAreGridCellsNotBufferLines() async throws {
        let fixture = TemporaryProjectFixture()
        makeNumberedFile(fixture, lineCount: 200)
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        // 60번 줄로 가면 화면이 스크롤된다 — 이제 화면 3행과 버퍼 4번 줄은 다른 줄이다.
        try await session.openFile(atRelativePath: "src/App.kt", line: 60, recordJump: false)
        try await waitUntilMouseDragCreatesSelection(session)

        let frames = await session.gridUpdates()
        try await session.sendMouse(
            EditorMouseEvent(button: .left, action: .press, row: 3, column: gutterColumns + 2)
        )

        let frame = try #require(await firstValue(from: frames) { $0.rows > 0 })
        let cursorLine = try #require(await session.currentLineForTesting())
        let screenRow3 = codeText(of: frame.lines[3])

        // 커서는 화면 3행에 보이던 줄로 가야 한다.
        #expect(cursorLine == screenRow3)
        // 좌표를 버퍼 라인으로 해석했다면 4번 줄로 갔을 것이다.
        #expect(cursorLine != "line 4 text")
    }

    @Test("기동 전 마우스 입력은 조용히 무시된다 — 크래시도 예외도 없다")
    func mouseBeforeStartIsIgnored() async throws {
        let session = NeovimEditorSession()

        try await session.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 0, column: 0))

        #expect(await session.state() == .notStarted)
    }

    /// 프로브가 훑는 행에서 **배경이 명시된** 셀 수.
    ///
    /// 행을 좁히는 것이 이 함수의 요점이다. 화면 전체를 세면 상태줄처럼 늘 배경을 가진 것이
    /// 섞여 들어와 단언이 **선택과 무관한 이유로 참**이 된다 — 빈 집합에서 저절로 참이 되는
    /// 단언과 같은 종류의 거짓 통과다.
    private func selectionBackgroundCellCount(
        in snapshot: EditorGridSnapshot,
        matching colour: EditorColor? = nil
    ) -> Int {
        (probeStartRow...probeEndRow).reduce(0) { total, row in
            guard snapshot.lines.count > row else { return total }
            let painted = snapshot.lines[row].runs
                .filter { run in
                    guard let background = run.style.background else { return false }
                    // 색을 지정하면 그 색만 센다 — "배경이 있다"가 아니라 "**우리가 준 색**이다".
                    return colour.map { background == $0 } ?? true
                }
                .reduce(0) { $0 + $1.cellWidth }
            return total + painted
        }
    }

    /// 선택색을 특정할 수 있게 앱이 주는 팔레트를 심는다.
    ///
    /// 값은 눈에 띄는 아무 색이어도 되지만 **다른 강조와 겹치지 않아야** 한다 — 겹치면 이
    /// 테스트가 무엇을 세고 있는지 다시 모호해진다.
    private func applyPaletteWithDistinctSelection(
        _ session: NeovimEditorSession
    ) async throws -> EditorColor {
        let selection = EditorColor(packedRGB: 0x233043)
        try await session.applySyntaxPalette(
            EditorSyntaxPalette(
                keyword: EditorColor(packedRGB: 0xC792EA),
                type: EditorColor(packedRGB: 0x57C7B8),
                function: EditorColor(packedRGB: 0x82AAFF),
                string: EditorColor(packedRGB: 0xC3E88D),
                number: EditorColor(packedRGB: 0xF78C6C),
                comment: EditorColor(packedRGB: 0x9AA0AD),
                keywordIsBold: true,
                normalForeground: EditorColor(packedRGB: 0xE8E8ED),
                normalBackground: EditorColor(packedRGB: 0x1B1B1F),
                sameSymbolBackground: EditorColor(packedRGB: 0x343438),
                selectionBackground: selection,
                lineNumberForeground: EditorColor(packedRGB: 0x9898A1),
                currentLineNumberForeground: EditorColor(packedRGB: 0xE8E8ED)
            )
        )
        return selection
    }

    @Test("드래그로 만든 선택은 화면에 보인다 — 앱이 준 선택색으로 (REQ-017 AC-3 · REQ-016 AC-3)")
    func theSelectionIsVisibleOnScreen() async throws {
        // 비주얼 **모드로 들어갔다**와 선택이 **보인다**는 다른 질문이다. 위의
        // `dragCreatesSelection` 은 모드만 묻는다 — 모드가 바뀌었는데 화면이 그대로여도
        // 통과한다. AC-3 은 사용자가 눈으로 보는 쪽이라 그리드에 색이 실렸는지를 물어야 한다.
        //
        // 그리고 **아무 배경**이 아니라 **앱이 준 색**인지까지 묻는다. 두 요구가 여기서
        // 만난다 — REQ-017 AC-3 은 "선택 배경이 보인다", REQ-016 AC-3 은 "색은 디자인
        // 토큰에서 온다". 색을 특정하지 않으면 nvim 기본색으로도 통과하고, 그러면 팔레트가
        // 끊긴 날 이 테스트는 아무 말도 하지 않는다. (backend-senior 와 중복 정리하며 합침)
        let fixture = TemporaryProjectFixture()
        makeNumberedFile(fixture, lineCount: 20)
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        let selectionColour = try await applyPaletteWithDistinctSelection(session)
        try await waitUntilMouseDragCreatesSelection(session)
        // 준비 확인이 방금 같은 자리를 눌렀다. `mousetime`(기본 500ms) 안에 다시 누르면
        // Neovim 이 더블클릭으로 읽어 드래그가 되지 않는다.
        try await Task.sleep(for: .milliseconds(600))

        let frames = await session.gridUpdates()
        let before = try #require(
            await firstValue(from: frames) { $0.lines.count > probeEndRow },
            "선택 전 프레임을 못 받았다 — 증가를 잴 기준이 없다"
        )
        // 기준선을 단언한다. 여기가 0 이 아니면 뒤의 "칠해졌다"는 선택의 증거가 아니다.
        #expect(
            selectionBackgroundCellCount(in: before, matching: selectionColour) == 0,
            "선택 전에 이미 칠해져 있으면 이 테스트는 선택을 재는 게 아니다"
        )

        try await dragAcrossProbeArea(session)

        let painted = await firstValue(from: frames) {
            selectionBackgroundCellCount(in: $0, matching: selectionColour) > 0
        }
        #expect(
            painted != nil,
            "드래그 후에도 **앱이 준 선택색**이 실린 프레임이 오지 않았다 — 선택이 안 보이거나 우리 색이 아니다"
        )
    }

    @Test("마우스로 만든 선택에 Vim 명령이 그대로 먹는다 — 드래그 후 d 로 지운다 (REQ-017 AC-4 · SC-12)")
    func vimCommandsApplyToASelectionMadeWithTheMouse() async throws {
        // 선택이 **보이는 것**과 선택이 **Vim 이 아는 선택인 것**은 다르다. 화면만 칠해 놓고
        // 실제 비주얼 범위가 서지 않았다면 AC-3 은 통과하고 AC-4 는 깨진다 — 사용자에게는
        // "선택은 되는데 지워지지 않는" 상태다. 그래서 버퍼를 직접 본다.
        let fixture = TemporaryProjectFixture()
        makeNumberedFile(fixture, lineCount: 20)
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await waitUntilMouseDragCreatesSelection(session)
        try await Task.sleep(for: .milliseconds(600))

        // 화면 행 ↔ 버퍼 줄을 산수로 짐작하지 않고 그리드에서 읽는다. `scrolloff` 하나에
        // 어긋나고, 어긋나면 이 단언은 실패하는 대신 **엉뚱한 줄을 보며 조용히 통과**한다.
        let frames = await session.gridUpdates()
        let frame = try #require(await firstValue(from: frames) { $0.lines.count > probeEndRow })
        let draggedText = (probeStartRow...probeEndRow).map { codeText(of: frame.lines[$0]) }
        #expect(draggedText.count == 2, "드래그가 훑는 두 행을 못 읽었다")
        #expect(draggedText.allSatisfy { !$0.isEmpty }, "빈 행을 드래그하면 지울 것이 없다")

        let before = try await session.bufferLinesForTesting()
        for text in draggedText {
            #expect(before.contains(text), "\(text) 가 버퍼에 없으면 삭제를 잴 수 없다")
        }

        try await dragAcrossProbeArea(session)
        try await session.sendKeys("d")
        try await waitUntilQueuedInputIsConsumed(session)

        let after = try await session.bufferLinesForTesting()
        #expect(after.count < before.count, "줄 수가 그대로다 — 선택이 있었어도 d 가 먹지 않았다")
        for text in draggedText {
            #expect(!after.contains(text), "\(text) 가 남아 있다 — 마우스 선택에 Vim 명령이 안 먹는다")
        }
    }
}
