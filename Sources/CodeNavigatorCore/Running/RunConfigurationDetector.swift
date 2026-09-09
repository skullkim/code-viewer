import CodeNavigatorContract
import Foundation

/// 소스를 보고 "이 프로젝트는 이렇게 띄운다" 를 알아낸다.
///
/// 순수 함수다 — 파일 목록과 "이 경로의 내용을 다오" 를 받는다. 디스크를 직접 읽으면 이
/// 규칙들을 시험하는 데 매번 진짜 프로젝트를 만들어야 하고, 그런 테스트는 느리고 흔들린다.
///
/// **환경변수는 채우지 않는다.** `.env` 를 읽어 넣으면 비밀값이 앱 설정으로 복사되고,
/// 대부분의 프레임워크(dotenv·Spring)는 그 파일을 이미 스스로 읽는다. 자동으로 정하는 것은
/// 명령·작업 폴더·디버그 전략 셋뿐이다.
public enum RunConfigurationDetector {

    /// 이 아래는 보지 않는다. `node_modules` 안에만 package.json 이 수천 개다.
    static let ignoredDirectories: Set<String> = [
        "node_modules", "build", "out", "dist", "target", "vendor", "venv", ".venv",
        ".git", ".gradle", ".idea", ".build", "DerivedData", "__pycache__", "Pods",
    ]

    /// **매니페스트를** 찾아 내려갈 깊이. 모노레포의 `backend/`·`apps/api/` 까지 닿으면
    /// 충분하고, 더 내려가면 예제·픽스처 프로젝트까지 긁어 온다.
    ///
    /// 소스 파일에는 적용하지 않는다 — `src/main/java/com/example/App.java` 는 평범한
    /// 자바 경로인데 이 한도에 걸린다.
    static let maximumManifestDepth = 3

    public static func detect(
        files: [String], contentsOf read: (String) -> String?
    ) -> [RunConfiguration] {
        let candidates = files.filter { !isIgnored($0) }
        let manifests = candidates.filter { depth(of: $0) <= maximumManifestDepth }
        var found: [RunConfiguration] = []

        // 빌드 도구가 우선이다. 그것이 있으면 "어떻게 띄우는지" 의 답을 이미 알고 있고,
        // 클래스를 뒤지는 것보다 정확하다.
        for directory in directories(of: manifests).sorted() {
            found += detectBuildTool(in: directory, files: manifests, read: read)
        }

        // 빌드 도구를 하나도 못 찾았을 때만 main 클래스를 뒤진다. Gradle 프로젝트 안에는
        // main 이 여럿 있어서, 같이 넣으면 목록이 지저분해진다.
        if found.isEmpty {
            found += detectJavaMainClasses(in: candidates, read: read)
        }

        return makeNamesUnique(found)
    }

    // MARK: 빌드 도구

    private static func detectBuildTool(
        in directory: String, files: [String], read: (String) -> String?
    ) -> [RunConfiguration] {
        if let gradle = detectGradle(in: directory, files: files, read: read) { return [gradle] }
        if let maven = detectMaven(in: directory, files: files, read: read) { return [maven] }
        if let node = detectNode(in: directory, files: files, read: read) { return [node] }
        if let python = detectPython(in: directory, files: files) { return [python] }
        if let swift = detectSwiftPackage(in: directory, files: files, read: read) { return [swift] }
        if let go = detectGo(in: directory, files: files) { return [go] }
        if let rust = detectRust(in: directory, files: files) { return [rust] }
        return []
    }

    private static func detectGradle(
        in directory: String, files: [String], read: (String) -> String?
    ) -> RunConfiguration? {
        let buildFiles = ["build.gradle", "build.gradle.kts"]
            .map { path(directory, $0) }
            .filter(files.contains)
        guard let buildFile = buildFiles.first else { return nil }

        // Spring Boot 가 있으면 `bootRun`. 없고 `application` 플러그인만 있으면 `run`.
        // 둘 다 없으면 띄울 것이 없는 프로젝트다 — `build` 를 넣으면 실행 버튼이 빌드를
        // 돌리고, 사용자는 서버가 안 뜬다고 읽는다.
        let script = read(buildFile) ?? ""
        let task: String
        if containsPlugin("org.springframework.boot", in: script) {
            task = "bootRun"
        } else if containsApplicationPlugin(script) {
            task = "run"
        } else {
            return nil
        }

        // **래퍼는 루트에만 있다.** 멀티모듈에서 `build.gradle.kts` 는 모듈마다 있지만
        // `gradlew` 는 저장소 루트에 하나뿐이다. 모듈 폴더에서 래퍼를 찾다 못 찾아 맨
        // `gradle` 로 떨어지면, 그건 대부분의 기계에 설치돼 있지 않다 —
        // "command not found: gradle" 이 그것이다.
        let root = gradleRoot(for: directory, files: files)
        let launcher = files.contains(path(root, "gradlew")) ? "./gradlew" : "gradle"

        // Gradle 은 **루트에서** 모듈을 경로로 지목해 돌린다. 모듈 폴더에서 `./gradlew` 를
        // 부르면 그 파일이 거기 없다.
        let modulePath = gradleModulePath(of: directory, under: root)
        let target = modulePath.isEmpty ? task : "\(modulePath):\(task)"

        return RunConfiguration(
            name: label(directory, task),
            command: "\(launcher) \(target)",
            workingDirectory: root,
            environment: [:],
            // 런처 JVM 이 JAVA_TOOL_OPTIONS 를 가로챈다 — 실측된 결함이다.
            debugLaunch: .gradleDebugJvm
        )
    }

    /// 이 모듈이 속한 Maven 루트. `mvnw` 나 부모 `pom.xml` 이 있는 가장 가까운 조상.
    private static func mavenRoot(for directory: String, files: [String]) -> String {
        var candidate = directory
        while true {
            if candidate != directory,
               files.contains(path(candidate, "pom.xml")) || files.contains(path(candidate, "mvnw")) {
                return candidate
            }
            if candidate == directory, files.contains(path(candidate, "mvnw")) {
                return candidate
            }
            guard !candidate.isEmpty else { return directory }
            candidate = candidate.split(separator: "/").dropLast().joined(separator: "/")
        }
    }

    /// `services/api` 를 루트 기준 상대 경로로. 루트 자신이면 빈 문자열.
    private static func relativePath(of directory: String, under root: String) -> String {
        guard directory != root else { return "" }
        guard !root.isEmpty, directory.hasPrefix(root + "/") else { return directory }
        return String(directory.dropFirst(root.count + 1))
    }

    /// 이 모듈이 속한 Gradle 루트. `gradlew` 나 `settings.gradle` 이 있는 가장 가까운
    /// 조상이고, 없으면 프로젝트 루트다.
    private static func gradleRoot(for directory: String, files: [String]) -> String {
        var candidate = directory
        while true {
            let marks = ["gradlew", "settings.gradle", "settings.gradle.kts"]
            if marks.contains(where: { files.contains(path(candidate, $0)) }) {
                return candidate
            }
            guard !candidate.isEmpty else { return "" }
            let parts = candidate.split(separator: "/").dropLast()
            candidate = parts.joined(separator: "/")
        }
    }

    /// `services/api` → `:services:api`. 루트 자신이면 빈 문자열.
    private static func gradleModulePath(of directory: String, under root: String) -> String {
        guard directory != root else { return "" }
        var relative = directory
        if !root.isEmpty, relative.hasPrefix(root + "/") {
            relative = String(relative.dropFirst(root.count + 1))
        }
        guard !relative.isEmpty else { return "" }
        return ":" + relative.split(separator: "/").joined(separator: ":")
    }

    /// 플러그인이 **이 모듈에서 실제로 쓰이는지**.
    ///
    /// 멀티모듈 루트는 플러그인을 선언만 하고 `apply false` 를 붙인다 — "버전은 여기서
    /// 정하되 여기서는 안 쓴다" 는 뜻이다. 그것을 쓰는 것으로 읽으면 루트에 `bootRun` 이
    /// 있는 줄 알고, 그 명령은 "그런 태스크 없음" 으로 실패한다.
    private static func containsPlugin(_ identifier: String, in script: String) -> Bool {
        for line in script.split(separator: "\n") {
            guard line.contains(identifier) else { continue }
            guard !line.contains("apply false") else { continue }
            return true
        }
        return false
    }

    /// `application` 플러그인이 선언됐는지.
    ///
    /// 두 가지를 동시에 만족해야 한다.
    /// - `plugins { id 'application' }` 처럼 **한 줄로 쓴 블록**도 읽어야 한다. 줄 단위
    ///   정확 일치로 짰다가 라이브 검증에서 못 읽는 것을 봤다 — 한 줄 블록은 아주 흔하다.
    /// - `java-library`·`my-application-plugin`·주석 속 "application" 에 걸리면 안 된다.
    ///   라이브러리에 실행 설정이 생기고, 실행 버튼이 아무것도 안 띄운다.
    ///
    /// 그래서 낱말이 아니라 **선언 형태**를 찾는다.
    private static func containsApplicationPlugin(_ script: String) -> Bool {
        // Groovy·Kotlin DSL 의 선언 형태. 따옴표까지 포함해서 찾으므로 `my-application-plugin`
        // 같은 이름에는 걸리지 않는다.
        let declarations = ["id 'application'", "id \"application\"", "id('application')", "id(\"application\")"]
        for line in script.split(separator: "\n") {
            // `apply false` 는 "여기서는 안 쓴다" 는 뜻이다 — 멀티모듈 루트가 그렇게 쓴다.
            guard !line.contains("apply false") else { continue }
            if declarations.contains(where: line.contains) { return true }
        }

        // Kotlin DSL 은 괄호 없이 `application` 한 줄로도 쓴다. 이건 줄 전체가 그것뿐일 때만
        // 인정한다 — 그러지 않으면 산문 속 낱말에 걸린다.
        return script.split(separator: "\n").contains { line in
            line.trimmingCharacters(in: .whitespaces) == "application"
        }
    }

    private static func detectMaven(
        in directory: String, files: [String], read: (String) -> String?
    ) -> RunConfiguration? {
        let pom = path(directory, "pom.xml")
        guard files.contains(pom) else { return nil }
        guard read(pom)?.contains("spring-boot-maven-plugin") == true else { return nil }

        // **래퍼는 루트에만 있다** — Gradle 과 같은 함정이다. 모듈 폴더에서 찾다 못 찾아
        // 맨 `mvn` 으로 떨어지면 대부분의 기계에 없다.
        let root = mavenRoot(for: directory, files: files)
        let launcher = files.contains(path(root, "mvnw")) ? "./mvnw" : "mvn"
        // Maven 은 루트에서 `-pl` 로 모듈을 지목한다.
        let modulePath = relativePath(of: directory, under: root)
        let target = modulePath.isEmpty
            ? "spring-boot:run"
            : "-pl \(modulePath) spring-boot:run"

        return RunConfiguration(
            name: label(directory, "spring-boot:run"),
            command: "\(launcher) \(target)",
            workingDirectory: root,
            environment: [:],
            debugLaunch: .mavenJvmArguments
        )
    }

    /// 띄우는 스크립트 이름을 고르는 순서. 앞엣것이 이긴다.
    static let nodeRunScripts = ["dev", "start:dev", "serve", "start"]

    private static func detectNode(
        in directory: String, files: [String], read: (String) -> String?
    ) -> RunConfiguration? {
        let manifest = path(directory, "package.json")
        guard files.contains(manifest), let text = read(manifest) else { return nil }
        guard
            let data = text.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scripts = root["scripts"] as? [String: Any]
        else {
            return nil
        }
        // 띄우는 스크립트가 없는 package.json 은 대개 설정 파일일 뿐이다.
        guard let script = nodeRunScripts.first(where: { scripts[$0] != nil }) else { return nil }

        return RunConfiguration(
            name: label(directory, script),
            command: "npm run \(script)",
            workingDirectory: directory,
            environment: [:],
            // JDWP 는 JVM 전용이다. Node 는 V8 인스펙터를 쓴다 — 지금 우리 디버거로는 못 붙는다.
            debugLaunch: .unsupported
        )
    }

    private static func detectPython(in directory: String, files: [String]) -> RunConfiguration? {
        if files.contains(path(directory, "manage.py")) {
            return RunConfiguration(
                name: label(directory, "runserver"),
                command: "python3 manage.py runserver",
                workingDirectory: directory, environment: [:], debugLaunch: .unsupported
            )
        }
        if files.contains(path(directory, "main.py")) {
            return RunConfiguration(
                name: label(directory, "main.py"),
                command: "python3 main.py",
                workingDirectory: directory, environment: [:], debugLaunch: .unsupported
            )
        }
        return nil
    }

    private static func detectSwiftPackage(
        in directory: String, files: [String], read: (String) -> String?
    ) -> RunConfiguration? {
        let manifest = path(directory, "Package.swift")
        guard files.contains(manifest), let text = read(manifest) else { return nil }
        // 라이브러리뿐인 패키지는 띄울 것이 없다. 실행 산출물의 이름을 그대로 쓴다 —
        // 여러 개면 `swift run` 이 어느 것인지 되묻는다.
        guard let product = firstExecutableProduct(in: text) else { return nil }
        return RunConfiguration(
            name: label(directory, product),
            command: "swift run \(product)",
            workingDirectory: directory, environment: [:], debugLaunch: .unsupported
        )
    }

    private static func firstExecutableProduct(in manifest: String) -> String? {
        guard let range = manifest.range(of: ".executable(") else { return nil }
        let rest = manifest[range.upperBound...]
        guard let nameRange = rest.range(of: "name:") else { return nil }
        let afterName = rest[nameRange.upperBound...].drop(while: { $0 != "\"" }).dropFirst()
        let product = String(afterName.prefix { $0 != "\"" })
        return product.isEmpty ? nil : product
    }

    private static func detectGo(in directory: String, files: [String]) -> RunConfiguration? {
        guard files.contains(path(directory, "go.mod")) else { return nil }
        return RunConfiguration(
            name: label(directory, "go run"), command: "go run .",
            workingDirectory: directory, environment: [:], debugLaunch: .unsupported
        )
    }

    private static func detectRust(in directory: String, files: [String]) -> RunConfiguration? {
        // 라이브러리 크레이트에는 `src/main.rs` 가 없다 — `cargo run` 이 할 일이 없다.
        guard files.contains(path(directory, "Cargo.toml")),
              files.contains(path(directory, "src/main.rs"))
        else {
            return nil
        }
        return RunConfiguration(
            name: label(directory, "cargo run"), command: "cargo run",
            workingDirectory: directory, environment: [:], debugLaunch: .unsupported
        )
    }

    // MARK: 순수 Java

    private static func detectJavaMainClasses(
        in files: [String], read: (String) -> String?
    ) -> [RunConfiguration] {
        files.filter { $0.hasSuffix(".java") }.sorted().compactMap { file in
            guard let source = read(file), hasMainMethod(source) else { return nil }
            let className = (file as NSString).lastPathComponent.replacingOccurrences(
                of: ".java", with: ""
            )
            let qualified = packageName(in: source).map { "\($0).\(className)" } ?? className
            return RunConfiguration(
                name: className,
                // 어디에 컴파일했는지는 프로젝트마다 달라 알 수 없다. 현재 폴더를 클래스패스로
                // 두고, 사용자가 고치게 한다 — 빈 명령보다 고칠 거리가 있는 편이 낫다.
                command: "java -cp . \(qualified)",
                workingDirectory: "",
                environment: [:],
                debugLaunch: .javaToolOptions
            )
        }
    }

    private static func hasMainMethod(_ source: String) -> Bool {
        for line in source.split(separator: "\n") {
            let squeezed = line.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            if squeezed.contains("static void main(String") { return true }
        }
        return false
    }

    private static func packageName(in source: String) -> String? {
        for line in source.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("package ") else { continue }
            return trimmed
                .dropFirst("package ".count)
                .prefix { $0 != ";" }
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: 경로 다루기

    private static func isIgnored(_ file: String) -> Bool {
        file.split(separator: "/").dropLast().contains { ignoredDirectories.contains(String($0)) }
    }

    private static func depth(of file: String) -> Int {
        file.split(separator: "/").count
    }

    /// 매니페스트가 있을 수 있는 폴더들. 루트는 빈 문자열이다.
    private static func directories(of files: [String]) -> Set<String> {
        var result: Set<String> = [""]
        for file in files {
            let parts = file.split(separator: "/").dropLast()
            guard !parts.isEmpty else { continue }
            result.insert(parts.joined(separator: "/"))
        }
        return result
    }

    private static func path(_ directory: String, _ name: String) -> String {
        directory.isEmpty ? name : "\(directory)/\(name)"
    }

    /// 사람이 읽을 이름. 모노레포에서는 폴더 이름이 무엇인지 말해 주는 유일한 단서다.
    private static func label(_ directory: String, _ task: String) -> String {
        guard !directory.isEmpty else { return task }
        return "\((directory as NSString).lastPathComponent) \(task)"
    }

    /// 이름이 곧 id 다. 겹치면 고르개가 한 줄만 보여 주고 나머지는 영영 못 고른다.
    private static func makeNamesUnique(_ configurations: [RunConfiguration]) -> [RunConfiguration] {
        var used: Set<String> = []
        return configurations.map { configuration in
            var renamed = configuration
            var name = configuration.name
            var suffix = 2
            while used.contains(name) {
                name = "\(configuration.name) \(suffix)"
                suffix += 1
            }
            used.insert(name)
            renamed.name = name
            return renamed
        }
    }
}
