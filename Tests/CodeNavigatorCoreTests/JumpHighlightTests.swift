import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Jump highlighting, kept from the retired scenario file.
///
/// These never went through `CodeNavigatorEngine` — they drive `NeovimEditorSession`
/// directly, which is what the application uses. They were only living in that file; the
/// path they exercise was always the live one, so they move rather than migrate.
@Suite("정의 이동 강조 — QA 지적 갭", .serialized)
struct JumpHighlightTests {

    @Test("정의 이동 시 대상 줄이 잠시 강조되고, 스스로 사라진다")
    func jumpTargetIsHighlightedThenClears() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: (1...30).map { "line \($0)" }.joined(separator: "\n"))
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 20, recordJump: true)
        #expect(try await session.jumpHighlightCountForTesting() == 1)

        // 스스로 지워져야 한다. 남으면 선택 영역처럼 보인다.
        var cleared = false
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            if try await session.jumpHighlightCountForTesting() == 0 {
                cleared = true
                break
            }
        }
        #expect(cleared)
    }

    @Test("라인을 지정하지 않은 열기는 강조하지 않는다")
    func openingWithoutALineDoesNotHighlight() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class App\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: nil, recordJump: false)
        #expect(try await session.jumpHighlightCountForTesting() == 0)
    }
}
