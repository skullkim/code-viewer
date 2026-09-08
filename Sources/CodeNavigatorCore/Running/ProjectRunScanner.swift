import CodeNavigatorContract
import Foundation

/// 프로젝트 폴더를 훑어 실행 설정을 감지한다.
///
/// 훑는 일과 판단하는 일을 갈라 둔다 — `RunConfigurationDetector` 는 순수 함수라 규칙을
/// 진짜 프로젝트 없이 시험할 수 있고, 여기는 디스크만 다룬다.
public enum ProjectRunScanner {

    /// 훑다가 멈추는 파일 수. 큰 저장소에서 프로젝트를 여는 순간 몇십만 개를 다 세면
    /// 창이 뜨는 동안 멈춰 있는다.
    static let fileLimit = 20_000

    /// 내용을 읽어 볼 파일 크기 상한. 생성된 거대 매니페스트를 통째로 메모리에 올리지 않는다.
    static let readLimit = 512 * 1024

    public static func detect(projectRoot: String) -> [RunConfiguration] {
        let files = listFiles(under: projectRoot)
        return RunConfigurationDetector.detect(files: files) { relativePath in
            read((projectRoot as NSString).appendingPathComponent(relativePath))
        }
    }

    static func listFiles(under root: String) -> [String] {
        // 루트와 열거된 경로를 **같은 방식으로** 맞춘다. 두 가지가 겹쳐 있어서 한 가지
        // 처방으로는 안 된다 — 실측으로 하나씩 갈랐다.
        //
        // - 루트가 **심링크 자체**이면 열거기가 아예 0건을 내준다(디렉터리로 안 본다).
        //   `resolvingSymlinksInPath` 가 이걸 푼다.
        // - 그런데 그 함수는 `/private/var` 를 `/var` 로 **되돌리는** 반면 열거기는
        //   `/private/var` 철자를 내준다. 접두사가 계속 어긋나므로 문자열로 한 번 더 맞춘다.
        //
        // 둘 중 하나만 하면 조용히 0건이 되고, 그건 "이 프로젝트는 띄울 게 없다" 와
        // 화면에서 구별되지 않는다.
        let rootURL = URL(fileURLWithPath: root).resolvingSymlinksInPath()
        let resolvedRoot = Self.normalized(rootURL.path)
        guard
            let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else {
            return []
        }

        var files: [String] = []
        for case let url as URL in enumerator {
            // 무시할 폴더는 **들어가지 않는다.** 들어가서 거르면 `node_modules` 하나에
            // 수만 번 도는데, 그 시간이 그대로 창이 뜨는 지연이 된다.
            let name = url.lastPathComponent
            if RunConfigurationDetector.ignoredDirectories.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false else {
                continue
            }
            // 열거는 해소된 루트에서 시작했으므로 접두사는 반드시 맞는다. 안 맞으면
            // 파일이 아니라 우리 가정이 틀린 것이라, 조용히 버리지 않고 그대로 담는다.
            let path = Self.normalized(url.path)
            guard path.hasPrefix(resolvedRoot) else {
                files.append(path)
                continue
            }
            files.append(String(path.dropFirst(resolvedRoot.count).drop(while: { $0 == "/" })))
            if files.count >= fileLimit { break }
        }
        return files
    }

    /// macOS 는 `/var`·`/tmp`·`/etc` 를 `/private` 아래로 링크해 두고, API 마다 어느 쪽
    /// 철자를 내주는지가 다르다. 비교하기 전에 한쪽으로 모은다.
    static func normalized(_ path: String) -> String {
        let privatePrefix = "/private"
        guard path.hasPrefix(privatePrefix + "/") else { return path }
        return String(path.dropFirst(privatePrefix.count))
    }

    private static func read(_ path: String) -> String? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attributes[.size] as? Int, size <= readLimit
        else {
            return nil
        }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}
