import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 실행 설정 — 무엇을, 어디서, 어떤 환경변수로 돌릴지.
///
/// 저장되는 것이라 **못 읽는 값이 앱을 못 열게 하면 안 된다.** 손으로 고친 설정 하나가
/// 창을 안 열리게 만드는 것은 설정이 할 수 있는 가장 나쁜 일이다.
@Suite("실행 설정")
@MainActor
struct RunConfigurationTests {

    @Test("저장하고 다시 읽으면 같다")
    func roundTrips() {
        let storage = InMemoryKeyValueStore()
        let configuration = RunConfiguration(
            name: "서버",
            command: "./gradlew bootRun",
            workingDirectory: "backend",
            environment: ["SPRING_PROFILES_ACTIVE": "local", "PORT": "8080"]
        )

        let writing = ShellPreferences(storage: storage)
        writing.runConfigurations = [configuration]

        let reading = ShellPreferences(storage: storage)
        #expect(reading.runConfigurations == [configuration])
    }

    @Test("처음에는 비어 있다 — 우리가 임의로 만들지 않는다")
    func startsEmpty() {
        #expect(ShellPreferences(storage: InMemoryKeyValueStore()).runConfigurations.isEmpty)
    }

    /// 손으로 고친 설정 하나가 창을 못 열게 하면 안 된다.
    @Test("손상된 설정은 빈 목록으로 읽는다")
    func survivesCorruptStorage() {
        let storage = InMemoryKeyValueStore()
        storage.setData(Data("이건 JSON 이 아니다".utf8), forKey: ShellPreferences.runConfigurationsKey)
        #expect(ShellPreferences(storage: storage).runConfigurations.isEmpty)
    }

    // MARK: 환경변수

    /// **환경변수는 물려받은 것 위에 얹는다.** 통째로 갈아 끼우면 `PATH` 가 사라져서
    /// `./gradlew` 도 `java` 도 못 찾는다 — 그리고 그 실패는 "명령을 못 찾음" 으로만 보인다.
    @Test("환경변수는 물려받은 것에 얹는다 — PATH 를 잃지 않는다")
    func layersOverTheInheritedEnvironment() {
        let merged = RunConfiguration(
            name: "x", command: "echo", workingDirectory: "",
            environment: ["MY_VAR": "1"]
        ).mergedEnvironment(inheriting: ["PATH": "/usr/bin", "HOME": "/Users/x"])

        #expect(merged["PATH"] == "/usr/bin")
        #expect(merged["HOME"] == "/Users/x")
        #expect(merged["MY_VAR"] == "1")
    }

    @Test("같은 이름이면 설정이 이긴다")
    func theConfigurationWins() {
        let merged = RunConfiguration(
            name: "x", command: "echo", workingDirectory: "",
            environment: ["PATH": "/custom"]
        ).mergedEnvironment(inheriting: ["PATH": "/usr/bin"])
        #expect(merged["PATH"] == "/custom")
    }

    // MARK: 작업 디렉터리

    @Test("작업 디렉터리는 프로젝트 루트 기준이다")
    func resolvesTheWorkingDirectory() {
        let configuration = RunConfiguration(
            name: "x", command: "echo", workingDirectory: "backend", environment: [:]
        )
        #expect(configuration.resolvedWorkingDirectory(projectRoot: "/p") == "/p/backend")
    }

    @Test("비어 있으면 프로젝트 루트다")
    func defaultsToTheProjectRoot() {
        let configuration = RunConfiguration(
            name: "x", command: "echo", workingDirectory: "", environment: [:]
        )
        #expect(configuration.resolvedWorkingDirectory(projectRoot: "/p") == "/p")
    }

    /// 절대 경로를 적었으면 그대로 쓴다 — 루트 아래로 억지로 밀어 넣으면 `/tmp/x` 가
    /// `/p/tmp/x` 가 된다.
    @Test("절대 경로는 그대로 쓴다")
    func keepsAnAbsolutePath() {
        let configuration = RunConfiguration(
            name: "x", command: "echo", workingDirectory: "/tmp/somewhere", environment: [:]
        )
        #expect(configuration.resolvedWorkingDirectory(projectRoot: "/p") == "/tmp/somewhere")
    }

    // MARK: 디버그 실행

    /// **명령을 고쳐 쓰지 않는다.** `-agentlib:jdwp=…` 를 어디에 넣을지는 명령마다 다르다
    /// (`java` 직접 · `./gradlew bootRun` · `mvn`). `JAVA_TOOL_OPTIONS` 는 JVM 이 표준으로
    /// 읽으므로 어떤 실행 방식이든 통한다.
    @Test("디버그 실행은 명령이 아니라 환경변수로 붙인다")
    func attachesTheAgentThroughTheEnvironment() {
        let configuration = RunConfiguration(
            name: "x", command: "./gradlew bootRun", workingDirectory: "", environment: [:]
        )
        let environment = configuration.mergedEnvironment(inheriting: [:], debugPort: 5005)

        let options = try? #require(environment["JAVA_TOOL_OPTIONS"])
        #expect(options?.contains("-agentlib:jdwp=") == true)
        #expect(options?.contains("address=127.0.0.1:5005") == true)
        #expect(options?.contains("server=y") == true)
        // `suspend=y` 여야 시작 전에 브레이크포인트를 걸 수 있다. 우리는 로드 전 클래스에도
        // 걸 수 있으므로 그 이점을 살린다.
        #expect(options?.contains("suspend=y") == true)
    }

    @Test("디버그가 아니면 에이전트를 안 붙인다")
    func leavesTheEnvironmentAloneWhenNotDebugging() {
        let environment = RunConfiguration(
            name: "x", command: "echo", workingDirectory: "", environment: [:]
        ).mergedEnvironment(inheriting: [:], debugPort: nil)
        #expect(environment["JAVA_TOOL_OPTIONS"] == nil)
    }

    /// 사용자가 이미 `JAVA_TOOL_OPTIONS` 를 적었으면 덮어쓰지 않고 **뒤에 붙인다.** 덮으면
    /// 사용자가 넣은 `-Xmx` 같은 것이 조용히 사라진다.
    @Test("이미 있는 JAVA_TOOL_OPTIONS 뒤에 붙인다")
    func appendsToExistingOptions() {
        let environment = RunConfiguration(
            name: "x", command: "echo", workingDirectory: "",
            environment: ["JAVA_TOOL_OPTIONS": "-Xmx512m"]
        ).mergedEnvironment(inheriting: [:], debugPort: 5005)

        #expect(environment["JAVA_TOOL_OPTIONS"]?.hasPrefix("-Xmx512m ") == true)
        #expect(environment["JAVA_TOOL_OPTIONS"]?.contains("-agentlib:jdwp=") == true)
    }
}
