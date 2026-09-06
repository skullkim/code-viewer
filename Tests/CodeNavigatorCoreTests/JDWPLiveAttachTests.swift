import Testing
import Foundation
@testable import CodeNavigatorCore

/// 실제 JVM 에 붙는다. 가짜 소켓으로 재는 프레이밍과, 진짜 JVM 이 보내는 바이트는 다르다 —
/// 스파이크에서 틀린 것 셋(ID 폭 가변·Methods 문자열 개수·suspend 시 클래스 미로드)은 전부
/// 여기서만 드러났다.
///
/// 디버기가 없으면 조용히 건너뛴다. 없는 것을 실패로 적으면 게이트가 늘 빨간불이고, 빨간불은
/// 곧 무시된다. 다만 **건너뛰었다는 사실은 출력한다** — 안 그러면 통과와 구별되지 않는다.
@Suite("JDWP 라이브 접속", .serialized)
struct JDWPLiveAttachTests {

    private static var host: String { ProcessInfo.processInfo.environment["JDWP_HOST"] ?? "127.0.0.1" }
    private static var port: UInt16 {
        UInt16(ProcessInfo.processInfo.environment["JDWP_PORT"] ?? "") ?? 5005
    }
    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["JDWP_LIVE"] == "1"
    }

    private func connect() async throws -> JDWPConnection? {
        guard Self.isEnabled else {
            print("SKIP: JDWP_LIVE=1 이 아니라 라이브 접속을 건너뛴다")
            return nil
        }
        let transport = try JDWPSocketTransport.connect(host: Self.host, port: Self.port)
        let connection = JDWPConnection(transport: transport)
        try await connection.handshake()
        return connection
    }

    @Test("붙어서 ID 폭을 읽는다")
    func attachesAndReadsIdentifierSizes() async throws {
        guard let connection = try await connect() else { return }
        defer { Task { await connection.close() } }

        let sizes = try await connection.readIdentifierSizes()
        print("LIVE sizes method=\(sizes.methodID) refType=\(sizes.referenceTypeID) frame=\(sizes.frameID)")
        // 값은 JVM 마다 다를 수 있다. 고정값이 아니라 **쓸 수 있는 값인지**를 본다.
        for size in [sizes.fieldID, sizes.methodID, sizes.objectID, sizes.referenceTypeID, sizes.frameID] {
            #expect([2, 4, 8].contains(size), "읽을 수 없는 ID 폭이다: \(size)")
        }
    }

    @Test("버전을 물으면 답한다 — 왕복이 실제로 성립한다")
    func readsTheVirtualMachineVersion() async throws {
        guard let connection = try await connect() else { return }
        defer { Task { await connection.close() } }

        // VirtualMachine.Version (1, 1): description, jdwpMajor, jdwpMinor, vmVersion, vmName
        let payload = try await connection.request(commandSet: 1, command: 1, payload: [])
        var reader = JDWPReader(bytes: payload)
        let description = try reader.readString()
        let major = try reader.readInt32()
        _ = try reader.readInt32()
        let vmVersion = try reader.readString()
        let vmName = try reader.readString()
        print("LIVE vm=\(vmName) version=\(vmVersion) jdwp=\(major)")
        #expect(!description.isEmpty)
        #expect(major >= 1)
        #expect(!vmName.isEmpty)
        // 페이로드를 남김없이 읽었는지 본다. 남아 있으면 우리가 필드를 하나 빠뜨린 것이고,
        // 그건 다음 명령에서 조용히 어긋난다.
        #expect(reader.remaining == 0, "안 읽은 바이트가 \(reader.remaining) 남았다")
    }
}
