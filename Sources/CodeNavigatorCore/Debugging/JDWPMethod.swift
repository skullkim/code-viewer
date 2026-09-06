import Foundation

/// A method as `ReferenceType.Methods` reports it.
struct JDWPMethod: Sendable, Hashable {
    let id: UInt64
    let name: String
    let signature: String
    let modifiers: Int32
}

extension JDWPMethod {
    /// Parses the reply to `ReferenceType.Methods` (command set 2, command 5).
    ///
    /// **메서드당 문자열은 둘이다** — 이름과 시그니처. 셋으로 읽으면(그건 `MethodsWithGeneric`,
    /// command 15 다) 다음 메서드의 ID 를 문자열 길이로 해석하고, 그 길이는 보통 거대한 수라
    /// 그 자리에서 죽는다. 스파이크가 실제로 이렇게 크래시했다.
    static func parseList(payload: [UInt8], methodIDSize: Int) throws -> [JDWPMethod] {
        var reader = JDWPReader(bytes: payload)
        let count = Int(try reader.readUInt32())
        var methods: [JDWPMethod] = []
        methods.reserveCapacity(count)
        for _ in 0..<count {
            let id = try reader.readIdentifier(size: methodIDSize)
            let name = try reader.readString()
            let signature = try reader.readString()
            let modifiers = try reader.readInt32()
            methods.append(JDWPMethod(id: id, name: name, signature: signature, modifiers: modifiers))
        }
        return methods
    }
}
