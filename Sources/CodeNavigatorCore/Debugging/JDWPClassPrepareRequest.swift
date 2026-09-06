import Foundation

/// A class the JVM has just finished loading.
struct JDWPPreparedClass: Sendable, Hashable {
    let requestID: Int32
    let threadID: UInt64
    let classID: UInt64
    /// 점 표기. `Lcom/example/Thing;` 이 아니라 `com.example.Thing`.
    let className: String
}

/// `EventRequest.Set` 의 CLASS_PREPARE.
///
/// 아직 로드되지 않은 클래스에 브레이크포인트를 걸기 위한 것이다. 이게 없으면 `suspend=y` 로
/// 띄운 JVM — **처음부터 디버깅하려는 경우** — 에서 아무 데도 못 건다. 그 JVM 은 우리 클래스를
/// 아직 로드하지 않았고, `ClassesBySignature` 는 정상적으로 0건을 답한다. 0건을 "그런 클래스
/// 없음" 으로 읽으면 브레이크포인트가 조용히 사라지고, 그건 "아직 그 줄을 안 지났다" 와
/// 화면에서 구별되지 않는다.
enum JDWPClassPrepareRequest {

    static let eventKind: UInt8 = 8
    /// 클래스 이름으로 좁힌다. 안 좁히면 JVM 이 **모든** 클래스 로드를 보고한다 — 수천 개다.
    static let classMatchModifier: UInt8 = 5
    /// 로드 직후 멈춰야 브레이크포인트를 걸 수 있다. 안 멈추면 그 사이에 이미 지나간다.
    static let suspendAll: UInt8 = 2

    static func payload(className: String) -> [UInt8] {
        var payload: [UInt8] = [eventKind, suspendAll]
        payload += bigEndian(UInt32(1))
        payload += [classMatchModifier]
        payload += bigEndian(UInt32(className.utf8.count))
        payload += Array(className.utf8)
        return payload
    }

    /// Reads a composite event, returning the prepared class or nil for any other event kind.
    static func parse(
        event: JDWPEvent, referenceTypeIDSize: Int, objectIDSize: Int
    ) throws -> JDWPPreparedClass? {
        guard event.commandSet == 64, event.command == 100 else { return nil }
        var reader = JDWPReader(bytes: event.payload)
        _ = try reader.readByte()   // suspend policy
        let count = Int(try reader.readInt32())
        for _ in 0..<count {
            let kind = try reader.readByte()
            let requestID = try reader.readInt32()
            // 다른 종류면 **이어서 읽지 않는다.** 페이로드 모양이 달라서 그 뒤가 전부
            // 쓰레기가 된다.
            guard kind == eventKind else { return nil }
            let threadID = try reader.readIdentifier(size: objectIDSize)
            _ = try reader.readByte()   // refTypeTag
            let classID = try reader.readIdentifier(size: referenceTypeIDSize)
            let signature = try reader.readString()
            _ = try reader.readInt32()  // status
            return JDWPPreparedClass(
                requestID: requestID,
                threadID: threadID,
                classID: classID,
                className: className(fromSignature: signature)
            )
        }
        return nil
    }

    /// `Lcom/example/Thing;` → `com.example.Thing`.
    ///
    /// 중첩 클래스의 `$` 는 그대로 둔다 — 우리가 건 이름과 비교만 하면 되고, 바꾸면 오히려
    /// `Outer.Inner` 와 `Outer$Inner` 중 어느 쪽이 맞는지가 매번 문제가 된다.
    static func className(fromSignature signature: String) -> String {
        signature
            .trimmingCharacters(in: CharacterSet(charactersIn: "L;"))
            .replacingOccurrences(of: "/", with: ".")
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian, Array.init)
    }
}
