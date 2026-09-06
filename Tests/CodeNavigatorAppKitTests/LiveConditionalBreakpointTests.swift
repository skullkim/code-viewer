import Testing
import Foundation
import CodeNavigatorContract
import CodeNavigatorCore
@testable import CodeNavigatorAppKit

/// 조건부 브레이크포인트를 **실제 JVM 으로** 잰다.
///
/// 가짜 세션으로는 "조건이 거짓이면 재개한다" 까지만 확인된다. 진짜로 물어야 하는 것은
/// 루프가 도는 동안 조건에 맞는 회차에서만 멈추는가인데, 그건 시간이 흐르는 시스템에서만
/// 성립한다.
@Suite("라이브 조건부 브레이크포인트", .serialized)
@MainActor
struct LiveConditionalBreakpointTests {

    private static var isEnabled: Bool { ProcessInfo.processInfo.environment["JDWP_LIVE"] == "1" }
    private static var port: UInt16 { UInt16(ProcessInfo.processInfo.environment["JDWP_PORT"] ?? "") ?? 5005 }

    @Test("조건에 맞는 회차에서만 멈춘다")
    func stopsOnlyOnTheMatchingIteration() async throws {
        guard Self.isEnabled else {
            print("SKIP: JDWP_LIVE=1 이 아니라 라이브 조건 검증을 건너뛴다")
            return
        }

        let session = try await JavaDebugSession.attach(host: "127.0.0.1", port: Self.port)
        let model = DebugModel()
        await model.attach(session: session, host: "127.0.0.1", port: Self.port)
        defer { Task { await model.detach() } }

        await model.toggleBreakpoint(path: "Probe.java", line: 29, className: "Probe")
        let id = try #require(model.breakpoints.first?.id, "브레이크포인트를 못 걸었다")
        #expect(model.lastError == nil, "\(model.lastError ?? "")")

        // 곧 도달할 값을 고른다. 이미 지나간 값을 고르면 "조건이 동작한다" 와 "영영 안 맞는다"
        // 를 구별할 수 없다 — 둘 다 "안 멈춤" 으로 보인다.
        await model.waitForNextStopForTesting()
        let current = try #require(
            model.variables.first { $0.name == "input" }.flatMap { Int($0.value) },
            "input 을 못 읽었다"
        )
        let target = current + 20
        print("LIVE(cond) 지금 input=\(current), 목표 \(target)")

        model.setCondition("input == \(target)", forBreakpointWithID: id)
        #expect(model.breakpoints.first?.condition != nil, "조건이 안 걸렸다")
        await model.resume()

        // 20 회차면 약 1초. 넉넉히 기다리되 무한히는 아니다.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if model.connection.isStopped, !model.variables.isEmpty { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(model.connection.isStopped, "조건에 맞는 회차가 지나갔는데 안 멈췄다")
        let stoppedAt = model.variables.first { $0.name == "input" }?.value
        print("LIVE(cond) 멈춘 자리 input=\(stoppedAt ?? "없음")")
        #expect(stoppedAt == "\(target)", "조건과 다른 회차에서 멈췄다")
    }
}
