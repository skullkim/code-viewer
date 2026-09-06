import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 멈춘 자리에서 "이 값이 뭐지?" 를 묻는다. IntelliJ 의 Evaluate Expression 자리다.
///
/// **부작용 없는 것만 다룬다.** 자바 식을 다 받으려면 JVM 안에서 메서드를 부르는데, 그러면
/// 물어보는 것만으로 프로그램 상태가 바뀐다. 디버거가 관찰하는 도구라는 성질을 편의 하나로
/// 잃는 것은 남는 장사가 아니다. 필드 따라가기(`a.b.c`)와 배열 첨자(`a[0]`)까지가 범위다.
@Suite("식 평가")
struct DebugExpressionTests {

    @Test("변수 하나는 그 변수다")
    func readsAPlainVariable() throws {
        let path = try #require(DebugExpression(text: "input"))
        #expect(path.root == "input")
        #expect(path.steps.isEmpty)
    }

    @Test("점으로 필드를 따라간다")
    func followsFields() throws {
        let path = try #require(DebugExpression(text: "this.inner.depth"))
        #expect(path.root == "this")
        #expect(path.steps == [.field("inner"), .field("depth")])
    }

    @Test("대괄호로 배열 원소를 짚는다")
    func indexesArrays() throws {
        let path = try #require(DebugExpression(text: "numbers[2]"))
        #expect(path.root == "numbers")
        #expect(path.steps == [.index(2)])
    }

    @Test("섞어 쓸 수 있다")
    func mixesFieldsAndIndexes() throws {
        let path = try #require(DebugExpression(text: "this.numbers[1]"))
        #expect(path.steps == [.field("numbers"), .index(1)])
    }

    /// 괄호가 있으면 메서드 호출이다. **거절한다** — 부르면 프로그램이 바뀐다.
    @Test("메서드 호출은 거절한다 — 물어보는 것이 프로그램을 바꾸면 안 된다")
    func refusesMethodCalls() {
        #expect(DebugExpression(text: "list.size()") == nil)
        #expect(DebugExpression(text: "toString()") == nil)
    }

    @Test("읽을 수 없는 식은 만들지 않는다")
    func refusesNonsense() {
        #expect(DebugExpression(text: "") == nil)
        #expect(DebugExpression(text: "  ") == nil)
        #expect(DebugExpression(text: "a..b") == nil)
        #expect(DebugExpression(text: "a[") == nil)
        #expect(DebugExpression(text: "a[x]") == nil, "첨자는 숫자만")
        #expect(DebugExpression(text: "1abc") == nil)
    }

    /// 음수 첨자는 자바에 없다. 받아 두면 JVM 에 물었다가 예외가 오고, 그 예외가 디버거의
    /// 오류처럼 보인다.
    @Test("음수 첨자는 거절한다")
    func refusesNegativeIndexes() {
        #expect(DebugExpression(text: "a[-1]") == nil)
    }
}
