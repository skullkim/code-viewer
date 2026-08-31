import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 트리와 인덱스가 같은 디렉토리를 본다 (REQ-003 ↔ REQ-009 경계면).
///
/// QA 실측: `blocked.md` 를 만들고 8초 뒤 **전문 검색은 그 파일을 찾는데(6 파일 검색)
/// 파일 트리에는 없었다(5개).** 인덱스는 감시자가 갱신하고 트리는 **열 때 한 번 읽은
/// 캐시**를 들고 있었기 때문이다.
///
/// **이것도 이중 장부다** — 인덱스와 트리가 같은 디렉토리를 각자 읽는다(ADR-0111 과 같은
/// 구조). 다만 이번엔 **한쪽만 갱신되는 경로가 실재로 확인됐다.**
@MainActor
@Suite("트리가 인덱스와 같은 파일을 본다 (REQ-003 ↔ REQ-009)")
struct TreeIndexAgreementTests {

    private func entry(_ name: String, isDirectory: Bool = false) -> DirectoryEntry {
        DirectoryEntry(name: name, path: name, isDirectory: isDirectory)
    }

    private func makeModel(_ session: FakeProjectSession) -> AppModel {
        AppModel(
            editorSession: FakeEditorSession(),
            workspace: FakeWorkspace(sharedSession: session),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
    }

    @Test("인덱싱이 끝나면 트리가 새 파일을 본다")
    func theTreeSeesFilesTheIndexFound() async {
        let session = FakeProjectSession()
        session.directoryEntries = ["": [entry("a.md"), entry("b.md")]]

        let model = makeModel(session)
        await model.openProject(at: URL(fileURLWithPath: "/tmp/proj"))
        #expect(model.fileTree.presentation.rows.count == 2, "전제: 두 파일로 시작한다")

        // 디스크에 새 파일이 생겼고 감시자가 재인덱싱했다.
        session.directoryEntries = ["": [entry("a.md"), entry("b.md"), entry("blocked.md")]]
        model.handle(indexState: .indexing(IndexProgress(completed: 1, total: 3)))
        model.handle(indexState: .ready)
        await model.awaitTreeRefresh()

        let names = model.fileTree.presentation.rows.map(\.name)
        #expect(names.contains("blocked.md"),
                "인덱스는 아는 파일을 트리가 모른다 — 트리에서 열 수 없다. 지금 \(names)")
    }

    @Test("🔑 새로고침이 펼침 상태를 버리지 않는다")
    func refreshingKeepsWhatTheUserOpened() async {
        // 가장 싼 구현은 `loadProject` 재호출인데, 그건 펼침·선택을 **의도적으로** 버린다
        // (프로젝트 전환용이다). 인덱싱이 끝날 때마다 트리가 접히면 큰 레포에서는
        // 사용자가 트리를 쓸 수 없다 — 고치려던 결함보다 나쁘다.
        let session = FakeProjectSession()
        session.directoryEntries = [
            "": [entry("src", isDirectory: true)],
            "src": [entry("main.swift")],
        ]

        let model = makeModel(session)
        await model.openProject(at: URL(fileURLWithPath: "/tmp/proj"))
        await model.fileTree.perform(.expand(path: "src"))
        #expect(model.fileTree.expandedPaths.contains("src"), "전제: 사용자가 폴더를 펼쳤다")

        model.handle(indexState: .indexing(IndexProgress(completed: 1, total: 2)))
        model.handle(indexState: .ready)
        await model.awaitTreeRefresh()

        #expect(model.fileTree.expandedPaths.contains("src"),
                "인덱싱이 끝날 때마다 트리가 접히면 사용자가 트리를 쓸 수 없다")
    }

    @Test("인덱싱 중에는 다시 읽지 않는다 — 진행 중 상태는 계속 바뀐다")
    func refreshWaitsForThePassToFinish() async {
        let session = FakeProjectSession()
        session.directoryEntries = ["": [entry("a.md")]]

        let model = makeModel(session)
        await model.openProject(at: URL(fileURLWithPath: "/tmp/proj"))
        let readsAfterOpen = session.directoryEntriesCallCount

        // 큰 레포에서 진행률은 초당 여러 번 바뀐다. 매번 트리를 다시 읽으면
        // 그 자체가 엔진 부하가 된다.
        model.handle(indexState: .indexing(IndexProgress(completed: 1, total: 900)))
        model.handle(indexState: .indexing(IndexProgress(completed: 2, total: 900)))
        model.handle(indexState: .indexing(IndexProgress(completed: 3, total: 900)))
        await model.awaitTreeRefresh()

        #expect(session.directoryEntriesCallCount == readsAfterOpen,
                "진행률이 바뀔 때마다 트리를 다시 읽고 있다")
    }
}
