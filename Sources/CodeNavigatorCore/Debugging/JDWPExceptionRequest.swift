import Foundation

/// An exception the JVM just threw.
struct JDWPThrownException: Sendable, Hashable {
    let requestID: Int32
    let threadID: UInt64
    /// 던진 자리.
    let classID: UInt64
    let methodID: UInt64
    let codeIndex: UInt64
    let exceptionObjectID: UInt64
    /// 잡히는 자리가 있으면 true. 없으면 이 예외로 스레드가 죽는다.
    let isCaught: Bool
}

/// `EventRequest.Set` 의 EXCEPTION.
///
/// 브레이크포인트를 어디에 걸어야 할지 모를 때 쓰는 것이라 디버깅에서 가장 자주 켜는 기능
/// 중 하나다. caught / uncaught 를 나눠 켤 수 있어야 하는데, 프레임워크가 예외를 잡아
/// 처리하는 코드에서 caught 를 켜면 **초당 수십 번 멈춘다** — 그러면 사용자는 디버거를 끈다.
enum JDWPExceptionRequest {

    static let eventKind: UInt8 = 4
    /// ExceptionOnly. 타입·caught·uncaught 를 한 수식어에 싣는다.
    static let exceptionOnlyModifier: UInt8 = 8
    static let suspendAll: UInt8 = 2

    /// - Parameter classID: 좁힐 예외 타입. `nil` 이면 모든 예외(프로토콜은 0 으로 쓴다).
    /// - Returns: 둘 다 끄면 `nil`. JVM 은 그런 요청도 받아들이고 **아무것도 보고하지
    ///   않는데**, 사용자에게는 "켰는데 안 멈춘다" 로 보이고 그건 고장과 구별되지 않는다.
    static func payload(
        classID: UInt64?, caught: Bool, uncaught: Bool, referenceTypeIDSize: Int
    ) -> [UInt8]? {
        guard caught || uncaught else { return nil }
        var payload: [UInt8] = [eventKind, suspendAll]
        payload += withUnsafeBytes(of: UInt32(1).bigEndian, Array.init)
        payload += [exceptionOnlyModifier]
        payload += identifierBytes(classID ?? 0, size: referenceTypeIDSize)
        payload += [caught ? 1 : 0, uncaught ? 1 : 0]
        return payload
    }

    /// Reads a composite event, returning the thrown exception or nil for any other kind.
    ///
    /// 예외 이벤트는 브레이크포인트와 달리 위치 **뒤에** 예외 객체와 잡히는 위치가 더 붙는다.
    /// 같은 모양으로 읽으면 그 뒤가 전부 어긋난다.
    static func parse(
        event: JDWPEvent, referenceTypeIDSize: Int, methodIDSize: Int, objectIDSize: Int
    ) throws -> JDWPThrownException? {
        guard event.commandSet == 64, event.command == 100 else { return nil }
        var reader = JDWPReader(bytes: event.payload)
        _ = try reader.readByte()
        let count = Int(try reader.readInt32())
        for _ in 0..<count {
            let kind = try reader.readByte()
            let requestID = try reader.readInt32()
            guard kind == eventKind else { return nil }

            let threadID = try reader.readIdentifier(size: objectIDSize)
            _ = try reader.readByte()   // 던진 위치의 typeTag
            let classID = try reader.readIdentifier(size: referenceTypeIDSize)
            let methodID = try reader.readIdentifier(size: methodIDSize)
            let codeIndex = try reader.readUInt64()

            let exception = try reader.readTaggedValue(objectIDSize: objectIDSize)
            guard case .object(_, let exceptionObjectID) = exception else { return nil }

            // 잡히는 위치. typeTag 0 이거나 클래스 id 가 0 이면 아무도 안 잡는다.
            let catchTag = try reader.readByte()
            let catchClassID = try reader.readIdentifier(size: referenceTypeIDSize)
            _ = try reader.readIdentifier(size: methodIDSize)
            _ = try reader.readUInt64()

            return JDWPThrownException(
                requestID: requestID,
                threadID: threadID,
                classID: classID,
                methodID: methodID,
                codeIndex: codeIndex,
                exceptionObjectID: exceptionObjectID,
                isCaught: catchTag != 0 && catchClassID != 0
            )
        }
        return nil
    }

    private static func identifierBytes(_ value: UInt64, size: Int) -> [UInt8] {
        Array(withUnsafeBytes(of: value.bigEndian, Array.init).suffix(size))
    }
}
