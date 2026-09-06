import Foundation

/// `VirtualMachine.RedefineClasses` (1, 18) — 핫스왑.
///
/// 멈춘 채로 코드를 고쳐 다시 넣는다. 고칠 때마다 프로그램을 다시 띄우지 않아도 되는 것이
/// 요점이다.
///
/// **표준 JVM 은 본문만 바꿀 수 있다.** 메서드를 더하거나 지우거나 시그니처를 바꾸면 거절한다.
/// 그 거절을 그대로 사용자에게 보여야 한다 — "알 수 없는 오류" 로 뭉개면 사용자는 자기가
/// 뭘 잘못했는지 모른 채 디버거를 의심한다.
enum JDWPRedefineRequest {

    static func payload(
        classes: [(classID: UInt64, bytes: [UInt8])], referenceTypeIDSize: Int
    ) -> [UInt8] {
        var payload = withUnsafeBytes(of: UInt32(classes.count).bigEndian, Array.init)
        for entry in classes {
            payload += identifierBytes(entry.classID, size: referenceTypeIDSize)
            payload += withUnsafeBytes(of: UInt32(entry.bytes.count).bigEndian, Array.init)
            payload += entry.bytes
        }
        return payload
    }

    private static func identifierBytes(_ value: UInt64, size: Int) -> [UInt8] {
        Array(withUnsafeBytes(of: value.bigEndian, Array.init).suffix(size))
    }
}

/// `VirtualMachine.CapabilitiesNew` (1, 17) 에서 우리가 쓰는 것들.
///
/// 못 하는 것을 메뉴에 켜 두면 사용자는 눌러 보고 알 수 없는 오류를 본다. 스파이크에서 이미
/// 봤다 — 이 JVM 은 핫스왑을 허용하지만 drop frame 은 거절한다.
struct JDWPCapabilities: Sendable, Hashable {
    let canRedefineClasses: Bool
    let canPopFrames: Bool
    let canGetInstanceInfo: Bool

    /// 응답은 불리언이 줄줄이 오는 형태다. 자리마다 뜻이 정해져 있고, **한 칸만 밀려도
    /// 다른 능력을 읽는다.** 처음에 8/10/12 로 잡았더니 핫스왑 자리에서 `canAddMethod` 를
    /// 읽어 "이 JVM 은 핫스왑을 안 받는다" 로 결론 날 뻔했다 — 기능이 조용히 꺼지는 형태다.
    ///
    /// 규격 순서(0-based):
    ///   0 watchFieldModification · 1 watchFieldAccess · 2 getBytecodes ·
    ///   3 getSyntheticAttribute · 4 getOwnedMonitorInfo · 5 getCurrentContendedMonitor ·
    ///   6 getMonitorInfo · **7 redefineClasses** · 8 addMethod ·
    ///   9 unrestrictedlyRedefineClasses · **10 popFrames** · 11 useInstanceFilters ·
    ///   12 getSourceDebugExtension · 13 requestVMDeathEvent · 14 setDefaultStratum ·
    ///   **15 getInstanceInfo**
    static let canRedefineClassesIndex = 7
    static let canPopFramesIndex = 10
    static let canGetInstanceInfoIndex = 15
    /// `CapabilitiesNew` 는 32개를 준다. 그보다 짧으면 우리가 볼 자리가 없다.
    static let expectedCount = 32

    /// 짧은 응답은 **읽지 않는다.** 없는 자리를 0 으로 읽으면 "못 한다" 가 되고, 그러면
    /// 되는 JVM 에서도 기능이 조용히 꺼진다.
    init(payload: [UInt8]) throws {
        guard payload.count >= Self.expectedCount else {
            throw JDWPReadError.outOfBounds(needed: Self.expectedCount, remaining: payload.count)
        }
        self.canRedefineClasses = payload[Self.canRedefineClassesIndex] != 0
        self.canPopFrames = payload[Self.canPopFramesIndex] != 0
        self.canGetInstanceInfo = payload[Self.canGetInstanceInfoIndex] != 0
    }
}
