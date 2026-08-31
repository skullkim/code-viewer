import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-004 AC-4 의 전제 — 탭의 더티 표시가 **바뀔 때** 알려지는가
///
/// 지금까지 탭 더티 점이 한 번도 뜬 적이 없다. 세션이 "수정 상태가 변했다" 를 아무에게도
/// 말하지 않기 때문이다. 세션은 **세지 않는다** — 세려면 열린 프로젝트 목록을 알아야 하고
/// 그건 워크스페이스의 것이다. 여기서는 신호만 낸다.
@Suite("더티 신호 — 변화 통지", .serialized)
struct EditorDirtySignalTests {

    private func firstValue(
        from stream: AsyncStream<String>,
        timeout: Duration = .seconds(5),
        where predicate: @escaping @Sendable (String) -> Bool
    ) async -> String? {
        await withTaskGroup(of: String?.self) { group in
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

    @Test("버퍼를 수정하면 그 파일 경로로 신호가 온다")
    func modifyingABufferSignalsItsPath() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "원본\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await Task.sleep(for: .milliseconds(300))

        // 구독을 먼저 연다 — 수정 뒤에 열면 이미 지나간 신호를 놓친다.
        let changes = await session.dirtyStateChanges()
        try await session.sendKeys("O수정<Esc>")

        let signalled = await firstValue(from: changes) { $0.hasSuffix("src/App.kt") }
        #expect(signalled != nil, "버퍼를 수정했는데 신호가 오지 않았다")
    }

    @Test("저장해서 더티가 풀릴 때도 신호가 온다 — 점을 끄려면 그 전이도 알아야 한다")
    func clearingDirtyAlsoSignals() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "원본\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await session.sendKeys("O수정<Esc>")
        try await Task.sleep(for: .milliseconds(400))
        #expect(try await session.dirtyFiles(inProjectRoot: fixture.rootURL) == ["src/App.kt"])

        let changes = await session.dirtyStateChanges()
        try await session.save()

        let signalled = await firstValue(from: changes) { $0.hasSuffix("src/App.kt") }
        #expect(signalled != nil, "저장으로 더티가 풀렸는데 신호가 오지 않았다")
        #expect(try await session.dirtyFiles(inProjectRoot: fixture.rootURL).isEmpty)
    }
}
