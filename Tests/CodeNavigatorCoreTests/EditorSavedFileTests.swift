import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-004 AC-4 (`:w` 저장이 실제 파일에 반영되고 통지된다), 계약 `SavedFile`
///
/// 줄 수·바이트 수는 Neovim이 저장 시점에 아는 값을 그대로 싣는다. `> 0`만 단언하면 Neovim이
/// 엉뚱한 값을 줘도 통과하므로, **줄 수를 정확히 아는 픽스처로 등호 단언**을 하고 디스크와도 대조한다.
@Suite("NeovimEditorSession — 저장 통지 값", .serialized)
struct EditorSavedFileTests {

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

    @Test("저장 통지의 줄 수·바이트 수가 실제 파일과 일치한다")
    func savedFileCountsMatchTheFileOnDisk() async throws {
        // 한글이 섞여 있어 바이트 수와 글자 수가 다르다 — byteSize가 정말 바이트인지 여기서 갈린다.
        let lines = ["첫 줄입니다", "second line", "세 번째 줄"]
        let contents = lines.map { $0 + "\n" }.joined()

        let fixture = TemporaryProjectFixture()
        fixture.write("src/Notes.txt", contents: contents)
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await session.shutDown() } }

        let savedFiles = await session.savedFiles()
        try await session.openFile(atRelativePath: "src/Notes.txt", line: 1, recordJump: false)
        try await session.sendKeys(":write<CR>")

        let saved = try #require(
            await firstValue(from: savedFiles) { (file: SavedFile) in file.path.hasSuffix("Notes.txt") }
        )

        #expect(saved.lineCount == lines.count)
        #expect(saved.byteSize == contents.utf8.count)

        // 앱이 파일을 다시 읽지 않는다는 게 설계지만, 값이 맞는지는 한 번 대조해 둔다.
        let onDiskSize = try Data(
            contentsOf: fixture.rootURL.appendingPathComponent("src/Notes.txt")
        ).count
        #expect(saved.byteSize == onDiskSize)

        // 글자 수와 같아지면 UTF-8 바이트가 아니라 글자를 센 것이다.
        #expect(saved.byteSize != contents.count)
    }

    @Test("편집으로 줄이 늘면 통지 값도 늘어난 뒤의 값이다")
    func savedFileCountsReflectTheEdit() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class App\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await session.shutDown() } }

        let savedFiles = await session.savedFiles()
        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await session.sendKeys("ofun added() {}<Esc>")
        try await session.sendKeys(":write<CR>")

        let saved = try #require(
            await firstValue(from: savedFiles) { (file: SavedFile) in file.path.hasSuffix("App.kt") }
        )

        // 저장 전 값(1줄)을 실어 보내면 여기서 걸린다.
        #expect(saved.lineCount == 2)

        let onDisk = try Data(contentsOf: fixture.rootURL.appendingPathComponent("src/App.kt"))
        #expect(saved.byteSize == onDisk.count)
    }
}
