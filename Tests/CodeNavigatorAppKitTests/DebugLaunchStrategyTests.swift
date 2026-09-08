import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 디버그 에이전트를 **어디에** 붙이느냐.
///
/// `JAVA_TOOL_OPTIONS` 하나로 다 되는 줄 알았는데 아니었다. 그 값은 모든 자식 JVM 이
/// 물려받아서, `./gradlew bootRun` 에 걸면 Gradle **런처** JVM 이 먼저 그것을 집어 포트를
/// 잡고 `suspend=y` 로 멈춘다 — 앱은 뜨지도 않는다. 실측으로 확인했다:
///
/// ```
/// $ JAVA_TOOL_OPTIONS="-agentlib:jdwp=...suspend=y,address=127.0.0.1:5099" ./gradlew --version
/// Listening for transport dt_socket at address: 5099     ← 런처가 멈췄다
/// ```
///
/// 그래서 붙이는 방법이 명령마다 달라야 한다.
@Suite("디버그 부착 전략")
struct DebugLaunchStrategyTests {

    private func configuration(
        command: String, strategy: DebugLaunchStrategy, environment: [String: String] = [:]
    ) -> RunConfiguration {
        RunConfiguration(
            name: "서버", command: command, workingDirectory: "",
            environment: environment, debugLaunch: strategy
        )
    }

    // MARK: java 를 직접 부르는 명령

    @Test("java 직접 실행은 JAVA_TOOL_OPTIONS 로 붙는다 — 명령은 그대로 둔다")
    func plainJavaUsesTheEnvironmentVariable() {
        let launch = configuration(command: "java -cp . Server", strategy: .javaToolOptions)
            .debugLaunch(port: 5005, inheriting: [:])
        #expect(launch.command == "java -cp . Server")
        #expect(launch.environment["JAVA_TOOL_OPTIONS"]?.contains("address=127.0.0.1:5005") == true)
        #expect(launch.environment["JAVA_TOOL_OPTIONS"]?.contains("suspend=y") == true)
    }

    @Test("이미 있는 JAVA_TOOL_OPTIONS 를 덮지 않고 뒤에 붙인다")
    func appendsRatherThanOverwrites() {
        let launch = configuration(
            command: "java -cp . Server", strategy: .javaToolOptions,
            environment: ["JAVA_TOOL_OPTIONS": "-Xmx512m"]
        ).debugLaunch(port: 5005, inheriting: [:])
        let value = launch.environment["JAVA_TOOL_OPTIONS"] ?? ""
        #expect(value.hasPrefix("-Xmx512m "), "사용자가 넣은 -Xmx 가 사라졌다")
        #expect(value.contains("-agentlib:jdwp="))
    }

    // MARK: Gradle

    /// Gradle 은 자기가 포크한 JVM 에만 붙여 준다. 런처는 건드리지 않는다.
    @Test("Gradle 은 명령에 --debug-jvm 을 붙이고 환경변수는 건드리지 않는다")
    func gradleUsesItsOwnFlag() {
        let launch = configuration(command: "./gradlew bootRun", strategy: .gradleDebugJvm)
            .debugLaunch(port: 5005, inheriting: [:])
        #expect(launch.command.contains("--debug-jvm"))
        #expect(
            launch.environment["JAVA_TOOL_OPTIONS"] == nil,
            "런처가 이걸 물려받아 포트를 가로챈다 — 실측된 결함이다"
        )
    }

    /// Gradle 은 포트를 **못 바꾼다.** 실측(Gradle 8.14.5): `--debug-jvm` 에
    /// `-Dorg.gradle.debug.port=6001` 을 같이 줘도 앱 JVM 은 `address=5005` 로 떴다.
    /// 그 옵션은 `org.gradle.debug`(Gradle 자신을 디버깅) 쪽 것이지 태스크 쪽이 아니다.
    ///
    /// 그래서 우리가 요청한 포트가 아니라 **실제로 열릴 포트**를 답해야 한다. 안 그러면
    /// 6001 로 붙으러 가고 앱은 5005 에서 기다린다 — 화면에는 "붙지 못했습니다" 만 뜬다.
    @Test("Gradle 은 5005 로 고정되고, 그 사실을 알려 준다")
    func gradlePinsThePort() {
        let launch = configuration(command: "./gradlew bootRun", strategy: .gradleDebugJvm)
            .debugLaunch(port: 6001, inheriting: [:])
        #expect(launch.port == 5005, "Gradle 이 실제로 여는 포트를 답해야 한다")
        #expect(
            !launch.command.contains("org.gradle.debug.port"),
            "먹지 않는 옵션을 붙이면 있지도 않은 조절 수단이 있는 것처럼 보인다"
        )
        #expect(launch.command == "./gradlew bootRun --debug-jvm")
    }

    @Test("Gradle 말고는 요청한 포트를 그대로 쓴다")
    func othersHonourTheRequestedPort() {
        #expect(
            configuration(command: "java -cp . S", strategy: .javaToolOptions)
                .debugLaunch(port: 6001, inheriting: [:]).port == 6001
        )
        #expect(
            configuration(command: "./mvnw spring-boot:run", strategy: .mavenJvmArguments)
                .debugLaunch(port: 6001, inheriting: [:]).port == 6001
        )
    }

    // MARK: Maven

    @Test("Maven 은 spring-boot.run.jvmArguments 로 넘긴다")
    func mavenPassesJvmArguments() {
        let launch = configuration(command: "./mvnw spring-boot:run", strategy: .mavenJvmArguments)
            .debugLaunch(port: 5005, inheriting: [:])
        #expect(launch.command.contains("-Dspring-boot.run.jvmArguments="))
        #expect(launch.command.contains("address=127.0.0.1:5005"))
        #expect(launch.environment["JAVA_TOOL_OPTIONS"] == nil)
    }

    // MARK: 못 붙는 명령

    /// Node·Python 은 JDWP 를 안 쓴다. 조용히 아무 일도 안 하면 사용자는 "붙는 중" 으로
    /// 읽고 30초를 기다린 뒤 알 수 없는 실패를 본다.
    @Test("붙을 수 없는 명령은 그렇다고 답한다")
    func unsupportedSaysSo() {
        // 지역 변수가 헬퍼 이름을 가리지 않게 다르게 부른다.
        let node = configuration(command: "npm run dev", strategy: .unsupported)
        #expect(node.canDebug == false)
        #expect(configuration(command: "java -cp . S", strategy: .javaToolOptions).canDebug)
        #expect(configuration(command: "./gradlew bootRun", strategy: .gradleDebugJvm).canDebug)
    }

    // MARK: 저장 형식 호환

    /// v0.5.0 이 저장한 설정에는 이 항목이 없다. 없으면 못 읽는다고 하면 사용자의 설정이
    /// 통째로 사라진다 — 읽기 실패는 빈 목록으로 처리되기 때문이다.
    @Test("전략이 없는 옛 설정도 읽힌다")
    func decodesConfigurationsSavedBeforeThisField() throws {
        let legacy = """
        [{"name":"서버","command":"java -cp . Server","workingDirectory":"","environment":{"PORT":"8080"}}]
        """
        let decoded = try JSONDecoder().decode([RunConfiguration].self, from: Data(legacy.utf8))
        #expect(decoded.count == 1)
        #expect(decoded[0].command == "java -cp . Server")
        #expect(decoded[0].environment == ["PORT": "8080"])
        // 옛 설정은 전부 JAVA_TOOL_OPTIONS 로 돌았으니 그 뜻을 유지한다.
        #expect(decoded[0].debugLaunch == .javaToolOptions)
    }
}
