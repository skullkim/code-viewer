import Foundation

/// Turns a source file into the class name JDWP wants.
///
/// 브레이크포인트는 파일 경로가 아니라 클래스 이름으로 건다 — JDWP 는 파일을 모르고
/// `Lcom/example/Probe;` 같은 시그니처만 안다. 이 변환이 틀리면 브레이크포인트는 "그런
/// 클래스 없음" 으로 실패하고, 그 실패는 "아직 그 줄을 안 지났다" 와 화면에서 같아 보인다.
///
/// 파일 이름 = 공개 최상위 타입 이름이라는 Java 의 규칙에 기댄다. 중첩 클래스나 한 파일에
/// 든 비공개 보조 클래스는 이 이름으로 안 잡히는데, 그건 2차에서 `AllClasses` 로 다룬다.
public enum JavaTypeName {

    public static func forFile(atPath path: String, source: String) -> String? {
        guard path.hasSuffix(".java") else { return nil }
        let fileName = (path as NSString).lastPathComponent
        return forSource(source, fileName: fileName)
    }

    public static func forSource(_ source: String, fileName: String) -> String? {
        guard fileName.hasSuffix(".java") else { return nil }
        let typeName = String(fileName.dropLast(".java".count))
        guard !typeName.isEmpty else { return nil }
        guard let package = packageName(in: source) else { return typeName }
        return package + "." + typeName
    }

    /// 첫 `package` **선언**을 찾는다. 낱말이 아니라 선언이다 — 주석 안의 "this package is…"
    /// 를 선언으로 읽으면 엉뚱한 패키지가 나오고, 그 이름으로는 아무 클래스도 안 잡힌다.
    private static func packageName(in source: String) -> String? {
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("package ") else { continue }
            let body = trimmed.dropFirst("package ".count)
            let name = body.prefix { $0 != ";" }.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        return nil
    }
}
