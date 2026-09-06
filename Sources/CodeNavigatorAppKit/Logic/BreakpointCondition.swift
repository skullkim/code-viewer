import CodeNavigatorContract
import Foundation

/// "i == 500 일 때만 멈춰라."
///
/// **JDWP 에는 식 조건이 없다.** 그래서 멈춘 뒤 우리가 값을 읽어 판정하고, 아니면 다시
/// 재개한다. 즉 이 타입은 조건을 *거는* 것이 아니라 이미 멈춘 자리에서 *판정하는* 것이다.
///
/// 문법은 일부러 좁다 — `변수 견줌 값` 하나뿐이다. 자바 식을 다 받으려면 JVM 안에서 코드를
/// 실행해야 하고(`InvokeMethod`), 그러면 조건 하나가 프로그램 상태를 바꿀 수 있다. 디버거가
/// 관찰하는 도구라는 성질을 조건 문법 하나로 잃는 것은 남는 장사가 아니다.
public struct BreakpointCondition: Sendable, Hashable {

    public enum Comparison: String, Sendable, Hashable, CaseIterable {
        case equal = "=="
        case notEqual = "!="
        case greaterOrEqual = ">="
        case lessOrEqual = "<="
        case greater = ">"
        case less = "<"
    }

    public let variableName: String
    public let comparison: Comparison
    public let expected: String
    /// 사용자가 적은 그대로. 화면에 되돌려 보여 준다.
    public let text: String

    /// 읽을 수 없으면 nil. **읽을 수 없는 조건을 "항상 거짓" 으로 두지 않는다** — 오타 하나로
    /// 브레이크포인트가 조용히 사라지고, 사용자는 코드를 의심하기 시작한다.
    public init?(text rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        // 긴 연산자부터 본다. `>` 를 먼저 찾으면 `>=` 를 `>` 와 `=값` 으로 쪼갠다.
        let ordered: [Comparison] = [.equal, .notEqual, .greaterOrEqual, .lessOrEqual, .greater, .less]
        for comparison in ordered {
            guard let range = text.range(of: comparison.rawValue) else { continue }
            let name = text[text.startIndex..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let value = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { return nil }
            // 이름이 식별자가 아니면 우리가 다룰 수 있는 조건이 아니다.
            guard name.range(of: "^[A-Za-z_$][A-Za-z0-9_$]*$", options: .regularExpression) != nil else {
                return nil
            }
            // 기대값도 본다. `i ===` 는 위 쪼개기에서 값 `=` 로 통과하는데, 그건 조건이 아니라
            // 오타다. 값을 안 보면 오타가 "항상 안 맞는 조건" 이 되어 브레이크포인트가
            // 조용히 사라진다.
            guard Self.isReadableValue(value) else { return nil }
            self.variableName = name
            self.comparison = comparison
            self.expected = value
            self.text = text
            return
        }
        return nil
    }

    /// 지금 멈춘 자리의 변수들로 판정한다.
    ///
    /// **모르면 멈춘다.** 조건이 가리키는 변수가 그 자리에 없으면 참으로 친다 — 조용히 안
    /// 멈추면 사용자는 조건이 틀렸는지 코드가 안 지나갔는지 구별할 수 없고, 조건을 고치는
    /// 대신 코드를 의심하기 시작한다.
    public func matches(variables: [JavaVariable]) -> Bool {
        guard let variable = variables.first(where: { $0.name == variableName }) else { return true }

        let actual = Self.unquoted(variable.value)
        let wanted = Self.unquoted(expected)

        // 숫자는 숫자로 견준다. 문자열로 하면 `"9" > "10"` 이 참이라 루프에서 엉뚱한 회차에
        // 멈춘다.
        if let actualNumber = Double(actual), let wantedNumber = Double(wanted) {
            switch comparison {
            case .equal: return actualNumber == wantedNumber
            case .notEqual: return actualNumber != wantedNumber
            case .greater: return actualNumber > wantedNumber
            case .less: return actualNumber < wantedNumber
            case .greaterOrEqual: return actualNumber >= wantedNumber
            case .lessOrEqual: return actualNumber <= wantedNumber
            }
        }

        switch comparison {
        case .equal: return actual == wanted
        case .notEqual: return actual != wanted
        // 숫자가 아닌 것에 대소를 물으면 답할 수 없다. 멈추는 쪽이다.
        case .greater, .less, .greaterOrEqual, .lessOrEqual: return true
        }
    }

    /// 숫자·따옴표 친 문자열·`true`/`false`/`null`·식별자만 값으로 인정한다.
    private static func isReadableValue(_ value: String) -> Bool {
        if Double(value) != nil { return true }
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { return true }
        if ["true", "false", "null"].contains(value) { return true }
        return value.range(of: "^[A-Za-z_$][A-Za-z0-9_$]*$", options: .regularExpression) != nil
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
    }
}
