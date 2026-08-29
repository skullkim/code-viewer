import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Every editing command must produce the same result in both input modes.
///
/// This is the property the contract exists for. Sending the equivalent keystrokes instead makes
/// each command mean whatever the current mode says it means — `u` reverses a change in normal
/// mode and types the letter "u" in insert mode, and `:w` sent as keys from insert mode does not
/// write at all. That last one is the dangerous kind: it looks like it worked.
@Suite("모드 무관 편집 명령 — 두 모드에서 같은 결과", .serialized)
struct ModeIndependentCommandTests {

    private func startedSession(
        _ fixture: TemporaryProjectFixture,
        inputMode: InputMode,
        contents: String = "first line\nsecond line\n"
    ) async throws -> NeovimEditorSession {
        fixture.write("src/App.kt", contents: contents)
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        if inputMode == .standard {
            try await session.setInputMode(.standard)
        }
        try await Task.sleep(for: .milliseconds(300))
        return session
    }

    private func diskContents(_ fixture: TemporaryProjectFixture) throws -> String {
        try String(contentsOf: fixture.rootURL.appendingPathComponent("src/App.kt"), encoding: .utf8)
    }

    // MARK: - Save (the data-loss one)

    @Test("저장이 두 모드 모두에서 실제로 디스크에 쓴다", arguments: [InputMode.vim, InputMode.standard])
    func saveWritesToDiskInBothModes(inputMode: InputMode) async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startedSession(fixture, inputMode: inputMode)
        defer { Task { await session.shutDown() } }

        // 버퍼만 바꾼다. 이 시점에 디스크는 아직 옛 내용이어야 한다(INV-3).
        try await session.replaceBufferForTesting(with: ["saved in \(inputMode.rawValue) mode"])
        #expect(try diskContents(fixture).contains("saved in") == false)

        try await session.save()
        try await Task.sleep(for: .milliseconds(300))

        // 디스크를 직접 읽는다. "저장했다"는 보고가 아니라 파일이 증거다.
        #expect(try diskContents(fixture).contains("saved in \(inputMode.rawValue) mode"))
    }

    @Test("저장 후에는 더티가 풀린다 — 두 모드 모두")
    func saveClearsDirtyInBothModes() async throws {
        for inputMode in [InputMode.vim, InputMode.standard] {
            let fixture = TemporaryProjectFixture()
            let session = try await startedSession(fixture, inputMode: inputMode)
            defer { Task { await session.shutDown() } }

            try await session.replaceBufferForTesting(with: ["changed"])
            #expect(try await session.isDirtyForTesting() == true, "\(inputMode) 에서 더티가 아니다")

            try await session.save()
            #expect(try await session.isDirtyForTesting() == false, "\(inputMode) 에서 저장 후에도 더티다")
        }
    }

    // MARK: - Undo and redo

    @Test("실행 취소가 두 모드 모두에서 되돌린다 — 글자를 입력하지 않는다", arguments: [InputMode.vim, InputMode.standard])
    func undoReversesInBothModes(inputMode: InputMode) async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startedSession(fixture, inputMode: inputMode)
        defer { Task { await session.shutDown() } }

        try await session.replaceBufferForTesting(with: ["changed line"])
        try await session.undo()
        try await Task.sleep(for: .milliseconds(200))

        let lines = try await session.bufferLinesForTesting()
        // 되돌아왔어야 하고, 무엇보다 'u' 가 버퍼에 들어가 있으면 안 된다.
        #expect(lines.first == "first line", "\(inputMode): \(lines)")
        #expect(lines.contains { $0.contains("uchanged") } == false, "'u' 가 입력됐다: \(lines)")
    }

    @Test("다시 실행이 두 모드 모두에서 되돌린 것을 복원한다", arguments: [InputMode.vim, InputMode.standard])
    func redoRestoresInBothModes(inputMode: InputMode) async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startedSession(fixture, inputMode: inputMode)
        defer { Task { await session.shutDown() } }

        try await session.replaceBufferForTesting(with: ["changed line"])
        try await session.undo()
        try await session.redo()
        try await Task.sleep(for: .milliseconds(200))

        #expect(try await session.bufferLinesForTesting().first == "changed line")
    }

    // MARK: - Selection and clipboard

    @Test("전체 선택이 두 모드 모두에서 버퍼 전체를 고른다", arguments: [InputMode.vim, InputMode.standard])
    func selectAllCoversTheBufferInBothModes(inputMode: InputMode) async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startedSession(
            fixture, inputMode: inputMode, contents: "one\ntwo\nthree\n"
        )
        defer { Task { await session.shutDown() } }

        try await session.selectAll()
        try await Task.sleep(for: .milliseconds(200))

        let mode = try await session.currentModeNameForTesting()
        #expect(mode?.hasPrefix("V") == true || mode?.hasPrefix("v") == true, "\(inputMode): mode=\(mode ?? "nil")")
        #expect(try await session.selectedLineCountForTesting() == 3, "\(inputMode)")
    }

    @Test("복사가 두 모드 모두에서 선택을 클립보드 레지스터에 넣는다", arguments: [InputMode.vim, InputMode.standard])
    func copyFillsTheClipboardRegisterInBothModes(inputMode: InputMode) async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startedSession(
            fixture, inputMode: inputMode, contents: "copy me\nnot me\n"
        )
        defer { Task { await session.shutDown() } }

        try await session.clearClipboardRegisterForTesting()
        try await session.selectAll()
        try await session.copySelection()
        try await Task.sleep(for: .milliseconds(200))

        let clipboard = try await session.clipboardRegisterForTesting()
        #expect(clipboard.contains("copy me"), "\(inputMode): '\(clipboard)'")
    }

    @Test("잘라내기가 두 모드 모두에서 버퍼를 비우고 클립보드를 채운다", arguments: [InputMode.vim, InputMode.standard])
    func cutRemovesAndFillsClipboardInBothModes(inputMode: InputMode) async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startedSession(
            fixture, inputMode: inputMode, contents: "cut me\n"
        )
        defer { Task { await session.shutDown() } }

        try await session.clearClipboardRegisterForTesting()
        try await session.selectAll()
        try await session.cutSelection()
        try await Task.sleep(for: .milliseconds(200))

        #expect(try await session.clipboardRegisterForTesting().contains("cut me"), "\(inputMode)")
        let remaining = try await session.bufferLinesForTesting().joined()
        #expect(remaining.contains("cut me") == false, "\(inputMode): '\(remaining)'")
    }

    @Test("붙여넣기가 두 모드 모두에서 클립보드 내용을 넣는다", arguments: [InputMode.vim, InputMode.standard])
    func pasteInsertsClipboardInBothModes(inputMode: InputMode) async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startedSession(fixture, inputMode: inputMode, contents: "target\n")
        defer { Task { await session.shutDown() } }

        try await session.setClipboardRegisterForTesting("pasted text")
        try await session.paste()
        try await Task.sleep(for: .milliseconds(200))

        let lines = try await session.bufferLinesForTesting()
        #expect(lines.contains { $0.contains("pasted text") }, "\(inputMode): \(lines)")
    }

    // MARK: - Jump list

    @Test("앞으로 이동이 뒤로 이동을 되돌린다 — 두 모드 모두", arguments: [InputMode.vim, InputMode.standard])
    func jumpForwardReversesJumpBackInBothModes(inputMode: InputMode) async throws {
        let fixture = TemporaryProjectFixture()
        let session = try await startedSession(
            fixture, inputMode: inputMode,
            contents: (1...60).map { "line \($0)" }.joined(separator: "\n") + "\n"
        )
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 40, recordJump: true)
        try await Task.sleep(for: .milliseconds(200))

        try await session.jumpBack()
        let afterBack = try await session.cursorLineForTesting()
        #expect(afterBack != 40, "\(inputMode): 뒤로 이동이 일어나지 않았다")

        try await session.jumpForward()
        #expect(try await session.cursorLineForTesting() == 40, "\(inputMode)")
    }
}
