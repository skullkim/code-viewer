import Foundation

/// 클래스 이름으로 컴파일된 `.class` 파일을 찾는다.
///
/// 우리는 컴파일하지 않는다. 컴파일까지 하려면 빌드 도구(gradle·maven)를 알아야 하고, 그건
/// 이 앱이 하려는 일이 아니다 — 사용자가 자기 빌드로 만든 결과를 그대로 쓴다.
///
/// 찾는 자리는 흔한 출력 디렉터리들이다. 못 찾으면 **추측해서 아무 파일이나 넣지 않는다** —
/// 엉뚱한 바이트코드를 JVM 에 넣는 것은 아무것도 안 하는 것보다 훨씬 나쁘다.
public enum ClassFileLocator {

    /// 프로젝트 루트 기준으로 볼 자리들. 앞의 것부터 본다.
    static let outputDirectories = [
        "build/classes/java/main",   // gradle
        "build/classes/java/test",
        "target/classes",            // maven
        "target/test-classes",
        "out/production",            // IntelliJ
        "bin",                       // eclipse
        "",                          // 루트에 그냥 있는 경우 (javac 직접)
    ]

    public static func find(forClassNamed className: String, projectRoot: String) -> URL? {
        let relative = className.replacingOccurrences(of: ".", with: "/") + ".class"
        let root = URL(fileURLWithPath: projectRoot)

        for directory in outputDirectories {
            let candidate = directory.isEmpty
                ? root.appendingPathComponent(relative)
                : root.appendingPathComponent(directory).appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
