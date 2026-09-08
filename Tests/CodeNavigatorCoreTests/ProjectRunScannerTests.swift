import Testing
import Foundation
@testable import CodeNavigatorCore

/// 디스크를 훑는 쪽. 규칙은 `RunConfigurationDetectorTests` 가 재고, 여기는 **진짜 폴더에서**
/// 무엇을 보고 무엇을 건너뛰는지만 잰다.
@Suite("프로젝트 훑기", .serialized)
struct ProjectRunScannerTests {

    private func makeTree(_ files: [String: String]) throws -> String {
        let root = NSTemporaryDirectory() + "scan-\(UUID().uuidString)"
        for (relativePath, contents) in files {
            let full = (root as NSString).appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                atPath: (full as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try contents.write(toFile: full, atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test("모노레포에서 폴더별로 잡는다")
    func findsConfigurationsPerDirectory() throws {
        let root = try makeTree([
            "backend/gradlew": "#!/bin/sh",
            "backend/build.gradle": "plugins { id 'org.springframework.boot' }",
            "frontend/package.json": #"{"scripts":{"dev":"vite"}}"#,
            "README.md": "# 문서",
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }

        let found = ProjectRunScanner.detect(projectRoot: root)
        #expect(found.map(\.workingDirectory).sorted() == ["backend", "frontend"])
        #expect(found.first { $0.workingDirectory == "backend" }?.debugLaunch == .gradleDebugJvm)
    }

    /// `node_modules` 안에는 package.json 이 수천 개 있다. **들어가지 않는 것**이 중요하다 —
    /// 들어가서 거르면 그 시간이 그대로 창이 뜨는 지연이 된다.
    @Test("node_modules 에는 들어가지 않는다")
    func doesNotDescendIntoVendorDirectories() throws {
        let root = try makeTree([
            "package.json": #"{"scripts":{"dev":"vite"}}"#,
            "node_modules/a/package.json": #"{"scripts":{"dev":"x"}}"#,
            "node_modules/b/c/package.json": #"{"scripts":{"start":"y"}}"#,
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }

        let files = ProjectRunScanner.listFiles(under: root)
        #expect(files == ["package.json"], "훑기가 node_modules 를 들어갔다: \(files)")
        #expect(ProjectRunScanner.detect(projectRoot: root).count == 1)
    }

    /// 경로는 루트 기준 상대여야 한다. 절대 경로가 섞이면 감지기의 폴더 판단이 통째로 어긋나고,
    /// `workingDirectory` 에 `/Users/...` 가 들어가 다른 기계에서 안 돈다.
    @Test("경로는 루트 기준 상대 경로다")
    func reportsRelativePaths() throws {
        let root = try makeTree(["deep/nested/file.txt": "x"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(ProjectRunScanner.listFiles(under: root) == ["deep/nested/file.txt"])
    }

    /// macOS 는 `/var`·`/tmp` 를 `/private` 아래로 링크해 두고, 열거기는 `/private` 쪽
    /// 철자를 내준다. 접두사 비교를 그대로 하면 **하나도 안 맞고 조용히 0건**이 된다 —
    /// 실제로 그렇게 됐다. 심링크로 연 프로젝트를 직접 만들어 확인한다.
    @Test("심링크로 연 프로젝트도 훑는다")
    func followsASymlinkedRoot() throws {
        let real = try makeTree(["package.json": #"{"scripts":{"dev":"vite"}}"#])
        defer { try? FileManager.default.removeItem(atPath: real) }
        let link = NSTemporaryDirectory() + "link-\(UUID().uuidString)"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        defer { try? FileManager.default.removeItem(atPath: link) }

        #expect(ProjectRunScanner.listFiles(under: link) == ["package.json"])
        #expect(ProjectRunScanner.detect(projectRoot: link).map(\.command) == ["npm run dev"])
    }

    /// `/private` 철자를 벗기는 규칙 자체를 못 박는다 — 이 한 줄이 위 결함의 전부였다.
    @Test("경로 정규화는 /private 만 벗기고 나머지는 건드리지 않는다")
    func normalizationOnlyStripsPrivate() {
        #expect(ProjectRunScanner.normalized("/private/var/x") == "/var/x")
        #expect(ProjectRunScanner.normalized("/var/x") == "/var/x")
        #expect(ProjectRunScanner.normalized("/Users/me/private/x") == "/Users/me/private/x")
        #expect(ProjectRunScanner.normalized("/privateer/x") == "/privateer/x")
    }

    @Test("빈 폴더는 빈 목록이다 — 지어내지 않는다")
    func emptyProjectYieldsNothing() throws {
        let root = try makeTree([:])
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(ProjectRunScanner.detect(projectRoot: root).isEmpty)
    }

    /// 없는 폴더를 훑으라고 하면 크래시가 아니라 빈 목록이어야 한다. 프로젝트가 지워진 뒤
    /// 탭이 복원되는 일이 실제로 있다.
    @Test("없는 폴더는 빈 목록이다")
    func missingDirectoryIsEmpty() {
        #expect(ProjectRunScanner.detect(projectRoot: "/그런/폴더/없음").isEmpty)
    }
}
