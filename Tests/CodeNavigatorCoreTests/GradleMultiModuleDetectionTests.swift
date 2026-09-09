import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// 코틀린·자바 **멀티모듈** Gradle 프로젝트.
///
/// 사용자가 겪은 것: "코틀린 멀티모듈에서는 계속 같은 에러뜨고 실행 안돼" — 그 에러가
/// `command not found: gradle` 이다.
///
/// 원인은 래퍼가 **루트에만** 있다는 것이다. 멀티모듈에서 `build.gradle.kts` 는 모듈마다
/// 있지만 `gradlew` 는 저장소 루트에 하나뿐이다. 모듈 폴더에서 래퍼를 찾다 못 찾으면 맨
/// `gradle` 로 떨어지는데, 그건 대부분의 기계에 설치돼 있지 않다.
///
/// 게다가 모듈 폴더에서 도는 것 자체가 틀렸다. Gradle 은 **루트에서** 모듈을 경로로
/// 지목해 돌린다 — `./gradlew :api:bootRun`.
@Suite("Gradle 멀티모듈 감지")
struct GradleMultiModuleDetectionTests {

    private func detect(
        _ files: [String], contents: [String: String] = [:]
    ) -> [RunConfiguration] {
        RunConfigurationDetector.detect(files: files) { contents[$0] }
    }

    /// 코틀린 멀티모듈의 흔한 모양: 루트에 래퍼와 settings, 모듈마다 build 파일.
    private var kotlinMultiModule: (files: [String], contents: [String: String]) {
        (
            [
                "gradlew",
                "settings.gradle.kts",
                "build.gradle.kts",
                "api/build.gradle.kts",
                "domain/build.gradle.kts",
            ],
            [
                // 루트는 플러그인을 **선언만** 한다. `apply false` 는 "여기서는 안 쓴다" 는 뜻이다.
                "build.gradle.kts": """
                plugins {
                    kotlin("jvm") version "1.9.0" apply false
                    id("org.springframework.boot") version "3.2.0" apply false
                }
                """,
                "settings.gradle.kts": """
                rootProject.name = "shop"
                include("api", "domain")
                """,
                "api/build.gradle.kts": """
                plugins {
                    id("org.springframework.boot")
                    kotlin("jvm")
                }
                """,
                "domain/build.gradle.kts": """
                plugins {
                    kotlin("jvm")
                }
                """,
            ]
        )
    }

    @Test("모듈에 래퍼가 없어도 루트의 래퍼를 쓴다")
    func usesTheWrapperAtTheGradleRoot() throws {
        let found = detect(kotlinMultiModule.files, contents: kotlinMultiModule.contents)
        let api = try #require(found.first { $0.command.contains("api") }, "감지된 것: \(found.map(\.command))")
        #expect(
            api.command.hasPrefix("./gradlew"),
            "맨 gradle 로 떨어졌다 — 대부분의 기계에 없다: \(api.command)"
        )
    }

    /// Gradle 은 루트에서 모듈을 경로로 지목해 돌린다. 모듈 폴더에서 `./gradlew` 를 부르면
    /// 그 파일이 거기 없다.
    @Test("루트에서 모듈 경로로 돌린다")
    func runsFromTheRootWithAModulePath() throws {
        let found = detect(kotlinMultiModule.files, contents: kotlinMultiModule.contents)
        let api = try #require(found.first { $0.command.contains("api") })
        #expect(api.command == "./gradlew :api:bootRun", "실제: \(api.command)")
        #expect(api.workingDirectory.isEmpty, "작업 폴더가 루트가 아니다: \(api.workingDirectory)")
    }

    /// `apply false` 는 "선언만 하고 여기서는 안 쓴다" 는 뜻이다. 루트를 돌릴 수 있는
    /// 것으로 읽으면 `./gradlew bootRun` 이 생기고, 그건 루트에 그 태스크가 없어 실패한다.
    @Test("apply false 인 루트는 돌릴 수 있는 것으로 보지 않는다")
    func ignoresPluginsDeclaredWithApplyFalse() {
        let found = detect(kotlinMultiModule.files, contents: kotlinMultiModule.contents)
        #expect(
            found.allSatisfy { $0.command != "./gradlew bootRun" },
            "루트를 실행 대상으로 잡았다: \(found.map(\.command))"
        )
    }

    /// 플러그인이 없는 모듈은 라이브러리다. 돌릴 것이 없다.
    @Test("라이브러리 모듈은 만들지 않는다")
    func skipsLibraryModules() {
        let found = detect(kotlinMultiModule.files, contents: kotlinMultiModule.contents)
        #expect(found.allSatisfy { !$0.command.contains("domain") }, "감지: \(found.map(\.command))")
    }

    /// 모듈이 더 깊을 수도 있다 — `services/api` 는 `:services:api` 다.
    @Test("중첩 모듈은 콜론으로 잇는다")
    func joinsNestedModulesWithColons() throws {
        let found = detect(
            ["gradlew", "settings.gradle.kts", "services/api/build.gradle.kts"],
            contents: [
                "services/api/build.gradle.kts": """
                plugins { id("org.springframework.boot") }
                """
            ]
        )
        let api = try #require(found.first, "아무것도 감지 못했다")
        #expect(api.command == "./gradlew :services:api:bootRun", "실제: \(api.command)")
    }

    /// 단일 모듈은 예전 그대로여야 한다 — 모듈 경로를 붙이면 오히려 깨진다.
    @Test("단일 모듈 프로젝트는 그대로 bootRun 이다")
    func singleModuleIsUnchanged() throws {
        let found = detect(
            ["gradlew", "build.gradle"],
            contents: ["build.gradle": "plugins { id 'org.springframework.boot' }"]
        )
        #expect(found.map(\.command) == ["./gradlew bootRun"])
        #expect(found[0].workingDirectory.isEmpty)
    }

    /// 래퍼가 어디에도 없으면 시스템 gradle 뿐이다. 그건 사실대로 두되, **루트에서** 돈다.
    @Test("래퍼가 아예 없으면 시스템 gradle 을 루트에서 쓴다")
    func fallsBackToSystemGradleAtTheRoot() throws {
        let found = detect(
            ["settings.gradle.kts", "api/build.gradle.kts"],
            contents: [
                "settings.gradle.kts": #"include("api")"#,
                "api/build.gradle.kts": #"plugins { id("org.springframework.boot") }"#,
            ]
        )
        let api = try #require(found.first)
        #expect(api.command == "gradle :api:bootRun", "실제: \(api.command)")
        #expect(api.workingDirectory.isEmpty)
    }

    /// 이름이 사람에게 읽혀야 한다. 모듈이 여럿이면 어느 것인지 알아야 고른다.
    @Test("이름에 모듈이 드러난다")
    func namesMentionTheModule() throws {
        let found = detect(kotlinMultiModule.files, contents: kotlinMultiModule.contents)
        let api = try #require(found.first)
        #expect(api.name.contains("api"), "이름: \(api.name)")
    }
}

/// Maven 멀티모듈도 같은 함정이 있다 — `mvnw` 는 루트에만 있다.
@Suite("Maven 멀티모듈 감지")
struct MavenMultiModuleDetectionTests {

    private func detect(
        _ files: [String], contents: [String: String] = [:]
    ) -> [RunConfiguration] {
        RunConfigurationDetector.detect(files: files) { contents[$0] }
    }

    @Test("모듈에 래퍼가 없어도 루트의 mvnw 를 쓴다")
    func usesTheWrapperAtTheRoot() throws {
        let found = detect(
            ["mvnw", "pom.xml", "api/pom.xml"],
            contents: [
                "pom.xml": "<project><modules><module>api</module></modules></project>",
                "api/pom.xml": """
                <project><build><plugins>
                  <plugin><artifactId>spring-boot-maven-plugin</artifactId></plugin>
                </plugins></build></project>
                """,
            ]
        )
        let api = try #require(found.first, "감지 0건")
        #expect(api.command.hasPrefix("./mvnw"), "맨 mvn 으로 떨어졌다: \(api.command)")
        // Maven 은 `-pl` 로 모듈을 지목하고 루트에서 돈다.
        #expect(api.command.contains("-pl api"), "실제: \(api.command)")
        #expect(api.workingDirectory.isEmpty)
    }

    @Test("단일 모듈 Maven 은 그대로다")
    func singleModuleIsUnchanged() {
        let found = detect(
            ["mvnw", "pom.xml"],
            contents: ["pom.xml": "<project><build><plugins><plugin><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build></project>"]
        )
        #expect(found.map(\.command) == ["./mvnw spring-boot:run"])
    }
}
