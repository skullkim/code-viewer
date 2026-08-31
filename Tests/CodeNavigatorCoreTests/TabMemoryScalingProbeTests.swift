import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Is the per-cycle growth a leak or allocator settling?
///
/// A leak compounds: total growth rises in proportion to cycles, so per-cycle stays flat. Settling
/// does not: the first cycles cost something and later ones cost nothing, so per-cycle falls as
/// the count rises. One measurement cannot tell those apart — which is why 132KB/cycle at ten
/// cycles is not yet an answer.
@Suite("탭 여닫기 메모리 — 누적인가 정착인가", .serialized)
struct TabMemoryScalingProbeTests {

    @Test("회차를 늘려 가며 회당 증가가 유지되는지 본다")
    func growthPerCycleAgainstCycleCount() async throws {
        let fixture = TemporaryProjectFixture()
        for index in 0..<2_000 {
            fixture.write("src/File\(index).kt", contents: "class Service\(index) { fun run() {} }")
        }

        // 회차마다 새 프로세스에서 돈다. 한 프로세스에서 10→20→40 을 이어 재면 뒤쪽 회차가
        // 앞쪽이 덥혀 둔 할당자를 물려받아, 누수가 있어도 "회당 증가가 준다"로 보인다.
        let cycles = ProcessInfo.processInfo.environment["TAB_MEMORY_CYCLES"].flatMap(Int.init) ?? 10
        do {
            let workspace = ProjectWorkspaceEngine(
                columns: 80, rows: 24, editorExecutableOverridePath: "/nonexistent/nvim"
            )
            let warmUp = try await workspace.openProject(at: fixture.rootURL)
            try await workspace.closeTab(warmUp.tab.id)
            let baseline = await workspace.memoryFootprint().processFootprintBytes

            for _ in 0..<cycles {
                let outcome = try await workspace.openProject(at: fixture.rootURL)
                try await workspace.closeTab(outcome.tab.id)
            }
            let after = await workspace.memoryFootprint().processFootprintBytes
            let total = after - baseline
            print(String(
                format: "[누적?] %3d회 → 총 증가 %6d KB · 회당 %4d KB",
                cycles, total / 1024, (total / cycles) / 1024
            ))
            await workspace.shutDown()
        }
    }
}
