import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 거터 표시가 틀리는 방식은 조용하다. 걸지 않은 줄에 점이 찍히면 사용자는 그 줄을 의심하고,
/// 건 줄에 안 찍히면 브레이크포인트가 안 걸린 줄 안다. 둘 다 오류가 안 난다.
@Suite("디버그 거터 표시")
@MainActor
struct DebugMarkerTests {

    @Test("멈춘 자리는 우리가 건 브레이크포인트일 때만 채워진다")
    func onlyNamesAStopItCanPlace() async throws {
        let model = DebugModel()
        let session = MarkerFakeSession()
        await model.attach(session: session, host: "127.0.0.1", port: 5005)
        await model.toggleBreakpoint(path: "src/Probe.java", line: 6, className: "Probe")

        session.stop = JavaStopEvent(
            threadID: 1, requestID: session.lastIssuedRequestID,
            classID: 2, methodID: 3, codeIndex: 4
        )
        session.letItStop()
        await model.waitForNextStopForTesting()

        #expect(model.stoppedBreakpointPath == "src/Probe.java")
        #expect(model.stoppedLine == 6)
    }

    /// 우리가 걸지 않은 자리에서 멈출 수 있다 — 다른 디버거가 남긴 것, 예외 중단. 그때
    /// 클래스 이름으로 파일을 되짚으면 틀릴 수 있고, **엉뚱한 파일이 열리는 것은 아무것도
    /// 안 여는 것보다 나쁘다.** 사용자가 그 파일을 고치기 시작한다.
    @Test("모르는 자리에서 멈추면 파일을 추측하지 않는다")
    func doesNotGuessAFileItDoesNotKnow() async throws {
        let model = DebugModel()
        let session = MarkerFakeSession()
        await model.attach(session: session, host: "127.0.0.1", port: 5005)

        session.stop = JavaStopEvent(
            threadID: 1, requestID: 999, classID: 2, methodID: 3, codeIndex: 4
        )
        session.letItStop()
        await model.waitForNextStopForTesting()

        #expect(model.stoppedBreakpointPath == nil)
        #expect(model.stoppedLine == nil)
    }

    @Test("풀면 멈춘 자리를 비운다 — 낡은 화살표가 남지 않는다")
    func clearsTheStoppedPlaceOnResume() async throws {
        let model = DebugModel()
        let session = MarkerFakeSession()
        await model.attach(session: session, host: "127.0.0.1", port: 5005)
        await model.toggleBreakpoint(path: "src/Probe.java", line: 6, className: "Probe")
        session.stop = JavaStopEvent(
            threadID: 1, requestID: session.lastIssuedRequestID,
            classID: 2, methodID: 3, codeIndex: 4
        )
        session.letItStop()
        await model.waitForNextStopForTesting()

        await model.resume()
        #expect(model.stoppedBreakpointPath == nil)
        #expect(model.stoppedLine == nil)
    }

    /// 표시는 **지금 열려 있는 파일 것만** 그린다. 다른 파일의 줄 번호를 이 파일에 찍으면
    /// 걸지 않은 자리에 점이 생긴다.
    @Test("다른 파일의 브레이크포인트는 이 파일에 그리지 않는다")
    func drawsOnlyThisFilesBreakpoints() {
        let markers = EditorDebugMarkers(
            path: "src/Probe.java", breakpointLines: [6], stoppedLine: 6
        )
        #expect(markers.breakpointLines == [6])
        #expect(EditorDebugMarkers.cleared(path: "src/Probe.java").breakpointLines.isEmpty)
        #expect(EditorDebugMarkers.cleared(path: "src/Probe.java").stoppedLine == nil)
    }

    /// 브레이크포인트 빨강이 오류 빨강과 같으면 화면이 매번 사고처럼 보인다.
    @Test("브레이크포인트 색이 오류 색과 다르다")
    func theBreakpointIsNotAnError() {
        for scheme in AppearanceScheme.allCases {
            let debug = SyntaxPaletteBuilder.debugPalette(for: scheme)
            let danger = EditorColor(DesignTokens.danger.value(for: scheme))
            #expect(debug.breakpointForeground != danger, "\(scheme)")
        }
    }

    /// 멈춘 줄 배경 위에서 코드가 계속 읽혀야 한다.
    @Test("멈춘 줄 배경 위에서 코드가 읽힌다")
    func codeStaysLegibleOnTheStoppedLine() {
        for scheme in AppearanceScheme.allCases {
            let debug = SyntaxPaletteBuilder.debugPalette(for: scheme)
            let text = EditorColor(DesignTokens.textPrimary.value(for: scheme))
            let ratio = ColorContrast.ratio(
                RGBColor(
                    red: Double(text.red) / 255,
                    green: Double(text.green) / 255,
                    blue: Double(text.blue) / 255
                ),
                RGBColor(
                    red: Double(debug.stoppedLineBackground.red) / 255,
                    green: Double(debug.stoppedLineBackground.green) / 255,
                    blue: Double(debug.stoppedLineBackground.blue) / 255
                )
            )
            #expect(ratio >= 4.5, "\(scheme) 멈춘 줄 대비 \(ratio)")
        }
    }
}

/// 브레이크포인트 id 를 기억하는 가짜 세션. `DebugModelTests` 의 것과 달리 발급한 id 를
/// 테스트가 알아야 한다 — 멈춤을 그 id 로 되짚는 것이 이 스위트의 주제다.
private final class MarkerFakeSession: DebugSession, @unchecked Sendable {
    var stop = JavaStopEvent(threadID: 1, requestID: 7, classID: 2, methodID: 3, codeIndex: 4)
    private(set) var lastIssuedRequestID: Int32 = 0
    private var nextRequestID: Int32 = 41
    private let gate = MarkerGate()

    func setBreakpoint(className: String, line: Int) async throws -> Int32 {
        nextRequestID += 1
        lastIssuedRequestID = nextRequestID
        return nextRequestID
    }
    func clearBreakpoint(requestID: Int32) async throws {}
    func waitForBreakpoint() async throws -> JavaStopEvent {
        await gate.wait()
        return stop
    }
    func letItStop() { gate.open() }
    func stackFrames(threadID: UInt64) async throws -> [JavaStackFrame] {
        [JavaStackFrame(frameID: 1, className: "Probe", methodName: "step", line: 6, classID: 2, methodID: 3)]
    }
    func localVariables(frame: JavaStackFrame, threadID: UInt64, codeIndex: UInt64) async throws -> [JavaVariable] {
        []
    }
    func resume() async throws {}
    /// 펼침 요청을 기록한다 — 무엇을 열었는지 테스트가 확인할 수 있게.
    var fieldsByObject: [UInt64: [JavaVariable]] = [:]
    private(set) var openedObjects: [UInt64] = []
    func fields(ofObject objectID: UInt64, typeSignature: String) async throws -> [JavaVariable] {
        openedObjects.append(objectID)
        return fieldsByObject[objectID] ?? []
    }
    /// 실제로 걸었는지 테스트가 확인할 수 있게 기록한다.
    private(set) var steps: [DebugStep] = []
    func step(_ step: DebugStep, threadID: UInt64) async throws { steps.append(step) }
    func close() async {}
}

private final class MarkerGate: @unchecked Sendable {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private let lock = NSLock()

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen { lock.unlock(); continuation.resume(); return }
            continuations.append(continuation)
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let pending = continuations
        continuations = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}
