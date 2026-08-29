import Testing
@testable import CodeNavigatorCore

@Suite("FileChangeBatch — 변경 배치 판정")
struct FileChangeBatchTests {

    @Test("비어 있으면 할 일이 없다")
    func emptyBatchResolvesToNothing() {
        var batch = FileChangeBatch()
        #expect(batch.isEmpty)
        #expect(batch.drain() == .none)
    }

    @Test("같은 경로의 반복 이벤트는 하나로 합쳐지고 마지막이 이긴다")
    func repeatedEventsForOnePathCollapse() {
        var batch = FileChangeBatch()
        batch.note(path: "src/App.kt", kind: .changed)
        batch.note(path: "src/App.kt", kind: .changed)
        batch.note(path: "src/App.kt", kind: .removed)

        #expect(batch.pendingCount == 1)
        #expect(batch.drain() == .incremental(["src/App.kt": .removed]))
    }

    @Test("임계 미만이면 개별 갱신이다")
    func belowThresholdResolvesIncrementally() {
        var batch = FileChangeBatch()
        for index in 0..<(FileChangeBatch.bulkChangeThreshold - 1) {
            batch.note(path: "src/File\(index).kt", kind: .changed)
        }
        guard case .incremental(let changes) = batch.drain() else {
            Issue.record("개별 갱신이어야 한다")
            return
        }
        #expect(changes.count == FileChangeBatch.bulkChangeThreshold - 1)
    }

    @Test("임계와 같아지면 전체 재스캔으로 폴백한다 — 경계 포함")
    func atThresholdFallsBackToFullRescan() {
        var batch = FileChangeBatch()
        for index in 0..<FileChangeBatch.bulkChangeThreshold {
            batch.note(path: "src/File\(index).kt", kind: .changed)
        }
        #expect(batch.drain() == .fullRescan)
    }

    @Test("드롭 신호가 오면 개수와 무관하게 전체 재스캔이다")
    func dropSignalForcesFullRescan() {
        var batch = FileChangeBatch()
        batch.note(path: "src/App.kt", kind: .changed)
        batch.requestFullRescan()

        #expect(batch.drain() == .fullRescan)
    }

    @Test("배출하면 비워져서 다음 배치가 새로 시작된다")
    func drainingResetsTheBatch() {
        var batch = FileChangeBatch()
        batch.note(path: "src/App.kt", kind: .changed)
        _ = batch.drain()

        #expect(batch.isEmpty)
        #expect(batch.drain() == .none)
    }

    @Test("전체 재스캔 요청도 배출 후 초기화된다")
    func drainingClearsTheFullRescanRequest() {
        var batch = FileChangeBatch()
        batch.requestFullRescan()
        #expect(batch.drain() == .fullRescan)
        #expect(batch.drain() == .none)
    }
}
