import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// REQ-005 and design §2 F-3. What happens on ⌘B depends only on how many definitions
/// came back, and the zero case is the one that matters most: AC-3 forbids silence.
@Suite("DefinitionRouting — 정의 이동 분기 (REQ-005)")
struct DefinitionRoutingTests {

    private func definition(_ name: String, line: Int, path: String = "Sources/A.swift") -> SymbolDefinition {
        SymbolDefinition(name: name, kind: .function, path: path, line: line, signature: "func \(name)()")
    }

    @Test("정의가 하나면 팝오버 없이 바로 이동한다")
    func aSingleDefinitionNavigatesImmediately() {
        let outcome = DefinitionRouting.route(symbolName: "buildIndex", definitions: [definition("buildIndex", line: 8)])
        #expect(outcome == .navigate(path: "Sources/A.swift", line: 8))
    }

    @Test("동명 정의가 여럿이면 후보 목록을 띄운다")
    func severalDefinitionsOpenThePicker() {
        let definitions = [
            definition("handle", line: 10, path: "Sources/A.swift"),
            definition("handle", line: 22, path: "Sources/B.swift"),
            definition("handle", line: 5, path: "Sources/C.swift"),
        ]
        let outcome = DefinitionRouting.route(symbolName: "handle", definitions: definitions)
        #expect(outcome == .presentCandidates(definitions))
    }

    @Test("정의가 없으면 상태바에 에러를 띄운다 — 무반응은 금지다")
    func noDefinitionSaysSo() {
        // REQ-005 AC-3. A key press that does nothing visible is indistinguishable from a
        // broken application.
        let outcome = DefinitionRouting.route(symbolName: "nowhere", definitions: [])
        #expect(outcome == .reportNotFound(message: "✕ 'nowhere' 정의를 찾을 수 없습니다"))
    }

    @Test("커서 아래 심볼이 없으면 그것도 알린다")
    func anEmptySymbolIsReportedToo() {
        #expect(DefinitionRouting.route(symbolName: "", definitions: []) == .reportNoSymbolUnderCursor(message: "✕ 커서 위치에 심볼이 없습니다"))
        #expect(DefinitionRouting.route(symbolName: "   ", definitions: []) == .reportNoSymbolUnderCursor(message: "✕ 커서 위치에 심볼이 없습니다"))
    }

    @Test("후보 목록의 순서는 엔진이 준 순서 그대로다")
    func candidateOrderIsThEngineOrder() {
        // The engine sorts by path then line; reordering here would only create a way for
        // the picker and the reference panel to disagree.
        let definitions = [
            definition("f", line: 90, path: "Sources/Z.swift"),
            definition("f", line: 1, path: "Sources/A.swift"),
        ]
        guard case .presentCandidates(let candidates) = DefinitionRouting.route(symbolName: "f", definitions: definitions) else {
            Issue.record("후보 목록이 아니다")
            return
        }
        #expect(candidates.map(\.path) == ["Sources/Z.swift", "Sources/A.swift"])
    }
}
