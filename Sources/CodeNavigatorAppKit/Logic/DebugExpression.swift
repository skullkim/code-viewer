import Foundation

/// 멈춘 자리에서 물어볼 수 있는 식.
///
/// **부작용 없는 것만 다룬다.** 자바 식을 다 받으려면 JVM 안에서 메서드를 부르는데
/// (`ObjectReference.InvokeMethod`), 그러면 물어보는 것만으로 프로그램 상태가 바뀐다.
/// 로그가 찍히고, 카운터가 오르고, 락이 잡힌다 — 디버거가 관찰하는 도구라는 성질을 편의
/// 하나로 잃는 것은 남는 장사가 아니다.
///
/// 그래서 범위는 **변수에서 시작해 필드와 배열 첨자로 내려가는 길** 하나다. 그 길은 전부
/// 읽기이고, JVM 상태를 건드리지 않는다.
public struct DebugExpression: Sendable, Hashable {

    public enum Step: Sendable, Hashable {
        case field(String)
        case index(Int)
    }

    public let root: String
    public let steps: [Step]
    /// 사용자가 적은 그대로. 화면에 되돌려 보여 준다.
    public let text: String

    public init?(text rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        // 괄호가 있으면 메서드 호출이다. 여기서 막는 것이 이 타입의 존재 이유다.
        guard !text.contains("("), !text.contains(")") else { return nil }

        var steps: [Step] = []
        var root: String?
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "[" {
                guard let close = text[index...].firstIndex(of: "]") else { return nil }
                let digits = text[text.index(after: index)..<close]
                // 첨자는 **숫자만**. 변수 첨자를 받으면 그 변수를 또 풀어야 하고, 음수는
                // 자바에 없어서 JVM 이 예외로 답하는데 그 예외가 디버거 오류처럼 보인다.
                guard let value = Int(digits), value >= 0 else { return nil }
                steps.append(.index(value))
                index = text.index(after: close)
                continue
            }
            if text[index] == "." {
                index = text.index(after: index)
                // 점 뒤에는 이름이 와야 한다. `a..b` 나 `a.` 를 받아 두면 빈 구간을 조용히
                // 건너뛰고, 사용자는 자기가 적은 것과 다른 곳의 값을 보게 된다.
                guard index < text.endIndex, text[index] != ".", text[index] != "[" else {
                    return nil
                }
                continue
            }
            let start = index
            while index < text.endIndex, text[index] != ".", text[index] != "[" {
                index = text.index(after: index)
            }
            let name = String(text[start..<index])
            guard Self.isIdentifier(name) else { return nil }
            if root == nil {
                root = name
            } else {
                steps.append(.field(name))
            }
        }

        guard let root else { return nil }
        self.root = root
        self.steps = steps
        self.text = text
    }

    private static func isIdentifier(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z_$][A-Za-z0-9_$]*$", options: .regularExpression) != nil
    }
}
