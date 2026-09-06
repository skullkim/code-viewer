import Foundation

/// 필드가 읽히거나 바뀐 순간.
struct JDWPFieldEvent: Sendable, Hashable {
    let requestID: Int32
    let threadID: UInt64
    /// 그 일이 일어난 코드 위치.
    let classID: UInt64
    let methodID: UInt64
    let codeIndex: UInt64
    let fieldID: UInt64
    let objectID: UInt64
    /// 쓰기일 때만 있다. 읽기 이벤트에는 값이 안 온다.
    let newValue: JDWPValue?
}

/// `EventRequest.Set` 의 FIELD_ACCESS / FIELD_MODIFICATION.
///
/// "이 필드가 언제 바뀌는지 알고 싶다" 에 답한다. 값이 이상해졌는데 어디서 바뀌었는지 모를
/// 때, 브레이크포인트를 하나씩 걸어 가며 찾는 대신 JVM 에게 물어보는 것이다.
enum JDWPWatchpointRequest {

    enum Kind: UInt8, Sendable, Hashable {
        /// 읽힐 때. getter 한 번에도 멈추므로 대개 원하는 것은 아니다.
        case access = 20
        /// 바뀔 때. 새 값을 함께 준다.
        case modification = 21
    }

    /// FieldOnly. 이 번호를 틀리면 JVM 이 다른 조건으로 읽는다.
    static let fieldOnlyModifier: UInt8 = 9
    static let suspendAll: UInt8 = 2

    static func payload(
        kind: Kind, classID: UInt64, fieldID: UInt64, referenceTypeIDSize: Int, fieldIDSize: Int
    ) -> [UInt8] {
        var payload: [UInt8] = [kind.rawValue, suspendAll]
        payload += withUnsafeBytes(of: UInt32(1).bigEndian, Array.init)
        payload += [fieldOnlyModifier]
        payload += identifierBytes(classID, size: referenceTypeIDSize)
        payload += identifierBytes(fieldID, size: fieldIDSize)
        return payload
    }

    static func parse(
        event: JDWPEvent,
        referenceTypeIDSize: Int, methodIDSize: Int, objectIDSize: Int, fieldIDSize: Int
    ) throws -> JDWPFieldEvent? {
        guard event.commandSet == 64, event.command == 100 else { return nil }
        var reader = JDWPReader(bytes: event.payload)
        _ = try reader.readByte()
        let count = Int(try reader.readInt32())
        for _ in 0..<count {
            let rawKind = try reader.readByte()
            let requestID = try reader.readInt32()
            guard let kind = Kind(rawValue: rawKind) else { return nil }

            let threadID = try reader.readIdentifier(size: objectIDSize)
            _ = try reader.readByte()   // 위치 typeTag
            let classID = try reader.readIdentifier(size: referenceTypeIDSize)
            let methodID = try reader.readIdentifier(size: methodIDSize)
            let codeIndex = try reader.readUInt64()

            _ = try reader.readByte()   // 필드가 속한 타입의 refTypeTag
            _ = try reader.readIdentifier(size: referenceTypeIDSize)
            let fieldID = try reader.readIdentifier(size: fieldIDSize)
            let object = try reader.readTaggedValue(objectIDSize: objectIDSize)
            let objectID: UInt64
            if case .object(_, let id) = object { objectID = id } else { objectID = 0 }

            // **쓰기일 때만 값이 온다.** 읽기 이벤트에서 값을 읽으려 하면 그 뒤가 어긋난다.
            let newValue = kind == .modification
                ? try reader.readTaggedValue(objectIDSize: objectIDSize)
                : nil

            return JDWPFieldEvent(
                requestID: requestID, threadID: threadID,
                classID: classID, methodID: methodID, codeIndex: codeIndex,
                fieldID: fieldID, objectID: objectID, newValue: newValue
            )
        }
        return nil
    }

    private static func identifierBytes(_ value: UInt64, size: Int) -> [UInt8] {
        Array(withUnsafeBytes(of: value.bigEndian, Array.init).suffix(size))
    }
}
