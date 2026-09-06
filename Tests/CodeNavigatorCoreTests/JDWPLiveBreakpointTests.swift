import Testing
import Foundation
import CodeNavigatorContract
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

    /// **한 번 누르면 한 걸음만 간다.** 스텝 요청을 안 거두면 JVM 이 매 줄 보고하고,
    /// 사용자는 "한 번 눌렀는데 계속 멈춘다" 를 겪는다 — 그게 브레이크포인트 때문인지
    /// 스텝 때문인지 화면에서는 구별되지 않는다.
    @Test("한 줄 실행이 정확히 한 줄만 나아간다")
    func stepsExactlyOneLine() async throws {
        guard Self.isEnabled else {
            print("SKIP: JDWP_LIVE=1 이 아니라 라이브 스텝 검증을 건너뛴다")
            return
        }

        let session = try await JavaDebugSession.attach(host: "127.0.0.1", port: Self.port)
        defer { Task { await session.close() } }

        // 5행(`int doubled = ...`)에 걸고 멈춘 뒤, 한 줄 넘기면 6행이어야 한다.
        let requestID = try await session.setBreakpoint(className: "Probe", line: 5)
        let stop = try await session.waitForBreakpoint()
        let before = try #require(try await session.stackFrames(threadID: stop.threadID).first)
        print("LIVE(step) 멈춤 \(before.className).\(before.methodName):\(before.line)")
        #expect(before.line == 5)

        // 브레이크포인트를 먼저 거둔다. 안 거두면 다음 바퀴의 5행에서 멈춘 것을 스텝의
        // 결과로 잘못 읽는다 — 검사가 자기가 만든 신호를 자기 답으로 쓰는 꼴이다.
        try await session.clearBreakpoint(requestID: requestID)

        try await session.step(.over, threadID: stop.threadID)
        let stepped = try await session.waitForBreakpoint()
        let after = try #require(try await session.stackFrames(threadID: stepped.threadID).first)
        print("LIVE(step) 한 줄 뒤 \(after.className).\(after.methodName):\(after.line)")
        #expect(after.line == 6, "한 줄 넘겼는데 \(after.line)행이다")

        // 요청이 거둬졌는지 본다. 안 거뒀으면 재개하자마자 또 멈춘다.
        try await session.resume()
        print("LIVE(step) 재개")
    }

    /// **아직 로드되지 않은 클래스에 건다.** `suspend=y` 로 띄운 JVM 이 그 상태다 — 처음부터
    /// 디버깅하려는 사람의 정상 상태이고, 예전에는 여기서 `classNotLoaded` 로 그냥 실패했다.
    ///
    /// 별도 포트를 쓴다. 다른 라이브 테스트가 쓰는 5005 는 `suspend=n` 이라 이미 로드돼 있고,
    /// 그러면 이 테스트가 재려는 상황이 성립하지 않는다.
    @Test("로드 전 클래스에 건 브레이크포인트가 로드 뒤에 걸린다")
    func placesABreakpointOnAClassThatHasNotLoadedYet() async throws {
        guard Self.isEnabled else {
            print("SKIP: JDWP_LIVE=1 이 아니라 로드 대기 검증을 건너뛴다")
            return
        }
        guard let port = UInt16(ProcessInfo.processInfo.environment["JDWP_SUSPENDED_PORT"] ?? "") else {
            print("SKIP: JDWP_SUSPENDED_PORT 가 없다 — suspend=y 로 띄운 JVM 이 필요하다")
            return
        }

        let session = try await JavaDebugSession.attach(host: "127.0.0.1", port: port)
        defer { Task { await session.close() } }

        // 이 시점에 Probe 는 아직 로드 전이다. 그것부터 확인한다 — 이미 로드돼 있으면 이
        // 테스트는 예약 경로를 밟지 않고 통과해 아무것도 지키지 않는다.
        let loaded = try await session.loadedClassID(named: "Probe")
        #expect(loaded == nil, "Probe 가 이미 로드돼 있다 — suspend=y 가 아니었다")

        let requestID = try await session.setBreakpoint(className: "Probe", line: 6)
        print("LIVE(prepare) 예약 request=\(requestID)")

        // 이제 달리게 한다. 로드되면 우리가 걸고, 그 뒤 6행에서 멈춰야 한다.
        try await session.resume()
        let stop = try await session.waitForBreakpoint()
        let top = try #require(try await session.stackFrames(threadID: stop.threadID).first)
        print("LIVE(prepare) 멈춤 \(top.className).\(top.methodName):\(top.line)")
        #expect(top.className == "Probe")
        #expect(top.line == 6)

        try await session.clearBreakpoint(requestID: requestID)
        try await session.resume()
    }

    /// 변수 안을 연다 — 실제 디버깅에서 가장 많이 하는 동작이다.
    @Test("객체·문자열·배열의 안을 읽는다")
    func opensWhatIsInsideAValue() async throws {
        guard Self.isEnabled else {
            print("SKIP: JDWP_LIVE=1 이 아니라 객체 그래프 검증을 건너뛴다")
            return
        }

        let session = try await JavaDebugSession.attach(host: "127.0.0.1", port: Self.port)
        defer { Task { await session.close() } }

        let requestID = try await session.setBreakpoint(className: "Probe", line: 22)
        let stop = try await session.waitForBreakpoint()
        let top = try #require(try await session.stackFrames(threadID: stop.threadID).first)
        let locals = try await session.localVariables(
            frame: top, threadID: stop.threadID, codeIndex: stop.codeIndex
        )

        // `this` 를 연다 — 필드가 넷이어야 한다.
        let this = try #require(locals.first { $0.name == "this" })
        let objectID = try #require(this.objectID, "this 를 펼칠 손잡이가 없다")
        let fields = try await session.fields(ofObject: objectID, typeSignature: this.typeSignature)
        let byName = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0) })
        print("LIVE(fields) this → \(fields.map { "\($0.name)=\($0.value)" }.joined(separator: " · "))")
        #expect(byName["counter"] != nil, "인스턴스 필드가 안 보인다")
        #expect(byName["label"] != nil)
        #expect(byName["numbers"] != nil)
        #expect(byName["inner"] != nil)

        // 문자열은 내용이 나와야 한다 — `String@7` 이 아니라.
        let label = try #require(byName["label"])
        let labelID = try #require(label.objectID)
        let labelInside = try await session.fields(ofObject: labelID, typeSignature: label.typeSignature)
        print("LIVE(fields) label → \(labelInside.map(\.value).joined())")
        #expect(labelInside.first?.value.contains("probe") == true)

        // 배열은 원소가 나와야 한다.
        let numbers = try #require(byName["numbers"])
        let numbersID = try #require(numbers.objectID)
        let elements = try await session.fields(ofObject: numbersID, typeSignature: numbers.typeSignature)
        print("LIVE(fields) numbers → \(elements.map(\.value).joined(separator: ","))")
        #expect(elements.map(\.value) == ["10", "20", "30"])

        // 중첩 객체도 한 겹 더 열린다.
        let inner = try #require(byName["inner"])
        let innerID = try #require(inner.objectID)
        let innerFields = try await session.fields(ofObject: innerID, typeSignature: inner.typeSignature)
        print("LIVE(fields) inner → \(innerFields.map { "\($0.name)=\($0.value)" }.joined(separator: " · "))")
        #expect(innerFields.contains { $0.name == "depth" && $0.value == "7" })

        try await session.clearBreakpoint(requestID: requestID)
        try await session.resume()
    }

    /// 앱이 실제로 하는 순서다 — 이벤트 리스너를 먼저 띄워 두고, 그 **와중에** 사용자가
    /// 브레이크포인트를 건다.
    ///
    /// 이 조합이 라이브에서 죽었다. 소켓 전송이 읽기와 쓰기에 같은 직렬 큐를 써서, 이벤트를
    /// 기다리며 막힌 읽기 뒤로 `setBreakpoint` 의 전송이 줄을 섰다. 증상은 "브레이크포인트를
    /// 걸었는데 아무 일도 안 일어남" — 오류도 로그도 없었다.
    @Test("이벤트를 기다리는 중에 건 브레이크포인트도 걸린다")
    func setsABreakpointWhileTheListenerWaits() async throws {
        guard Self.isEnabled else {
            print("SKIP: JDWP_LIVE=1 이 아니라 라이브 리스너 검증을 건너뛴다")
            return
        }

        let session = try await JavaDebugSession.attach(host: "127.0.0.1", port: Self.port)
        defer { Task { await session.close() } }

        // 먼저 리스너를 띄운다. 아직 브레이크포인트가 없으니 영원히 기다릴 자세다.
        let listener = Task { try await session.waitForBreakpoint() }

        // 리스너가 실제로 소켓 읽기에 들어갈 시간을 준다. 안 그러면 경쟁을 재현하지 못하고
        // 통과해 버린다 — 그러면 이 테스트는 아무것도 지키지 않는다.
        try await Task.sleep(nanoseconds: 500_000_000)

        let requestID = try await session.setBreakpoint(className: "Probe", line: 6)
        print("LIVE(listener) breakpoint request=\(requestID)")

        let stop = try await listener.value
        print("LIVE(listener) stopped thread=\(stop.threadID)")

        let frames = try await session.stackFrames(threadID: stop.threadID)
        let top = try #require(frames.first)
        #expect(top.className == "Probe")
        #expect(top.line == 6)
        print("LIVE(listener) top \(top.className).\(top.methodName):\(top.line)")

        try await session.clearBreakpoint(requestID: requestID)
        try await session.resume()
    }
}
