import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// Design §6 lists recent projects as a data requirement, and REQ-011 AC-3 groups them
/// with window size and split ratios — shell state the application restores, not something
/// the indexing engine should carry. The store lives here for that reason.
@Suite("RecentProjectStore — 최근 프로젝트 (REQ-001 AC-2, REQ-011 AC-3)")
struct RecentProjectStoreTests {

    /// Time is injected so "most recent" is a fact the test states rather than a race it
    /// hopes to win.
    private final class FixedClock: @unchecked Sendable {
        private var current: Date
        init(_ start: Date) { current = start }
        func now() -> Date { current }
        func advance(seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
    }

    private func makeStore() -> (RecentProjectStore, FixedClock) {
        let clock = FixedClock(Date(timeIntervalSince1970: 1_000_000))
        let store = RecentProjectStore(
            storage: InMemoryKeyValueStore(),
            now: { clock.now() }
        )
        return (store, clock)
    }

    @Test("처음에는 비어 있다")
    func startsEmpty() {
        let (store, _) = makeStore()
        #expect(store.projects().isEmpty)
    }

    @Test("연 프로젝트가 기록된다")
    func openingAProjectRecordsIt() {
        let (store, _) = makeStore()
        store.recordOpened(rootPath: "/repo/code-navigator")
        let projects = store.projects()
        #expect(projects.count == 1)
        #expect(projects[0].name == "code-navigator")
        #expect(projects[0].rootPath == "/repo/code-navigator")
    }

    @Test("최신순으로 정렬된다")
    func projectsAreOrderedMostRecentFirst() {
        let (store, clock) = makeStore()
        store.recordOpened(rootPath: "/repo/first")
        clock.advance(seconds: 60)
        store.recordOpened(rootPath: "/repo/second")
        clock.advance(seconds: 60)
        store.recordOpened(rootPath: "/repo/third")
        #expect(store.projects().map(\.name) == ["third", "second", "first"])
    }

    @Test("같은 프로젝트를 다시 열면 중복 없이 맨 앞으로 온다")
    func reopeningMovesToTheFrontWithoutDuplicating() {
        let (store, clock) = makeStore()
        store.recordOpened(rootPath: "/repo/a")
        clock.advance(seconds: 60)
        store.recordOpened(rootPath: "/repo/b")
        clock.advance(seconds: 60)
        store.recordOpened(rootPath: "/repo/a")
        #expect(store.projects().map(\.name) == ["a", "b"])
        #expect(store.projects().count == 2)
    }

    @Test("최대 5건만 남는다")
    func atMostFiveAreKept() {
        // Design §3 W-2: at most five, newest first.
        let (store, clock) = makeStore()
        for index in 1...8 {
            store.recordOpened(rootPath: "/repo/p\(index)")
            clock.advance(seconds: 60)
        }
        let projects = store.projects()
        #expect(projects.count == 5)
        #expect(projects.map(\.name) == ["p8", "p7", "p6", "p5", "p4"])
    }

    @Test("사라진 경로는 목록에서 제거할 수 있다")
    func aVanishedProjectCanBeRemoved() {
        // Design §3 W-2: opening a recent entry whose path is gone shows the failure sheet
        // and drops the entry, so the list does not keep offering a dead door.
        let (store, clock) = makeStore()
        store.recordOpened(rootPath: "/repo/gone")
        clock.advance(seconds: 60)
        store.recordOpened(rootPath: "/repo/alive")
        store.remove(rootPath: "/repo/gone")
        #expect(store.projects().map(\.name) == ["alive"])
    }

    @Test("경로가 정규화되어 같은 프로젝트가 두 번 들어가지 않는다")
    func pathsAreNormalisedBeforeComparison() {
        let (store, clock) = makeStore()
        store.recordOpened(rootPath: "/repo/a")
        clock.advance(seconds: 60)
        store.recordOpened(rootPath: "/repo/a/")
        clock.advance(seconds: 60)
        store.recordOpened(rootPath: "/repo/sub/../a")
        #expect(store.projects().count == 1)
    }

    @Test("재시작 후에도 복원된다")
    func theListSurvivesARestart() {
        let clock = FixedClock(Date(timeIntervalSince1970: 1_000_000))
        let storage = InMemoryKeyValueStore()
        let first = RecentProjectStore(storage: storage, now: { clock.now() })
        first.recordOpened(rootPath: "/repo/a")
        clock.advance(seconds: 60)
        first.recordOpened(rootPath: "/repo/b")

        // A second store over the same storage stands in for the next launch.
        let second = RecentProjectStore(storage: storage, now: { clock.now() })
        #expect(second.projects().map(\.name) == ["b", "a"])
    }

    @Test("저장된 데이터가 깨져 있어도 앱이 죽지 않는다")
    func corruptStoredDataIsSurvivable() {
        // REQ-NF-004. A restored preference is untrusted input like any other, and losing
        // the recent list is a far better outcome than refusing to launch.
        let storage = InMemoryKeyValueStore()
        storage.setData("이건 JSON이 아니다".data(using: .utf8)!, forKey: RecentProjectStore.storageKey)
        let store = RecentProjectStore(storage: storage, now: { Date() })
        #expect(store.projects().isEmpty)
        store.recordOpened(rootPath: "/repo/a")
        #expect(store.projects().map(\.name) == ["a"])
    }
}
