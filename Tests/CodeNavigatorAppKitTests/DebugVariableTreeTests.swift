import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 변수 패널이 나무가 된다. 평평한 목록과 다른 점은 **어느 줄이 누구의 자식인지** 뿐인데,
/// 그걸 틀리면 다른 객체의 필드가 이 객체 것처럼 보인다 — 오류가 아니라 그냥 틀린 값이다.
@Suite("디버그 변수 나무")
@MainActor
struct DebugVariableTreeTests {

    private func rows(_ model: DebugModel) -> [DebugVariableRow] {
        model.variableRows
    }

    @Test("펼치기 전에는 최상위만 보인다")
    func showsOnlyTheTopLevelUntilExpanded() {
        let model = DebugModel()
        model.setVariablesForTesting([
            JavaVariable(name: "this", typeSignature: "LProbe;", value: "Object@3", objectID: 3),
            JavaVariable(name: "input", typeSignature: "I", value: "42"),
        ])
        #expect(rows(model).map(\.variable.name) == ["this", "input"])
        #expect(rows(model).allSatisfy { $0.depth == 0 })
    }

    @Test("펼치면 자식이 바로 아래에 한 단 들여써서 들어간다")
    func insertsChildrenBelowTheirParent() async {
        let model = DebugModel()
        let session = TreeFakeSession()
        session.fieldsByObject[3] = [
            JavaVariable(name: "counter", typeSignature: "I", value: "7"),
            JavaVariable(name: "label", typeSignature: "Ljava/lang/String;", value: "String@6", objectID: 6),
        ]
        await model.attach(session: session, host: "127.0.0.1", port: 5005)
        model.setVariablesForTesting([
            JavaVariable(name: "this", typeSignature: "LProbe;", value: "Object@3", objectID: 3),
            JavaVariable(name: "input", typeSignature: "I", value: "42"),
        ])

        await model.toggleExpansion(of: rows(model)[0])

        #expect(rows(model).map(\.variable.name) == ["this", "counter", "label", "input"])
        #expect(rows(model).map(\.depth) == [0, 1, 1, 0])
        #expect(session.openedObjects == [3])
    }

    /// 같은 것을 두 번 열면 두 번 묻지 않는다. 디버기는 멈춰 있고 값은 안 변하는데, 매번
    /// 왕복하면 큰 객체에서 패널이 눈에 띄게 느려진다.
    @Test("두 번째 펼치기는 다시 묻지 않는다")
    func doesNotAskTwiceForTheSameObject() async {
        let model = DebugModel()
        let session = TreeFakeSession()
        session.fieldsByObject[3] = [JavaVariable(name: "counter", typeSignature: "I", value: "7")]
        await model.attach(session: session, host: "127.0.0.1", port: 5005)
        model.setVariablesForTesting([
            JavaVariable(name: "this", typeSignature: "LProbe;", value: "Object@3", objectID: 3)
        ])

        await model.toggleExpansion(of: rows(model)[0])
        await model.toggleExpansion(of: rows(model)[0])   // 접는다
        await model.toggleExpansion(of: rows(model)[0])   // 다시 편다
        #expect(session.openedObjects == [3], "같은 객체를 두 번 물었다")
    }

    @Test("접으면 자식이 사라진다 — 손자까지 함께")
    func collapsingHidesDescendants() async {
        let model = DebugModel()
        let session = TreeFakeSession()
        session.fieldsByObject[3] = [
            JavaVariable(name: "inner", typeSignature: "LInner;", value: "Object@8", objectID: 8)
        ]
        session.fieldsByObject[8] = [JavaVariable(name: "depth", typeSignature: "I", value: "7")]
        await model.attach(session: session, host: "127.0.0.1", port: 5005)
        model.setVariablesForTesting([
            JavaVariable(name: "this", typeSignature: "LProbe;", value: "Object@3", objectID: 3)
        ])

        await model.toggleExpansion(of: rows(model)[0])
        await model.toggleExpansion(of: rows(model)[1])
        #expect(rows(model).map(\.variable.name) == ["this", "inner", "depth"])

        await model.toggleExpansion(of: rows(model)[0])
        #expect(rows(model).map(\.variable.name) == ["this"], "손자가 남았다")
    }

    /// 기본형은 열 수 없다. 삼각형을 그리면 사용자가 눌러 보고 아무 일도 안 일어나는 것을 겪는다.
    @Test("기본형에는 펼침 손잡이가 없다")
    func primitivesHaveNoHandle() {
        let model = DebugModel()
        model.setVariablesForTesting([JavaVariable(name: "input", typeSignature: "I", value: "42")])
        #expect(rows(model)[0].variable.isExpandable == false)
    }

    /// 필드가 없는 객체도 열 수는 있다. 그때 "필드 없음" 을 말해야 한다 — 아무것도 안 나오면
    /// 사용자는 눌리지 않았다고 읽는다.
    @Test("필드가 없는 객체는 그렇다고 말한다")
    func saysWhenAnObjectHasNoFields() async {
        let model = DebugModel()
        let session = TreeFakeSession()
        session.fieldsByObject[3] = []
        await model.attach(session: session, host: "127.0.0.1", port: 5005)
        model.setVariablesForTesting([
            JavaVariable(name: "empty", typeSignature: "LEmpty;", value: "Object@3", objectID: 3)
        ])

        await model.toggleExpansion(of: rows(model)[0])
        #expect(rows(model).count == 2)
        #expect(rows(model)[1].variable.name == "필드 없음")
        #expect(rows(model)[1].variable.isExpandable == false)
    }

    /// 걸음을 떼거나 재개하면 객체 id 가 의미를 잃는다. 펼친 상태를 들고 있으면 다음 멈춤에서
    /// **다른 객체의 값을 옛 이름으로** 보여 준다.
    @Test("재개하면 펼친 상태를 버린다")
    func forgetsExpansionOnResume() async {
        let model = DebugModel()
        let session = TreeFakeSession()
        session.fieldsByObject[3] = [JavaVariable(name: "counter", typeSignature: "I", value: "7")]
        await model.attach(session: session, host: "127.0.0.1", port: 5005)
        model.setVariablesForTesting([
            JavaVariable(name: "this", typeSignature: "LProbe;", value: "Object@3", objectID: 3)
        ])
        await model.toggleExpansion(of: rows(model)[0])
        #expect(rows(model).count == 2)

        await model.resume()
        model.setVariablesForTesting([
            JavaVariable(name: "this", typeSignature: "LProbe;", value: "Object@3", objectID: 3)
        ])
        #expect(rows(model).count == 1, "재개 뒤에도 펼침이 남아 있다")
    }
}

private final class TreeFakeSession: DebugSession, @unchecked Sendable {
    var fieldsByObject: [UInt64: [JavaVariable]] = [:]
    private(set) var openedObjects: [UInt64] = []

    func setBreakpoint(className: String, line: Int) async throws -> Int32 { 1 }
    func clearBreakpoint(requestID: Int32) async throws {}
    func waitForBreakpoint() async throws -> JavaStopEvent {
        // 이 스위트는 멈춤을 다루지 않는다. 영원히 기다려 리스너가 화면을 건드리지 않게 둔다.
        try await Task.sleep(nanoseconds: .max)
        throw CancellationError()
    }
    func stackFrames(threadID: UInt64) async throws -> [JavaStackFrame] { [] }
    func localVariables(frame: JavaStackFrame, threadID: UInt64, codeIndex: UInt64) async throws -> [JavaVariable] { [] }
    func resume() async throws {}
    func step(_ step: DebugStep, threadID: UInt64) async throws {}
    func fields(ofObject objectID: UInt64, typeSignature: String) async throws -> [JavaVariable] {
        openedObjects.append(objectID)
        return fieldsByObject[objectID] ?? []
    }
    /// 규칙을 기록한다 — 껐는지 켰는지 테스트가 확인할 수 있게.
    private(set) var exceptionRule: ExceptionBreakpointRule = .off
    func setExceptionBreakpoint(_ rule: ExceptionBreakpointRule) async throws {
        exceptionRule = rule
    }
    /// 지켜보는 필드를 기록한다.
    private(set) var watchedFields: [String] = []
    func watchField(named name: String, inClass className: String) async throws -> Int32 {
        watchedFields.append("\(className).\(name)")
        return Int32(watchedFields.count)
    }
    func clearWatchpoint(requestID: Int32) async throws {}
    func close() async {}
}
