import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: 모드 독립 편집 명령의 **실패 경로** (REQ-010 AC-2 의 명령들이 잘못된 상황에서 무엇을 하는가)
///
/// 행복 경로는 `ModeIndependentCommandTests` 가 덮는다. 여기서 보는 것은 "그 명령을 부를 수 없는
/// 상황에서 부르면 어떻게 되는가"다 — 조용히 엉뚱한 것을 지우거나, 실패를 성공으로 위장하지 않아야 한다.
@Suite("편집 명령 — 실패 경로", .serialized)
struct EditorCommandFailurePathTests {

    private func startSession(
        _ fixture: TemporaryProjectFixture,
        contents: String = "line one\nline two\nline three\n"
    ) async throws -> NeovimEditorSession {
        fixture.write("src/App.kt", contents: contents)
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await Task.sleep(for: .milliseconds(300))
        return session
    }

    /// 버퍼가 손대어졌는지는 더티 플래그가 가장 정확히 말해준다 — 내용 비교보다 민감하다.
    ///
    /// 상태 브로드캐스터는 구독 즉시 최신값을 재생하므로, 구독해서 첫 값을 받으면 현재 상태다.
    /// 세션에 테스트용 조회 훅을 새로 뚫지 않으려고 이 경로를 쓴다(그 파일은 내 소유가 아니다).
    private func currentStatus(_ session: NeovimEditorSession) async -> EditorStatus? {
        await withTaskGroup(of: EditorStatus?.self) { group in
            group.addTask {
                for await status in await session.statusUpdates() {
                    return status
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func isDirty(_ session: NeovimEditorSession) async throws -> Bool {
        let status = await currentStatus(session)
        return try #require(status, "상태를 읽지 못했다 — 더티 여부를 판정할 수 없다").isDirty
    }

    // 선택이 없을 때의 복사·잘라내기.
    //
    // 구현은 선택 중이 아니면 `gv`(직전 선택 복원)를 앞에 붙인다. 표준 모드에서 메뉴로 초점이
    // 옮겨가며 선택이 풀리는 경우를 살리려는 것인데, **한 번도 선택한 적이 없으면** 복원할 것이
    // 없다. 그때 엉뚱한 범위를 지우면 사용자 데이터가 사라진다.

    @Test("선택한 적이 없는데 잘라내기를 하면 버퍼가 그대로다")
    func cutWithoutAnySelectionLeavesBufferAlone() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        let before = try await session.currentLineForTesting()
        #expect(try await isDirty(session) == false)

        // 던지든 말든 좋다. 절대 안 되는 것은 버퍼가 바뀌는 것이다.
        _ = try? await session.cutSelection()
        try await Task.sleep(for: .milliseconds(200))

        #expect(try await session.currentLineForTesting() == before)
        #expect(try await isDirty(session) == false, "선택이 없는데 잘라내기가 버퍼를 건드렸다")
    }

    @Test("선택한 적이 없는데 복사를 해도 버퍼가 그대로다")
    func copyWithoutAnySelectionLeavesBufferAlone() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        let before = try await session.currentLineForTesting()

        _ = try? await session.copySelection()
        try await Task.sleep(for: .milliseconds(200))

        #expect(try await session.currentLineForTesting() == before)
        #expect(try await isDirty(session) == false)
    }

    // 한때 실패했다: 선택이 없으면 `gv` 로 예전 선택을 복원해 잘라내고 있었다(c74ec65 에서 수정).
    // 화면 밖의 줄이 사라지는 경로였으므로 회귀를 여기서 잡는다.
    @Test("예전 선택이 남아 있어도 잘라내기가 그 범위를 지우지 않는다")
    func cutDoesNotResurrectAStaleSelection() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        // 사용자가 1번 줄을 골랐다가 선택을 풀고, 커서를 다른 곳으로 옮겼다.
        try await session.sendKeys("ggV<Esc>")
        try await Task.sleep(for: .milliseconds(200))
        try await session.sendKeys("G")
        try await Task.sleep(for: .milliseconds(200))

        // 여기서 ⌘X 를 누른다. `gv` 가 예전 선택을 되살리면 1번 줄이 사라진다.
        _ = try? await session.cutSelection()
        try await Task.sleep(for: .milliseconds(250))

        // 맨 위로 가서 1번 줄이 그대로인지 본다(세션에 조회 훅을 새로 뚫지 않는다).
        try await session.sendKeys("gg")
        try await Task.sleep(for: .milliseconds(200))

        #expect(
            try await session.currentLineForTesting() == "line one",
            "선택을 푼 뒤 옮겨갔는데도 예전 선택 범위가 잘려나갔다"
        )
    }

    // 저장할 수 없는 버퍼.

    @Test("이름 없는 버퍼에서 저장하면 에러로 표면화된다 — 조용히 성공하지 않는다")
    func savingAnUnnamedBufferSurfacesAnError() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        // 이름 없는 새 버퍼로 간다. Neovim 은 여기서 `:write` 를 E32 로 거절한다.
        try await session.sendKeys(":enew<CR>")
        try await Task.sleep(for: .milliseconds(300))

        await #expect(throws: NavigatorError.self) {
            try await session.save()
        }
    }

    @Test("읽기 전용 버퍼에서 저장하면 에러로 표면화된다")
    func savingAReadOnlyBufferSurfacesAnError() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.sendKeys(":setlocal readonly<CR>")
        try await Task.sleep(for: .milliseconds(250))

        // 파일 이름은 있는데 쓸 수 없는 경우다. 이름 없는 버퍼와 다른 코드 경로를 탄다.
        await #expect(throws: NavigatorError.self) {
            try await session.save()
        }
    }

    // 전체 선택 → 잘라내기. 잘린 뒤에도 사용자가 하던 일을 이어갈 수 있어야 한다.

    @Test(
        "전체 선택 후 잘라내기가 버퍼를 비우고 표준 모드에서는 계속 타이핑된다",
        arguments: [InputMode.vim, InputMode.standard]
    )
    func selectAllThenCutClearsBufferAndKeepsTyping(mode: InputMode) async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.setInputMode(mode)
        try await Task.sleep(for: .milliseconds(400))

        try await session.selectAll()
        try await Task.sleep(for: .milliseconds(250))
        try await session.cutSelection()
        try await Task.sleep(for: .milliseconds(250))

        #expect(try await session.currentLineForTesting() == "", "전체 선택 후 잘라냈는데 버퍼가 비지 않았다")

        guard mode == .standard else {
            return
        }

        // 표준 모드의 약속은 "타이핑하면 글자가 들어간다"이다(REQ-010 AC-5). 잘라내기가
        // 노멀 모드에 남겨두면 `hello` 가 명령으로 해석돼 글자가 들어가지 않는다.
        try await session.sendKeys("hello")
        try await Task.sleep(for: .milliseconds(250))

        #expect(
            try await session.currentLineForTesting() == "hello",
            "잘라낸 뒤 타이핑이 삽입되지 않는다 — 표준 모드인데 명령으로 해석됐다"
        )
    }

    // undo/redo 경계.

    @Test("되돌릴 것이 없을 때 실행취소를 반복해도 던지지 않고 버퍼가 그대로다")
    func undoAtOldestChangeIsHarmless() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        let before = try await session.currentLineForTesting()

        for _ in 0..<3 {
            try await session.undo()
        }
        try await Task.sleep(for: .milliseconds(200))

        #expect(try await session.currentLineForTesting() == before)
        #expect(try await isDirty(session) == false)
    }

    @Test("다시 실행할 것이 없을 때 반복해도 던지지 않고 버퍼가 그대로다")
    func redoAtNewestChangeIsHarmless() async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        // 한 번 편집하고 되돌린 뒤, 다시 실행을 경계 너머까지 눌러 본다.
        try await session.sendKeys("ofun added() {}<Esc>")
        try await Task.sleep(for: .milliseconds(200))
        try await session.undo()
        try await Task.sleep(for: .milliseconds(200))
        try await session.redo()
        try await Task.sleep(for: .milliseconds(200))

        let afterFirstRedo = try await session.currentLineForTesting()

        for _ in 0..<3 {
            try await session.redo()
        }
        try await Task.sleep(for: .milliseconds(200))

        #expect(try await session.currentLineForTesting() == afterFirstRedo)
    }
}
