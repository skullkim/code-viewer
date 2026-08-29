import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-NF-001 (전문 검색 ≤2초) · REQ-NF-002 / SC-8 (인덱싱 후 유휴 메모리 ≤150MB)
///
/// 인덱싱·심볼 검색 예산은 `IndexingPerformanceTests`가 재고 있었지만 **전문 검색과 메모리는
/// 아무도 재고 있지 않았다.** 재지 않는 예산은 예산이 아니라 희망이다.
///
/// 질의는 전부 **레포 전체를 훑어야 하는 것**으로 골랐다. 흔한 단어는 상한(500건)에 금방 닿아
/// 일찍 멈추므로 최악의 경우를 재지 못한다.
@Suite("성능 — 전문 검색과 메모리 (REQ-NF-001·002)", .serialized)
struct SearchPerformanceTests {

    private static let mediumProjectFileCount = 5_000
    private static let fullTextSearchBudgetInSeconds = 2.0
    private static let idleMemoryBudgetInBytes = 150 * 1_024 * 1_024

    /// The footprint Instruments and the memory gauge report — the number REQ-NF-002 is about.
    private func memoryFootprintInBytes() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        return Int(info.phys_footprint)
    }

    private func megabytes(_ bytes: Int) -> String {
        String(format: "%.1fMB", Double(bytes) / 1_048_576)
    }

    @Test("리터럴 전문 검색이 2초 안에 끝난다 — 레포 전체를 훑는 경우", .timeLimit(.minutes(2)))
    func literalFullTextSearchWithinBudget() async throws {
        let fixture = MediumProjectFixture.make(fileCount: Self.mediumProjectFileCount)
        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)

        // 한 파일에만 있는 문자열이라 상한에 걸리지 않고 5,000개를 전부 읽어야 한다.
        let start = Date()
        let result = try await engine.searchText("service-4996", mode: .literal)
        let elapsed = Date().timeIntervalSince(start)
        print("[성능] 리터럴 전문 검색(전체 스캔) \(String(format: "%.0f", elapsed * 1000))ms · \(result.items.count)건")

        #expect(result.items.count == 1)
        #expect(result.truncated == false)
        #expect(elapsed < Self.fullTextSearchBudgetInSeconds)
    }

    @Test("정규식 전문 검색이 2초 안에 끝난다 — 레포 전체를 훑는 경우", .timeLimit(.minutes(2)))
    func regularExpressionFullTextSearchWithinBudget() async throws {
        let fixture = MediumProjectFixture.make(fileCount: Self.mediumProjectFileCount)
        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)

        // 정규식은 줄마다 String 으로 디코드해야 해서 리터럴보다 비싸다 — 예산이 걸린다면 여기다.
        let start = Date()
        let result = try await engine.searchText(#"service-49\d\d"#, mode: .regularExpression)
        let elapsed = Date().timeIntervalSince(start)
        print("[성능] 정규식 전문 검색(전체 스캔) \(String(format: "%.0f", elapsed * 1000))ms · \(result.items.count)건")

        #expect(!result.items.isEmpty)
        #expect(elapsed < Self.fullTextSearchBudgetInSeconds)
    }

    @Test("상한에 닿는 흔한 질의는 일찍 멈춘다", .timeLimit(.minutes(2)))
    func commonQueryStopsAtTheCap() async throws {
        let fixture = MediumProjectFixture.make(fileCount: Self.mediumProjectFileCount)
        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)

        let start = Date()
        let result = try await engine.searchText("handle", mode: .literal)
        let elapsed = Date().timeIntervalSince(start)
        print("[성능] 흔한 질의(상한 도달) \(String(format: "%.0f", elapsed * 1000))ms · \(result.items.count)건")

        // 상한의 존재 이유가 이것이다 — 흔한 단어가 전체 스캔을 유발하지 않는다.
        #expect(result.truncated == true)
        #expect(result.items.count == TextSearcher.resultLimit)
        #expect(elapsed < Self.fullTextSearchBudgetInSeconds)
    }

    @Test("메모리 측정기가 실제로 움직인다 — 측정기 자체 검사")
    func memoryMeterActuallyRespondsToAllocation() throws {
        let before = try #require(memoryFootprintInBytes())

        // 50MB 를 실제로 만지고(touch) 유지한다. 건드리지 않으면 페이지가 잡히지 않아
        // 측정기가 움직이지 않는 것과 구분되지 않는다.
        let allocationSize = 50 * 1_024 * 1_024
        var block = [UInt8](repeating: 0, count: allocationSize)
        for offset in stride(from: 0, to: allocationSize, by: 4_096) {
            block[offset] = 1
        }

        let after = try #require(memoryFootprintInBytes())
        let observed = after - before
        print("[성능] 측정기 자체 검사: 50MB 할당 시 관측 증가 \(megabytes(observed))")

        // 측정기가 죽어 있으면(항상 같은 값) 이 단언이 잡는다 — 그렇지 않으면
        // 150MB 예산 테스트가 무엇을 재든 영원히 통과한다.
        #expect(observed > 40 * 1_024 * 1_024)
        #expect(block[0] == 1)
    }

    /// SC-8 의 권위 있는 측정은 **격리 실행**에서만 나온다.
    ///
    /// 같은 프로세스에서 앞선 테스트가 이미 페이지를 잡아 두면 인덱스가 그 자리를 재사용해
    /// 증가분이 0에 가깝게 나온다(실측: 단독 실행 20.1MB, 전체 실행 0.1MB). 그래서 이 테스트는
    /// **거짓 빨간불을 내지 않는 단언만** 두고, 진짜 판정은 `gate.sh` 가 이 테스트를 단독으로
    /// 돌려 출력 숫자로 한다. 전체 스위트 안에서는 측정 기록이 주 목적이다.
    @Test("중형 레포 인덱싱 후 유휴 메모리가 150MB를 넘지 않는다 (SC-8)", .timeLimit(.minutes(3)))
    func idleMemoryAfterIndexingWithinBudget() async throws {
        let baseline = try #require(memoryFootprintInBytes())

        let fixture = MediumProjectFixture.make(fileCount: Self.mediumProjectFileCount)
        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)

        // 인덱스를 살려둔 채로 잰다 — "유휴"는 인덱싱이 끝나고 인덱스를 들고 있는 상태다.
        //
        // `withExtendedLifetime` 이 핵심이다. 마지막 사용 이후 ARC 가 엔진을 즉시 해제할 수 있어,
        // 그냥 재면 **이미 사라진 인덱스를 재고서 "메모리를 거의 안 쓴다"고 통과**한다.
        let statistics = await engine.indexStatistics()
        let afterIndexing = try withExtendedLifetime(engine) {
            try #require(memoryFootprintInBytes())
        }
        let indexCost = afterIndexing - baseline

        print("[성능] 유휴 메모리 \(megabytes(afterIndexing)) (인덱싱 전 \(megabytes(baseline)), 인덱스 비용 \(megabytes(indexCost))) · 심볼 \(statistics.symbolCount)")

        #expect(statistics.symbolCount > 0)
        // 파일 내용을 보유하지 않는다는 설계(§4)가 지켜지면 인덱스 자체는 예산의 일부만 쓴다.
        // 절대값 단언은 두지 않는다 — 프로세스에 앞선 테스트들의 잔재가 쌓이면 내 코드와 무관하게
        // 빨간불이 된다. 절대값 판정은 게이트의 격리 실행이 한다.
        #expect(indexCost < Self.idleMemoryBudgetInBytes)
    }
}
