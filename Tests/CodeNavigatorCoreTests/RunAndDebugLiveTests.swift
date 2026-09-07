import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// 실행 설정 하나가 **끝까지** 이어지는지 진짜 JVM 으로 확인한다 —
/// 설정 → 터미널 기동 → 환경변수 전달 → JDWP 자동 부착 → 브레이크포인트.
///
/// 단위 테스트는 각 조각이 맞는지만 답한다. `JAVA_TOOL_OPTIONS` 가 실제로 자식 JVM 에
/// 닿는지, `termopen` 이 명령을 정말 돌리는지는 프로세스를 띄워야만 답이 나온다 — 이 앱에서
/// "테스트는 초록인데 기능이 죽어 있다" 가 반복적으로 난 자리가 정확히 여기다.
@Suite("실행·디버그 라이브", .serialized)
struct RunAndDebugLiveTests {

    /// 이 스위트가 쓰는 포트. 기본 5005 를 피한다 — 사용자가 자기 JVM 을 붙여 둔 채
    /// 테스트를 돌리면 남의 프로세스에 브레이크포인트를 건다.
    private static let debugPort: UInt16 = 5099

    @Test(
        "설정대로 터미널에서 돌고, 환경변수가 닿고, 디버거가 자동으로 붙는다",
        // 자바가 없는 기계에서는 러너가 **건너뜀으로 표시**하게 한다. 본문에서 조용히
        // `return` 하면 통과로 찍히고, 그건 "검증했다" 는 거짓말이 된다.
        .enabled(if: JavaToolchain.locate() != nil, "javac 가 없어 실행·디버그 라이브를 검증할 수 없다"),
        .timeLimit(.minutes(2))
    )
    func runsThenAttaches() async throws {
        let toolchain = try #require(JavaToolchain.locate())
        // 이 포트에 누가 이미 붙어 있으면 우리가 띄운 것이 아니라 **남의 JVM** 에 붙어서
        // 통과할 수 있다. 그건 통과가 아니라 이 테스트가 아무것도 검증하지 않았다는 뜻이다.
        try #require(
            !PortProbe.isListening(port: Self.debugPort),
            "\(Self.debugPort) 번을 이미 누가 잡고 있다 — 앞선 실행이 JVM 을 흘렸거나 다른 프로세스가 쓰는 중이다"
        )
        let root = try toolchain.compileProbeServer()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let configuration = RunConfiguration(
            name: "서버",
            command: "\(toolchain.javaPath) -cp . Server",
            workingDirectory: "",
            environment: ["PORT": "8080", "APP_ENV": "smoke"]
        )
        let environment = configuration.mergedEnvironment(
            inheriting: ProcessInfo.processInfo.environment, debugPort: Self.debugPort
        )

        let session = NeovimTerminalSession()
        let screen = ScreenCollector()
        let collecting = Task {
            for await snapshot in await session.gridUpdates() {
                await screen.append(snapshot.lines.map(\.plainText).joined(separator: "\n"))
            }
        }
        defer { collecting.cancel() }

        do {
            try await runAndAttach(session: session, configuration: configuration,
                                   environment: environment, root: root, screen: screen)
        } catch {
            // 실패해도 반드시 내린다. 안 내리면 JVM 이 포트를 잡은 채 남아 **다음 실행이
            // 그 프로세스에 붙어서** 통과한다.
            await session.stop()
            throw error
        }
        await session.stop()
    }

    private func runAndAttach(
        session: NeovimTerminalSession,
        configuration: RunConfiguration,
        environment: [String: String],
        root: String,
        screen: ScreenCollector
    ) async throws {
        try await session.start(
            command: configuration.command,
            workingDirectory: configuration.resolvedWorkingDirectory(projectRoot: root),
            environment: environment,
            columns: 100, rows: 24
        )

        // `suspend=y` 라 JVM 은 우리가 붙을 때까지 멈춰 있다. 포트가 열릴 때까지 기다린다 —
        // 바로 붙으면 "연결 거부" 가 나는데, 그건 우리가 빨랐다는 뜻이지 설정이 틀렸다는
        // 뜻이 아니다.
        var attached: JavaDebugSession?
        for _ in 0..<60 where attached == nil {
            attached = try? await JavaDebugSession.attach(host: "127.0.0.1", port: Self.debugPort)
            if attached == nil {
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        let debugSession = try #require(
            attached,
            "JDWP 로 못 붙었다 — 실행이 에이전트 인자를 안 실었거나 터미널이 명령을 안 돌렸다"
        )

        let requestID = try await debugSession.setBreakpoint(className: "Server", line: 8)
        try await debugSession.resume()
        let stop = try await debugSession.waitForBreakpoint()
        let frames = try await debugSession.stackFrames(threadID: stop.threadID)
        let top = try #require(frames.first, "멈췄는데 스택이 비었다")
        #expect(top.className == "Server")
        #expect(top.line == 8, "멈춘 줄이 건 줄과 다르다")

        try await debugSession.clearBreakpoint(requestID: requestID)
        try await debugSession.resume()
        await debugSession.close()

        // 환경변수가 자식 프로세스까지 닿았는지는 화면에 찍힌 글자로만 증명된다 — 우리가
        // 만든 사전을 다시 읽는 것은 아무것도 증명하지 않는다.
        var text = ""
        for _ in 0..<40 {
            text = await screen.text
            if text.contains("PORT=8080"), text.contains("APP_ENV=smoke") { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        #expect(text.contains("PORT=8080"), "화면에 PORT=8080 이 없다. 본 것:\n\(String(text.suffix(400)))")
        #expect(text.contains("APP_ENV=smoke"), "화면에 APP_ENV=smoke 가 없다")
    }
}


/// 그리드 갱신을 모은다. 터미널은 화면 전체를 다시 그리므로, 지나간 줄을 붙잡으려면
/// 모든 스냅샷을 쌓아 둬야 한다.
private actor ScreenCollector {
    private(set) var text = ""
    func append(_ chunk: String) {
        text += chunk + "\n"
    }
}

/// 테스트용 JDK. 없으면 nil — 이 기계에 자바가 없을 수 있고, 그때는 조용히 실패하는 대신
/// 건너뛴 것을 말해야 한다.
struct JavaToolchain {
    let javacPath: String
    let javaPath: String

    static func locate() -> JavaToolchain? {
        guard let javac = which("javac"), let java = which("java") else { return nil }
        return JavaToolchain(javacPath: javac, javaPath: java)
    }

    private static func which(_ tool: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", tool]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// 환경변수를 찍고 한동안 도는 서버 흉내. 8번째 줄이 브레이크포인트 자리다.
    func compileProbeServer() throws -> String {
        let root = NSTemporaryDirectory() + "code-navigator-run-live-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        let source = """
        public class Server {
            static int tick = 0;
            public static void main(String[] args) throws Exception {
                System.out.println("PORT=" + System.getenv("PORT"));
                System.out.println("APP_ENV=" + System.getenv("APP_ENV"));
                for (int i = 0; i < 600; i++) {
                    tick = i;
                    Thread.sleep(100);
                }
            }
        }
        """
        try source.write(toFile: root + "/Server.java", atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: javacPath)
        // `-g` 없이는 LineTable·VariableTable 이 비어서 브레이크포인트를 걸 자리가 없다.
        process.arguments = ["-g", "-d", root, root + "/Server.java"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "RunAndDebugLive", code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "javac 실패"]
            )
        }
        return root
    }
}

/// 포트가 비었는지 본다. 붙어 보는 것으로 재는 이유는 `lsof` 를 부르면 그 도구의 유무·권한이
/// 판정에 섞이기 때문이다 — 여기서 알고 싶은 건 "지금 이 포트로 붙을 수 있는가" 하나다.
enum PortProbe {
    static func isListening(port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connected == 0
    }
}
