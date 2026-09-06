import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// 지금 변수 패널은 `this Probe = Object@3` 까지만 보여준다. 실제 디버깅에서 가장 많이 하는
/// 동작이 그 안을 여는 것인데 그게 없다.
///
/// 필드를 여는 데 필요한 것 둘: 타입의 **필드 목록**(`ReferenceType.Fields`)과 그 객체의
/// **값**(`ObjectReference.GetValues`). 목록은 타입에 딸리고 값은 인스턴스에 딸린다 — 둘을
/// 섞으면 다른 객체의 값을 이 객체 것으로 보여 준다.
@Suite("JDWP 객체 필드")
struct JDWPObjectFieldsTests {

    @Test("Fields 응답은 필드당 문자열 셋이 아니라 둘이다")
    func parsesTheFieldList() throws {
        var payload = bigEndian(UInt32(2))
        for (id, name, signature) in [
            (UInt64(11), "counter", "I"),
            (UInt64(12), "name", "Ljava/lang/String;"),
        ] {
            payload += identifier(id, size: 8)
            payload += string(name)
            payload += string(signature)
            payload += bigEndian(UInt32(2))   // modifiers
        }

        let fields = try JDWPField.parseList(payload: payload, fieldIDSize: 8)
        #expect(fields.count == 2)
        #expect(fields[0].name == "counter")
        #expect(fields[0].signature == "I")
        #expect(fields[1].id == 12)
    }

    /// 정적 필드는 인스턴스에 없다. 섞어서 물으면 JVM 이 거절하고, 그러면 **필드가 하나도
    /// 안 보인다** — 하나 때문에 전부를 잃는다.
    @Test("정적 필드를 인스턴스 필드와 가른다")
    func separatesStaticFields() throws {
        var payload = bigEndian(UInt32(2))
        payload += identifier(11, size: 8) + string("instanceOne") + string("I") + bigEndian(UInt32(2))
        payload += identifier(12, size: 8) + string("STATIC_ONE") + string("I") + bigEndian(UInt32(0x0008 | 2))

        let fields = try JDWPField.parseList(payload: payload, fieldIDSize: 8)
        #expect(fields.filter { !$0.isStatic }.map(\.name) == ["instanceOne"])
        #expect(fields.filter(\.isStatic).map(\.name) == ["STATIC_ONE"])
    }

    @Test("GetValues 요청이 객체 id 와 필드 목록을 싣는다")
    func buildsTheGetValuesPayload() throws {
        let payload = JDWPObjectFields.getValuesPayload(
            objectID: 0x77, fieldIDs: [11, 12], objectIDSize: 8, fieldIDSize: 8
        )
        var reader = JDWPReader(bytes: payload)
        #expect(try reader.readIdentifier(size: 8) == 0x77)
        #expect(try reader.readInt32() == 2)
        #expect(try reader.readIdentifier(size: 8) == 11)
        #expect(try reader.readIdentifier(size: 8) == 12)
        #expect(reader.remaining == 0)
    }

    /// 값은 태그가 붙어 온다 — 폭이 태그마다 다르다. 고정 폭으로 읽으면 두 번째 필드부터
    /// 전부 밀린다.
    @Test("GetValues 응답을 태그대로 읽는다")
    func readsTaggedValues() throws {
        var payload = bigEndian(UInt32(3))
        payload += [UInt8(ascii: "I")] + bigEndian(UInt32(bitPattern: 42))
        payload += [UInt8(ascii: "Z"), 1]
        payload += [UInt8(ascii: "L")] + identifier(0x99, size: 8)

        var reader = JDWPReader(bytes: payload)
        let count = Int(try reader.readInt32())
        #expect(count == 3)
        #expect(try reader.readTaggedValue(objectIDSize: 8) == .int(42))
        #expect(try reader.readTaggedValue(objectIDSize: 8) == .boolean(true))
        #expect(try reader.readTaggedValue(objectIDSize: 8) == .object(tag: "L", id: 0x99))
        #expect(reader.remaining == 0)
    }

    /// 문자열은 id 만 와서는 쓸모가 없다 — 화면에 `String@7` 이 뜬다. 값을 따로 물어야 한다.
    @Test("문자열 값 요청은 객체 id 하나다")
    func buildsTheStringValuePayload() throws {
        let payload = JDWPObjectFields.stringValuePayload(objectID: 0x55, objectIDSize: 8)
        var reader = JDWPReader(bytes: payload)
        #expect(try reader.readIdentifier(size: 8) == 0x55)
        #expect(reader.remaining == 0)
    }

    private func bigEndian(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.bigEndian, Array.init) }
    private func identifier(_ value: UInt64, size: Int) -> [UInt8] {
        Array(withUnsafeBytes(of: value.bigEndian, Array.init).suffix(size))
    }
    private func string(_ text: String) -> [UInt8] { bigEndian(UInt32(text.utf8.count)) + Array(text.utf8) }
}
