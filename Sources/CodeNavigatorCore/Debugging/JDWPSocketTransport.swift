import Foundation

/// A blocking TCP socket, wrapped so the protocol layer can await it.
///
/// Written on POSIX sockets rather than `Network.framework` for one reason: JDWP needs
/// **exactly N bytes** at a time, and a framing layer that has to cope with half a header cannot
/// be reasoned about. `read(2)` in a loop gives that directly.
///
/// The blocking calls run off the cooperative pool, because blocking one of its threads on a
/// socket that is waiting for a breakpoint would stall unrelated work for as long as the user
/// takes to press a key.
final class JDWPSocketTransport: JDWPTransport, @unchecked Sendable {
    private let descriptor: Int32
    /// 읽기와 쓰기가 **다른 큐**를 쓴다. 소켓은 전이중인데 한 직렬 큐에 묶으면 반이중이 된다 —
    /// 이벤트를 기다리며 막혀 있는 읽기 뒤로 모든 쓰기가 줄을 서고, 그러면 디버거가 이벤트를
    /// 기다리기 시작한 순간부터 명령이 **전송조차 되지 않는다**. 라이브에서 실제로 그랬고,
    /// 증상은 "브레이크포인트를 걸었는데 아무 일도 안 일어남" 이었다 — 오류도 로그도 없이.
    private let readQueue = DispatchQueue(label: "jdwp.socket.read")
    private let writeQueue = DispatchQueue(label: "jdwp.socket.write")

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    /// Connects to a JVM started with `-agentlib:jdwp=…,server=y`.
    ///
    /// **포트가 열려 있는지 미리 확인하지 마라.** `server=y` 는 연결을 하나만 받는다. 살아
    /// 있는지 보려고 `nc -z` 로 붙으면 그 연결이 디버거의 자리를 가져가고, 정작 우리가 붙을
    /// 때는 아무도 없다. 실제로 그렇게 한 번 막혔다.
    static func connect(host: String, port: UInt16) throws -> JDWPSocketTransport {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw JDWPConnectionError.connectFailed("소켓을 열지 못했습니다")
        }
        // `Darwin.` 을 붙인다 — 이 타입에도 `close` 가 있어서 이름이 가려진다.

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            Darwin.close(descriptor)
            throw JDWPConnectionError.connectFailed("주소를 해석하지 못했습니다: \(host)")
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            let reason = String(cString: strerror(errno))
            Darwin.close(descriptor)
            throw JDWPConnectionError.connectFailed(
                "\(host):\(port) 에 연결하지 못했습니다 — \(reason). JVM 이 -agentlib:jdwp 로 떠 있는지 확인하세요."
            )
        }
        return JDWPSocketTransport(descriptor: descriptor)
    }

    func send(_ bytes: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            writeQueue.async { [descriptor] in
                var remaining = bytes[...]
                while !remaining.isEmpty {
                    let written = remaining.withUnsafeBytes { buffer in
                        write(descriptor, buffer.baseAddress, buffer.count)
                    }
                    guard written > 0 else {
                        continuation.resume(throwing: JDWPConnectionError.connectionClosed)
                        return
                    }
                    remaining = remaining.dropFirst(written)
                }
                continuation.resume()
            }
        }
    }

    func receive(count: Int) async throws -> [UInt8] {
        guard count > 0 else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            readQueue.async { [descriptor] in
                var buffer = [UInt8](repeating: 0, count: count)
                var filled = 0
                while filled < count {
                    let read = buffer.withUnsafeMutableBytes { pointer in
                        Darwin.read(descriptor, pointer.baseAddress!.advanced(by: filled), count - filled)
                    }
                    // 0 은 상대가 닫았다는 뜻이고, 음수는 오류다. 둘 다 **부분 버퍼를
                    // 돌려주면 안 된다** — 0 으로 채워진 나머지가 유효한 값처럼 파싱된다.
                    guard read > 0 else {
                        continuation.resume(throwing: JDWPConnectionError.connectionClosed)
                        return
                    }
                    filled += read
                }
                continuation.resume(returning: buffer)
            }
        }
    }

    func close() async {
        // 읽기 큐는 소켓 대기로 막혀 있을 수 있으므로 그쪽에서 닫으려 하면 영영 못 닫는다.
        // 서술자를 닫으면 막혀 있던 `read` 가 0 으로 풀린다.
        Darwin.close(descriptor)
    }
}
