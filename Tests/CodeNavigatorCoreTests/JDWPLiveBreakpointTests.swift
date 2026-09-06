import Testing
import Foundation
@testable import CodeNavigatorCore

/// 1차 범위 전체를 실제 JVM 에 대고 한 번에 확인한다 — 붙기 → 걸기 → 멈춤 → 스택 → 변수 → 풀기.
///
/// 단위 테스트는 프레이밍이 맞는지만 답한다. 브레이크포인트가 실제로 걸리는지, 멈춘 자리에서
/// 변수 값이 진짜 그 값인지는 JVM 만 답할 수 있다.
@Suite("JDWP 라이브 브레이크포인트", .serialized)
struct JDWPLiveBreakpointTests {

    private static var isEnabled: Bool { ProcessInfo.processInfo.environment["JDWP_LIVE"] == "1" }
    private static var port: UInt16 { UInt16(ProcessInfo.processInfo.environment["JDWP_PORT"] ?? "") ?? 5005 }

    @Test("브레이크포인트에 멈추고 스택과 지역 변수를 읽은 뒤 다시 푼다")
    func stopsAndReadsTheFrame() async throws {
        guard Self.isEnabled else {
            print("SKIP: JDWP_LIVE=1 이 아니라 라이브 브레이크포인트를 건너뛴다")
            return
        }

        let session = try await JavaDebugSession.attach(host: "127.0.0.1", port: Self.port)
        defer { Task { await session.close() } }

        // Probe.step 의 `String label = "step-" + doubled;` 줄.
        let requestID = try await session.setBreakpoint(className: "Probe", line: 6)
        print("LIVE breakpoint request=\(requestID)")

        let stop = try await session.waitForBreakpoint()
        print("LIVE stopped thread=\(stop.threadID) codeIndex=\(stop.codeIndex)")

        let suspendCount = try await session.suspendCount(threadID: stop.threadID)
        print("LIVE suspendCount=\(suspendCount)")

        let frames = try await session.stackFrames(threadID: stop.threadID)
        #expect(!frames.isEmpty, "멈췄는데 스택이 비어 있다")
        let top = try #require(frames.first)
        print("LIVE top frame \(top.className).\(top.methodName):\(top.line)")
        #expect(top.className == "Probe")
        #expect(top.methodName == "step")
        #expect(top.line == 6, "멈춘 줄이 건 줄과 달랐다")

        let variables = try await session.localVariables(
            frame: top, threadID: stop.threadID, codeIndex: stop.codeIndex
        )
        for variable in variables {
            print("LIVE var \(variable.name): \(variable.typeSignature) = \(variable.value)")
        }
        // `input` 은 파라미터라 이 지점에서 반드시 살아 있고, `doubled` 는 앞 줄에서 대입됐다.
        let byName = Dictionary(uniqueKeysWithValues: variables.map { ($0.name, $0.value) })
        let input = try #require(byName["input"], "파라미터 input 이 없다")
        let doubled = try #require(byName["doubled"], "앞 줄에서 대입된 doubled 가 없다")
        #expect(Int(doubled) == Int(input).map { $0 * 2 }, "doubled 가 input 의 두 배가 아니다")

        try await session.clearBreakpoint(requestID: requestID)
        try await session.resume()
        print("LIVE resumed")
    }
}
