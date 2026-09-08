import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// 소스를 보고 "이 프로젝트는 이렇게 띄운다" 를 알아낸다.
///
/// 픽스처는 이 기계에 실제로 있는 프로젝트들에서 가져왔다 — 지어낸 모양으로 시험하면
/// 지어낸 것만 통과한다.
@Suite("실행 설정 감지")
struct RunConfigurationDetectorTests {

    private func detect(
        _ files: [String], contents: [String: String] = [:]
    ) -> [RunConfiguration] {
        RunConfigurationDetector.detect(files: files) { contents[$0] }
    }

    // MARK: Gradle

    /// `~/Documents/repo/2022-thankoo/backend` 의 모양.
    @Test("Gradle + Spring Boot 는 bootRun 으로, 런처를 피하는 전략으로 잡는다")
    func findsSpringBootGradle() throws {
        let found = detect(
            ["backend/gradlew", "backend/build.gradle", "backend/settings.gradle"],
            contents: ["backend/build.gradle": """
            plugins {
                id 'org.springframework.boot' version '2.6.8'
                id 'java'
            }
            """]
        )
        let first = try #require(found.first)
        #expect(found.count == 1)
        #expect(first.command == "./gradlew bootRun")
        #expect(first.workingDirectory == "backend")
        #expect(first.debugLaunch == .gradleDebugJvm, "JAVA_TOOL_OPTIONS 는 런처가 가로챈다")
    }

    @Test("Spring Boot 가 아닌 Gradle 은 application 플러그인의 run 을 쓴다")
    func findsPlainGradleApplication() {
        let found = detect(
            ["gradlew", "build.gradle.kts"],
            contents: ["build.gradle.kts": """
            plugins {
                application
                kotlin("jvm") version "1.9.0"
            }
            """]
        )
        #expect(found.map(\.command) == ["./gradlew run"])
        #expect(found[0].workingDirectory == "", "루트면 작업 폴더는 비운다")
    }

    /// 라이브 검증이 잡은 빈틈: `plugins { id 'application' }` 처럼 **한 줄로 쓴 블록**을
    /// 못 봤다. 줄 단위 정확 일치로 짰기 때문인데, 한 줄 블록은 아주 흔하다.
    @Test("한 줄로 쓴 plugins 블록도 읽는다")
    func readsASingleLinePluginsBlock() {
        for script in [
            "plugins { id 'application' }",
            #"plugins { id "application" }"#,
            #"plugins { id("application") }"#,
            "plugins {\n    id 'application'\n}",
        ] {
            #expect(
                detect(["gradlew", "build.gradle"], contents: ["build.gradle": script])
                    .map(\.command) == ["./gradlew run"],
                "못 읽은 형태: \(script)"
            )
        }
    }

    /// 그렇다고 아무 `application` 이나 잡으면 안 된다. 라이브러리에 실행 설정이 생긴다.
    @Test("낱말만 같은 것에는 걸리지 않는다")
    func doesNotMatchLookalikeWords() {
        for script in [
            "plugins { id 'java-library' }\n// application code lives in app/",
            "description = 'A library for application developers'",
            "plugins { id 'my-application-plugin' }",
        ] {
            #expect(
                detect(["gradlew", "build.gradle"], contents: ["build.gradle": script]).isEmpty,
                "잘못 잡은 형태: \(script)"
            )
        }
    }

    /// 라이브러리 프로젝트는 띄울 것이 없다. 억지로 `./gradlew build` 를 넣으면 실행
    /// 버튼이 빌드를 돌리고, 사용자는 서버가 안 뜬다고 읽는다.
    @Test("돌릴 것이 없는 Gradle 프로젝트는 아무것도 만들지 않는다")
    func skipsLibraryOnlyGradle() {
        let found = detect(
            ["gradlew", "build.gradle"],
            contents: ["build.gradle": "plugins { id 'java-library' }"]
        )
        #expect(found.isEmpty)
    }

    // MARK: Maven

    @Test("Maven + Spring Boot 는 spring-boot:run 으로 잡는다")
    func findsSpringBootMaven() {
        let found = detect(
            ["mvnw", "pom.xml"],
            contents: ["pom.xml": """
            <project><build><plugins>
              <plugin><groupId>org.springframework.boot</groupId>
              <artifactId>spring-boot-maven-plugin</artifactId></plugin>
            </plugins></build></project>
            """]
        )
        #expect(found.map(\.command) == ["./mvnw spring-boot:run"])
        #expect(found[0].debugLaunch == .mavenJvmArguments)
    }

    /// `mvnw` 가 없으면 `mvn` 을 쓴다. 없는 파일을 부르면 "권한 없음" 으로 끝난다.
    @Test("래퍼가 없으면 시스템 mvn 을 쓴다")
    func fallsBackToSystemMaven() {
        let found = detect(
            ["pom.xml"],
            contents: ["pom.xml": "<project><build><plugins><plugin><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build></project>"]
        )
        #expect(found.map(\.command) == ["mvn spring-boot:run"])
    }

    // MARK: Node

    /// `~/Documents/repo/store-management` 의 모양 — 백엔드와 프론트가 따로 있다.
    @Test("package.json 두 개를 각자의 폴더로 잡는다")
    func findsBothNodePackages() {
        let found = detect(
            ["backend/package.json", "frontend/package.json"],
            contents: [
                "backend/package.json": #"{"scripts":{"start":"nest start","start:dev":"nest start --watch"}}"#,
                "frontend/package.json": #"{"scripts":{"dev":"vite","build":"vite build"}}"#,
            ]
        )
        #expect(found.count == 2)
        let byDirectory = Dictionary(uniqueKeysWithValues: found.map { ($0.workingDirectory, $0) })
        #expect(byDirectory["backend"]?.command == "npm run start:dev")
        #expect(byDirectory["frontend"]?.command == "npm run dev")
        #expect(byDirectory["frontend"]?.debugLaunch == .unsupported, "JDWP 로는 못 붙는다")
    }

    @Test("dev 가 있으면 dev 를, 없으면 start 를 고른다")
    func prefersTheDevScript() {
        #expect(
            detect(["package.json"], contents: ["package.json": #"{"scripts":{"dev":"vite","start":"node ."}}"#])
                .map(\.command) == ["npm run dev"]
        )
        #expect(
            detect(["package.json"], contents: ["package.json": #"{"scripts":{"start":"node ."}}"#])
                .map(\.command) == ["npm run start"]
        )
    }

    /// 돌릴 스크립트가 없는 package.json 은 대개 설정 파일일 뿐이다.
    @Test("띄우는 스크립트가 없으면 만들지 않는다")
    func skipsPackagesWithoutARunScript() {
        #expect(
            detect(["package.json"], contents: ["package.json": #"{"scripts":{"build":"tsc","test":"jest"}}"#])
                .isEmpty
        )
    }

    /// `node_modules` 안에도 package.json 이 수천 개 있다. 그것까지 잡으면 목록이 쓸모없어진다.
    @Test("node_modules 와 build 산출물은 보지 않는다")
    func ignoresVendorDirectories() {
        let found = detect(
            [
                "node_modules/express/package.json",
                "backend/node_modules/x/package.json",
                "build/package.json",
                ".git/package.json",
                "package.json",
            ],
            contents: ["package.json": #"{"scripts":{"dev":"vite"}}"#]
        )
        #expect(found.map(\.workingDirectory) == [""])
    }

    // MARK: Python · 그 밖

    @Test("main.py 는 파이썬 실행으로 잡는다")
    func findsPythonEntryPoint() {
        let found = detect(["main.py", "requirements.txt"])
        #expect(found.map(\.command) == ["python3 main.py"])
        #expect(found[0].debugLaunch == .unsupported)
    }

    @Test("manage.py 가 있으면 Django 로 본다")
    func findsDjango() {
        #expect(
            detect(["manage.py"]).map(\.command) == ["python3 manage.py runserver"]
        )
    }

    // MARK: Swift · Go · Rust

    /// 이 앱 자신이 그 모양이다 — `.executable` 이 있으면 돌릴 것이 있다.
    @Test("실행 산출물이 있는 Swift 패키지는 swift run 으로 잡는다")
    func findsSwiftExecutable() {
        let found = detect(
            ["Package.swift"],
            contents: ["Package.swift": """
            let package = Package(
                name: "Thing",
                products: [
                    .library(name: "Core", targets: ["Core"]),
                    .executable(name: "thing", targets: ["App"]),
                ]
            )
            """]
        )
        #expect(found.map(\.command) == ["swift run thing"])
        #expect(found[0].debugLaunch == .unsupported, "JDWP 는 JVM 전용이다")
    }

    /// 라이브러리뿐인 패키지는 띄울 것이 없다.
    @Test("라이브러리만 있는 Swift 패키지는 만들지 않는다")
    func skipsLibraryOnlySwiftPackage() {
        #expect(
            detect(
                ["Package.swift"],
                contents: ["Package.swift": #"products: [.library(name: "Core", targets: ["Core"])]"#]
            ).isEmpty
        )
    }

    @Test("go.mod 와 Cargo.toml 도 잡는다")
    func findsGoAndRust() {
        #expect(detect(["go.mod", "main.go"]).map(\.command) == ["go run ."])
        #expect(detect(["Cargo.toml", "src/main.rs"]).map(\.command) == ["cargo run"])
    }

    /// 라이브러리 크레이트에는 `src/main.rs` 가 없다.
    @Test("main.rs 가 없는 크레이트는 만들지 않는다")
    func skipsLibraryCrate() {
        #expect(detect(["Cargo.toml", "src/lib.rs"]).isEmpty)
    }

    // MARK: 순수 Java

    @Test("빌드 도구가 없으면 main 을 가진 클래스를 찾는다")
    func findsAPlainMainClass() {
        let found = detect(
            ["src/Server.java", "src/Helper.java"],
            contents: [
                "src/Server.java": """
                public class Server {
                    public static void main(String[] args) {}
                }
                """,
                "src/Helper.java": "class Helper { void main() {} }",
            ]
        )
        #expect(found.count == 1, "main 이 없는 파일까지 잡았다")
        #expect(found[0].command.contains("Server"))
        #expect(found[0].debugLaunch == .javaToolOptions)
    }

    @Test("패키지가 있으면 완전한 이름으로 부른다")
    func usesTheFullyQualifiedName() throws {
        let found = detect(
            ["src/main/java/com/example/App.java"],
            contents: ["src/main/java/com/example/App.java": """
            package com.example;
            public class App {
                public static void main(String[] args) {}
            }
            """]
        )
        let first = try #require(found.first, "깊은 경로의 자바 파일을 아예 못 봤다")
        #expect(first.command.contains("com.example.App"))
    }

    /// Gradle 프로젝트 안에는 main 클래스가 여럿 있다. 빌드 도구가 답을 알고 있으므로
    /// 클래스를 뒤질 필요가 없고, 뒤지면 목록이 지저분해진다.
    @Test("빌드 도구를 찾았으면 main 클래스는 뒤지지 않는다")
    func doesNotScanClassesWhenABuildToolAnswers() {
        let found = detect(
            ["gradlew", "build.gradle", "src/main/java/App.java"],
            contents: [
                "build.gradle": "plugins { id 'org.springframework.boot' }",
                "src/main/java/App.java": "public class App { public static void main(String[] a){} }",
            ]
        )
        #expect(found.map(\.command) == ["./gradlew bootRun"])
    }

    // MARK: 이름과 순서

    @Test("이름이 겹치지 않는다 — 이름이 곧 id 다")
    func namesAreUnique() {
        let found = detect(
            ["a/package.json", "b/package.json"],
            contents: [
                "a/package.json": #"{"scripts":{"dev":"vite"}}"#,
                "b/package.json": #"{"scripts":{"dev":"vite"}}"#,
            ]
        )
        #expect(Set(found.map(\.name)).count == found.count)
    }

    @Test("아무것도 못 찾으면 빈 목록이다 — 지어내지 않는다")
    func inventsNothing() {
        #expect(detect(["README.md", "docs/guide.md"]).isEmpty)
    }
}
