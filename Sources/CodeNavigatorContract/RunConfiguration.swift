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

    public var id: String { name }

    public init(name: String, command: String, workingDirectory: String, environment: [String: String]) {
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
    }

    /// 어디서 돌릴지. 절대 경로를 적었으면 그대로 쓴다 — 루트 아래로 억지로 밀어 넣으면
    /// `/tmp/x` 가 `/p/tmp/x` 가 된다.
    public func resolvedWorkingDirectory(projectRoot: String) -> String {
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return projectRoot }
        if trimmed.hasPrefix("/") { return trimmed }
        return (projectRoot as NSString).appendingPathComponent(trimmed)
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
