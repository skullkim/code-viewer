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
            EditorMouseEvent(button: .left, action: .press, row: probeStartRow, column: 0)
        )
        try await waitUntilQueuedInputIsConsumed(session)
        try await session.sendMouse(
            EditorMouseEvent(button: .left, action: .drag, row: probeEndRow, column: 3)
        )
        try await waitUntilQueuedInputIsConsumed(session)
        try await session.sendMouse(
            EditorMouseEvent(button: .left, action: .release, row: probeEndRow, column: 3)
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
            guard let topLine = snapshot.lines.first?.plainText else { return false }
            return topLine.hasPrefix("line ") && !topLine.hasPrefix("line 1 text")
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
        try await session.sendMouse(EditorMouseEvent(button: .left, action: .press, row: 3, column: 2))

        let frame = try #require(await firstValue(from: frames) { $0.rows > 0 })
        let cursorLine = try #require(await session.currentLineForTesting())
        let screenRow3 = frame.lines[3].plainText.trimmingCharacters(in: .whitespaces)

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
}
