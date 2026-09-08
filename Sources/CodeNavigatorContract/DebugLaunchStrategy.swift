/// 디버그 에이전트를 **어디에** 붙일지.
///
/// 하나로 다 될 줄 알았는데 아니었다. `JAVA_TOOL_OPTIONS` 는 모든 자식 JVM 이 물려받는다.
/// `./gradlew bootRun` 에 걸면 Gradle **런처** JVM 이 먼저 그것을 집어 포트를 잡고
/// `suspend=y` 로 멈춰 버린다 — 앱은 뜨지도 않고, 우리는 앱이 아니라 런처에 붙는다.
///
/// 그래서 붙이는 자리를 명령이 아니라 **설정이 들고 있게** 한다. 매번 명령 문자열을 다시
/// 뜯어 추측하면, 사용자가 명령을 조금 고칠 때마다 붙는 방식이 소리 없이 바뀐다.
public enum DebugLaunchStrategy: String, Sendable, Hashable, Codable, CaseIterable {

    /// JVM 이 표준으로 읽는 환경변수. `java` 를 직접 부르는 명령에만 안전하다.
    case javaToolOptions

    /// Gradle 이 **자기가 포크한** JVM 에만 에이전트를 붙여 준다. 런처는 건드리지 않는다.
    case gradleDebugJvm

    /// Spring Boot Maven 플러그인이 포크된 JVM 에 인자를 넘긴다.
    case mavenJvmArguments

    /// JDWP 로 붙을 수 없는 명령 (Node·Python·Go 등). 디버그 실행을 막는다.
    case unsupported

    public var title: String {
        switch self {
        case .javaToolOptions: return "JAVA_TOOL_OPTIONS (java 직접 실행)"
        case .gradleDebugJvm: return "Gradle --debug-jvm"
        case .mavenJvmArguments: return "Maven spring-boot.run.jvmArguments"
        case .unsupported: return "디버그 못 함"
        }
    }
}
