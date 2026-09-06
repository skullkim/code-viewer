import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 조건부 브레이크포인트. "i == 500 일 때만 멈춰라" — 루프 안에서 특정 회차를 잡을 때 쓴다.
///
/// **JDWP 에는 식 조건이 없다.** 그래서 멈춘 뒤 우리가 값을 읽어 판정하고, 아니면 다시
/// 재개한다. 그 재개가 사용자에게 보이면 안 된다 — 화면이 깜빡이면 "멈췄다 말았다" 로 읽힌다.
@Suite("조건부 브레이크포인트")
struct BreakpointConditionTests {

    @Test("빈 조건은 항상 참이다 — 조건 없는 브레이크포인트와 같다")
    func anEmptyConditionAlwaysMatches() {
        #expect(BreakpointCondition(text: "") == nil)
        #expect(BreakpointCondition(text: "   ") == nil)
    }

    @Test("변수와 숫자를 견준다")
    func comparesAVariableToANumber() throws {
        let condition = try #require(BreakpointCondition(text: "i == 500"))
        #expect(condition.matches(variables: [variable("i", "500")]))
        #expect(!condition.matches(variables: [variable("i", "499")]))
    }

    @Test("여섯 가지 견줌을 안다")
    func knowsSixComparisons() throws {
        let cases: [(String, String, Bool)] = [
            ("i == 5", "5", true), ("i != 5", "5", false),
            ("i > 4", "5", true), ("i < 4", "5", false),
            ("i >= 5", "5", true), ("i <= 4", "5", false),
        ]
        for (text, value, expected) in cases {
            let condition = try #require(
                BreakpointCondition(text: text), "\(text) 를 못 읽었다" as Comment
            )
            #expect(
                condition.matches(variables: [variable("i", value)]) == expected, "\(text)" as Comment
            )
        }
    }

    @Test("문자열도 견준다 — 따옴표는 벗긴다")
    func comparesStrings() throws {
        let condition = try #require(BreakpointCondition(text: "name == \"probe\""))
        #expect(condition.matches(variables: [variable("name", "\"probe\"")]))
        #expect(!condition.matches(variables: [variable("name", "\"other\"")]))
    }

    @Test("true / false 도 견준다")
    func comparesBooleans() throws {
        let condition = try #require(BreakpointCondition(text: "flag == true"))
        #expect(condition.matches(variables: [variable("flag", "true")]))
        #expect(!condition.matches(variables: [variable("flag", "false")]))
    }

    /// **없는 변수를 물으면 멈춘다.** 조용히 안 멈추면 사용자는 조건이 틀렸는지 코드가 안
    /// 지나갔는지 구별할 수 없고, 조건을 고치는 대신 코드를 의심하기 시작한다.
    @Test("조건이 가리키는 변수가 없으면 멈춘다")
    func stopsWhenTheVariableIsMissing() throws {
        let condition = try #require(BreakpointCondition(text: "missing == 1"))
        #expect(condition.matches(variables: [variable("i", "5")]))
    }

    /// 읽을 수 없는 조건도 멈추는 쪽이다. 안 멈추면 오타 하나로 브레이크포인트가 사라진다.
    @Test("읽을 수 없는 조건은 만들지 않는다")
    func refusesNonsense() {
        #expect(BreakpointCondition(text: "i ===") == nil)
        #expect(BreakpointCondition(text: "그냥 말") == nil)
    }

    /// 숫자 견줌은 문자열 비교가 아니다. `"9" > "10"` 은 문자열로는 참이라, 문자열로 비교하면
    /// 루프에서 엉뚱한 회차에 멈춘다.
    @Test("숫자는 숫자로 견준다 — 문자열로 견주지 않는다")
    func comparesNumbersNumerically() throws {
        let condition = try #require(BreakpointCondition(text: "i > 9"))
        #expect(condition.matches(variables: [variable("i", "10")]))
        #expect(!condition.matches(variables: [variable("i", "9")]))
    }

    private func variable(_ name: String, _ value: String) -> JavaVariable {
        JavaVariable(name: name, typeSignature: "I", value: value)
    }
}
