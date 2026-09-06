/// Turns a JVM type signature into something a person reads.
///
/// JDWP 는 `I`, `Ljava/lang/String;`, `[[J` 로 답한다. 그대로 화면에 찍으면 변수 목록의 절반이
/// 암호가 된다 — 그리고 그건 값이 틀린 것과 구별되지 않는다. 사용자는 `I` 를 보고 값이 깨진
/// 줄 안다.
///
/// 패키지는 뗀다. 변수 한 줄에 `java.util.concurrent.ConcurrentHashMap` 을 다 적으면 정작
/// 값이 밀려 나간다. 어느 패키지인지 알아야 하는 순간은 드물고, 그때는 값 쪽에 타입이 붙는다.
public enum DebugTypeName {

    public static func readable(_ signature: String) -> String {
        guard let first = signature.first else { return "?" }

        switch first {
        case "Z": return "boolean"
        case "B": return "byte"
        case "C": return "char"
        case "S": return "short"
        case "I": return "int"
        case "J": return "long"
        case "F": return "float"
        case "D": return "double"
        case "V": return "void"
        case "[":
            return readable(String(signature.dropFirst())) + "[]"
        case "L":
            // `Lcom/example/Thing;` → `Thing`. 세미콜론이 없는 손상된 시그니처도 그냥 읽는다 —
            // 여기서 던져 봐야 변수 한 줄 때문에 패널 전체가 사라질 뿐이다.
            let body = signature.dropFirst().drop { $0 == ";" ? false : false }
            let name = body.prefix { $0 != ";" }
            return String(name.split(separator: "/").last ?? name.split(separator: ".").last ?? "?")
        default:
            return signature
        }
    }
}
