import Foundation

/// 무엇을, 어디서, 어떤 환경변수로 돌릴지.
///
/// IntelliJ 의 Run Configuration 자리다. 서버를 띄우려면 명령 하나로는 모자란다 — 대개
/// 작업 디렉터리가 다르고, 프로파일이나 포트를 환경변수로 준다.
public struct RunConfiguration: Sendable, Hashable, Codable, Identifiable {
    public var name: String
    /// 셸에 그대로 넘길 명령. `./gradlew bootRun` 처럼 적는다.
    public var command: String
    /// 프로젝트 루트 기준 상대 경로. 비우면 루트.
    public var workingDirectory: String
    public var environment: [String: String]
    /// 디버그 실행일 때 에이전트를 어디에 붙일지. 명령마다 다르다 — `DebugLaunchStrategy`.
    public var debugLaunch: DebugLaunchStrategy

    public var id: String { name }

    /// 디버그 실행을 눌러도 되는지. 못 붙는 명령에서 버튼을 켜 두면 사용자는 30초를
    /// 기다린 뒤 "붙지 못했습니다" 만 본다.
    public var canDebug: Bool { debugLaunch != .unsupported }

    public init(
        name: String,
        command: String,
        workingDirectory: String,
        environment: [String: String],
        debugLaunch: DebugLaunchStrategy = .javaToolOptions
    ) {
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.debugLaunch = debugLaunch
    }

    /// v0.5.0 이 저장한 설정에는 `debugLaunch` 가 없다. 없다고 통째로 실패하면 사용자의
    /// 설정이 전부 사라진다 — 읽기 실패는 빈 목록으로 처리되기 때문이다. 그때의 뜻
    /// (`JAVA_TOOL_OPTIONS`) 을 그대로 이어 준다.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        environment = try container.decode([String: String].self, forKey: .environment)
        debugLaunch = try container.decodeIfPresent(
            DebugLaunchStrategy.self, forKey: .debugLaunch
        ) ?? .javaToolOptions
    }

    /// 어디서 돌릴지. 절대 경로를 적었으면 그대로 쓴다 — 루트 아래로 억지로 밀어 넣으면
    /// `/tmp/x` 가 `/p/tmp/x` 가 된다.
    public func resolvedWorkingDirectory(projectRoot: String) -> String {
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return projectRoot }
        if trimmed.hasPrefix("/") { return trimmed }
        return (projectRoot as NSString).appendingPathComponent(trimmed)
    }

    /// Gradle 이 `--debug-jvm` 에서 여는 포트. **바꿀 수 없다.**
    ///
    /// 실측(Gradle 8.14.5): `-Dorg.gradle.debug.port=6001` 을 같이 줘도 앱 JVM 은
    /// `address=5005` 로 떴다. 그 옵션은 Gradle 자신을 디버깅하는 쪽 것이지 태스크 쪽이
    /// 아니다.
    public static let gradleDebugPort: UInt16 = 5005

    /// 디버그로 띄울 때 실제로 쓸 명령·환경과, **실제로 열릴 포트**.
    ///
    /// 셋을 **함께** 돌려주는 이유는 어디에 넣을지가 전략마다 다르고, 포트마저 우리 뜻대로
    /// 안 되는 전략이 있기 때문이다. 따로 물으면 부르는 쪽이 짝을 맞춰야 하고, 하나라도
    /// 어긋나면 엉뚱한 포트로 붙으러 가서 "붙지 못했습니다" 로 끝난다.
    public func debugLaunch(
        port: UInt16, inheriting inherited: [String: String]
    ) -> (command: String, environment: [String: String], port: UInt16) {
        var environment = mergedEnvironment(inheriting: inherited)
        // Gradle 만 포트를 우리가 못 정한다. 나머지는 요청한 그대로다.
        let actualPort = debugLaunch == .gradleDebugJvm ? Self.gradleDebugPort : port
        // `suspend=y` 인 것은 시작 코드에 건 브레이크포인트를 놓치지 않기 위해서다.
        // 붙은 뒤 우리가 다시 풀어 준다.
        let agent = Self.agentArgument(port: actualPort)

        switch debugLaunch {
        case .javaToolOptions:
            // 덮어쓰지 않고 뒤에 붙인다. 덮으면 사용자가 넣은 `-Xmx` 같은 것이 사라진다.
            if let existing = environment[Self.javaToolOptionsKey], !existing.isEmpty {
                environment[Self.javaToolOptionsKey] = existing + " " + agent
            } else {
                environment[Self.javaToolOptionsKey] = agent
            }
            return (command, environment, actualPort)

        case .gradleDebugJvm:
            // 플래그 하나뿐이다. 포트 옵션은 붙여 봐야 먹지 않고, 먹지 않는 옵션을 붙이면
            // 있지도 않은 조절 수단이 있는 것처럼 보인다.
            return (command + " --debug-jvm", environment, actualPort)

        case .mavenJvmArguments:
            return (command + " -Dspring-boot.run.jvmArguments=\"\(agent)\"", environment, actualPort)

        case .unsupported:
            // 붙지 않는다. 부르는 쪽이 `canDebug` 를 먼저 봐야 하지만, 여기서도 에이전트를
            // 얹지 않는 것이 안전하다 — 얹으면 Node 프로세스가 알 수 없는 인자로 죽는다.
            return (command, environment, actualPort)
        }
    }

    static let javaToolOptionsKey = "JAVA_TOOL_OPTIONS"

    static func agentArgument(port: UInt16) -> String {
        "-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=127.0.0.1:\(port)"
    }

    /// 실제로 프로세스에 줄 환경.
    ///
    /// **물려받은 것 위에 얹는다.** 통째로 갈아 끼우면 `PATH` 가 사라져 `./gradlew` 도
    /// `java` 도 못 찾고, 그 실패는 "명령을 못 찾음" 으로만 보인다 — 환경변수 문제라는
    /// 단서가 화면 어디에도 없다.
    ///
    /// - Parameter debugPort: 디버그로 띄우면 그 포트. `nil` 이면 그냥 실행이다.
    public func mergedEnvironment(
        inheriting inherited: [String: String], debugPort: UInt16? = nil
    ) -> [String: String] {
        var merged = inherited
        for (key, value) in environment {
            merged[key] = value
        }
        guard let debugPort else { return merged }

        // **명령을 고쳐 쓰지 않는다.** `-agentlib:jdwp=…` 를 어디에 넣을지는 명령마다
        // 다르다 — `java` 는 클래스 이름 앞, `./gradlew bootRun` 은 아예 다른 자리,
        // `mvn` 은 또 다르다. `JAVA_TOOL_OPTIONS` 는 JVM 이 표준으로 읽으므로 어떤 실행
        // 방식이든 통한다.
        //
        // `suspend=y` 인 것은 우리가 로드 전 클래스에도 브레이크포인트를 걸 수 있기
        // 때문이다 — 시작 전에 걸어 두는 이점을 살린다.
        let agent = "-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=127.0.0.1:\(debugPort)"
        if let existing = merged["JAVA_TOOL_OPTIONS"], !existing.isEmpty {
            // 덮어쓰지 않고 뒤에 붙인다. 덮으면 사용자가 넣은 `-Xmx` 같은 것이 조용히 사라진다.
            merged["JAVA_TOOL_OPTIONS"] = existing + " " + agent
        } else {
            merged["JAVA_TOOL_OPTIONS"] = agent
        }
        return merged
    }
}
