import Foundation

/// A field as `ReferenceType.Fields` reports it.
struct JDWPField: Sendable, Hashable {
    let id: UInt64
    let name: String
    let signature: String
    let modifiers: Int32

    /// `ACC_STATIC`. 정적 필드는 인스턴스에 없다 — 인스턴스 필드와 섞어서 물으면 JVM 이
    /// 거절하고, 그러면 **필드가 하나도 안 보인다.** 하나 때문에 전부를 잃는다.
    var isStatic: Bool { modifiers & 0x0008 != 0 }
}

extension JDWPField {
    /// `ReferenceType.Fields` (2, 4).
    ///
    /// 필드당 문자열은 **둘**이다 — 이름과 시그니처. `FieldsWithGeneric`(cmd 14)이 셋이다.
    /// `Methods` 에서 이미 한 번 당한 자리와 같은 모양이다.
    static func parseList(payload: [UInt8], fieldIDSize: Int) throws -> [JDWPField] {
        var reader = JDWPReader(bytes: payload)
        let count = Int(try reader.readInt32())
        var fields: [JDWPField] = []
        fields.reserveCapacity(count)
        for _ in 0..<count {
            let id = try reader.readIdentifier(size: fieldIDSize)
            let name = try reader.readString()
            let signature = try reader.readString()
            let modifiers = try reader.readInt32()
            fields.append(JDWPField(id: id, name: name, signature: signature, modifiers: modifiers))
        }
        return fields
    }
}

/// Payloads for reading what is inside an object.
///
/// 필드 목록은 **타입**에 딸리고 값은 **인스턴스**에 딸린다. 둘을 섞으면 다른 객체의 값을
/// 이 객체 것으로 보여 준다 — 그건 오류가 아니라 그냥 틀린 숫자다.
enum JDWPObjectFields {

    /// `ObjectReference.GetValues` (9, 2).
    static func getValuesPayload(
        objectID: UInt64, fieldIDs: [UInt64], objectIDSize: Int, fieldIDSize: Int
    ) -> [UInt8] {
        var payload = identifierBytes(objectID, size: objectIDSize)
        payload += withUnsafeBytes(of: UInt32(fieldIDs.count).bigEndian, Array.init)
        for fieldID in fieldIDs {
            payload += identifierBytes(fieldID, size: fieldIDSize)
        }
        return payload
    }

    /// `StringReference.Value` (10, 1).
    ///
    /// 문자열은 객체 id 로만 오면 화면에 `String@7` 이 뜬다. 사용자가 보고 싶은 것은 그
    /// 숫자가 아니라 내용이다.
    static func stringValuePayload(objectID: UInt64, objectIDSize: Int) -> [UInt8] {
        identifierBytes(objectID, size: objectIDSize)
    }

    /// `ArrayReference.Length` (13, 1) 와 `GetValues` (13, 2) 도 같은 모양으로 쓴다.
    static func arrayValuesPayload(
        arrayID: UInt64, firstIndex: Int32, length: Int32, objectIDSize: Int
    ) -> [UInt8] {
        var payload = identifierBytes(arrayID, size: objectIDSize)
        payload += withUnsafeBytes(of: firstIndex.bigEndian, Array.init)
        payload += withUnsafeBytes(of: length.bigEndian, Array.init)
        return payload
    }

    private static func identifierBytes(_ value: UInt64, size: Int) -> [UInt8] {
        Array(withUnsafeBytes(of: value.bigEndian, Array.init).suffix(size))
    }
}
