import Foundation

/// 한 걸음의 깊이. **숫자가 직관과 반대다** — 안으로 들어가는 것이 0 이고 넘기는 것이 1 이다.
/// 바꿔 쓰면 "한 줄 넘기기" 가 함수 속으로 들어가는데, 그건 오류가 아니라 그냥 다른 데서
/// 멈춘 것으로 보인다.
enum JDWPStepDepth: Int32, Sendable, Hashable, CaseIterable {
    case into = 0
    case over = 1
    case out = 2
}

/// `EventRequest.Set` 의 SINGLE_STEP 페이로드.
///
/// 스텝은 브레이크포인트와 같은 기계로 만든다 — 이벤트 요청이다. 다만 **한 번 쓰고 지워야
/// 한다.** 안 지우면 매 줄 멈추고, 사용자는 "스텝을 한 번 눌렀는데 계속 멈춘다" 를 겪는다.
/// 그게 브레이크포인트 때문인지 스텝 때문인지 화면에서는 구별되지 않는다.
enum JDWPStepRequest {

    /// SINGLE_STEP. 브레이크포인트(2)와 다른 값이다.
    static let eventKind: UInt8 = 1
    /// Step modifier. 이 번호를 틀리면 JVM 이 다른 조건으로 읽는다.
    static let stepModifierKind: UInt8 = 10
    /// 줄 단위. 명령어 단위(`MIN` = -1)로 두면 한 줄 안에서 수십 번 멈춘다.
    static let lineStepSize: Int32 = 1
    /// 멈출 때 모든 스레드를 세운다 — 브레이크포인트와 같은 정책이라야 화면이 일관된다.
    static let suspendAll: UInt8 = 2

    static func payload(threadID: UInt64, depth: JDWPStepDepth, objectIDSize: Int) -> [UInt8] {
        var payload: [UInt8] = [eventKind, suspendAll]
        payload += bigEndian(UInt32(1))                    // 수식어 개수
        payload += [stepModifierKind]
        payload += identifierBytes(threadID, size: objectIDSize)
        payload += bigEndian(UInt32(bitPattern: lineStepSize))
        payload += bigEndian(UInt32(bitPattern: depth.rawValue))
        return payload
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian, Array.init)
    }

    private static func identifierBytes(_ value: UInt64, size: Int) -> [UInt8] {
        Array(withUnsafeBytes(of: value.bigEndian, Array.init).suffix(size))
    }
}
