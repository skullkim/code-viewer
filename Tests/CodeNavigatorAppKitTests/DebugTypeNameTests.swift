import Testing
@testable import CodeNavigatorAppKit

/// JDWP 가 답하는 `I` 나 `Ljava/lang/String;` 을 그대로 찍으면 변수 목록의 절반이 암호가 된다.
/// 그리고 암호는 **값이 깨진 것과 구별되지 않는다** — 사용자는 `I` 를 보고 읽기가 틀렸다고 읽는다.
@Suite("JVM 시그니처 읽기")
struct DebugTypeNameTests {

    @Test("기본 타입을 이름으로 바꾼다")
    func readsPrimitives() {
        #expect(DebugTypeName.readable("I") == "int")
        #expect(DebugTypeName.readable("J") == "long")
        #expect(DebugTypeName.readable("Z") == "boolean")
        #expect(DebugTypeName.readable("D") == "double")
        #expect(DebugTypeName.readable("V") == "void")
    }

    @Test("클래스는 패키지를 뗀 이름이다")
    func stripsThePackage() {
        #expect(DebugTypeName.readable("Ljava/lang/String;") == "String")
        #expect(DebugTypeName.readable("Lcom/woowacourse/thankoo/member/domain/Member;") == "Member")
    }

    @Test("배열은 대괄호를 붙인다")
    func marksArrays() {
        #expect(DebugTypeName.readable("[I") == "int[]")
        #expect(DebugTypeName.readable("[[J") == "long[][]")
        #expect(DebugTypeName.readable("[Ljava/lang/String;") == "String[]")
    }

    /// 손상된 시그니처 때문에 패널 전체가 사라지면 안 된다. 한 줄이 이상한 것과 디버거가
    /// 죽은 것은 크기가 다르다.
    @Test("모르는 시그니처는 그대로 두고 죽지 않는다")
    func survivesNonsense() {
        #expect(DebugTypeName.readable("") == "?")
        #expect(DebugTypeName.readable("Qwhat") == "Qwhat")
        #expect(!DebugTypeName.readable("Lbroken").isEmpty)
    }
}
