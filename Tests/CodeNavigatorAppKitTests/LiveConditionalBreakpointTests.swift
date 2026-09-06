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

    @Test("멈춘 자리에서 식을 푼다 — 필드와 배열 첨자까지")
    func evaluatesExpressionsAtTheStop() async throws {
        guard Self.isEnabled else {
            print("SKIP: JDWP_LIVE=1 이 아니라 라이브 식 평가를 건너뛴다")
            return
        }

        let session = try await JavaDebugSession.attach(host: "127.0.0.1", port: Self.port)
        let model = DebugModel()
        await model.attach(session: session, host: "127.0.0.1", port: Self.port)
        defer { Task { await model.detach() } }

        await model.toggleBreakpoint(path: "Probe.java", line: 29, className: "Probe")
        await model.waitForNextStopForTesting()
        #expect(model.connection.isStopped)

        // 변수 하나
        await model.evaluate("input")
        print("LIVE(eval) input = \(model.lastExpressionResult ?? "없음")")
        #expect(Int(model.lastExpressionResult ?? "") != nil, "숫자가 안 나왔다")

        // 필드 따라가기
        await model.evaluate("this.inner.depth")
        print("LIVE(eval) this.inner.depth = \(model.lastExpressionResult ?? "없음")")
        #expect(model.lastExpressionResult == "7")

        // 배열 첨자
        await model.evaluate("this.numbers[1]")
        print("LIVE(eval) this.numbers[1] = \(model.lastExpressionResult ?? "없음")")
        #expect(model.lastExpressionResult == "20")

        // 문자열 필드
        await model.evaluate("this.label")
        print("LIVE(eval) this.label = \(model.lastExpressionResult ?? "없음")")
        #expect(model.lastExpressionResult?.contains("String@") == true)

        // 없는 것은 없다고 말한다 — 조용히 비우지 않는다
        await model.evaluate("this.nope")
        print("LIVE(eval) this.nope → \(model.lastExpressionResult ?? "없음")")
        #expect(model.lastExpressionResult?.contains("없습니다") == true)

        // 메서드 호출은 거절한다
        await model.evaluate("this.toString()")
        #expect(model.lastExpressionResult?.contains("메서드 호출 불가") == true)
    }

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
