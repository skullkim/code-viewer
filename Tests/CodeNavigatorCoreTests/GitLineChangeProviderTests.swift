import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// 진짜 git 저장소에 대고 잰다. 파싱 규칙은 `GitLineChangeParserTests` 가 재고, 여기서는
/// **git 을 실제로 부르는 부분**만 본다 — 인자 하나가 틀리면 조용히 빈 목록이 되고, 그건
/// "바뀐 게 없다" 와 화면에서 구별되지 않는다.
@Suite("Git 변경 조회 — 실제 저장소", .serialized)
struct GitLineChangeProviderTests {

    private func makeRepository(_ files: [String: String]) throws -> String {
        let root = NSTemporaryDirectory() + "gitprobe-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        for (path, contents) in files {
            let full = (root as NSString).appendingPathComponent(path)
            try FileManager.default.createDirectory(
                atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true
            )
            try contents.write(toFile: full, atomically: true, encoding: .utf8)
        }
        // 사용자의 전역 설정(서명 요구·훅)에 흔들리지 않게 최소 설정으로 만든다.
        for arguments in [
            ["init", "-q", "-b", "main"],
            ["config", "user.email", "probe@example.invalid"],
            ["config", "user.name", "Probe"],
            ["config", "commit.gpgsign", "false"],
            ["add", "."],
            ["commit", "-q", "-m", "first", "--no-verify"],
        ] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            process.currentDirectoryURL = URL(fileURLWithPath: root)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }
        return root
    }

    private func write(_ contents: String, to path: String, in root: String) throws {
        try contents.write(
            toFile: (root as NSString).appendingPathComponent(path), atomically: true, encoding: .utf8
        )
    }

    @Test("고친 줄만 수정으로 나온다")
    func reportsOnlyTheEditedLine() throws {
        let root = try makeRepository(["A.java": "one\ntwo\nthree\nfour\n"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("one\nTWO\nthree\nfour\n", to: "A.java", in: root)

        let changes = GitLineChangeProvider().changes(forFileAt: "A.java", repositoryRoot: root)
        #expect(changes == [GitLineChange(line: 2, kind: .modified)], "실제로 받은 것: \(changes)")
    }

    @Test("새로 넣은 줄은 추가로 나온다")
    func reportsInsertedLines() throws {
        let root = try makeRepository(["A.java": "one\ntwo\n"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("one\ninserted\ntwo\n", to: "A.java", in: root)

        let changes = GitLineChangeProvider().changes(forFileAt: "A.java", repositoryRoot: root)
        #expect(changes == [GitLineChange(line: 2, kind: .added)], "실제로 받은 것: \(changes)")
    }

    /// **스테이지에 올려도 표시가 남아야 한다.** 인덱스와만 견주면 방금 `git add` 한 줄이
    /// 표시에서 사라지고, 사용자는 그 변경이 없어진 것으로 읽는다.
    @Test("git add 한 변경도 계속 보인다")
    func stagedChangesStillShow() throws {
        let root = try makeRepository(["A.java": "one\ntwo\n"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("one\nTWO\n", to: "A.java", in: root)

        let add = Process()
        add.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        add.arguments = ["git", "add", "A.java"]
        add.currentDirectoryURL = URL(fileURLWithPath: root)
        add.standardError = FileHandle.nullDevice
        try add.run()
        add.waitUntilExit()

        let changes = GitLineChangeProvider().changes(forFileAt: "A.java", repositoryRoot: root)
        #expect(changes == [GitLineChange(line: 2, kind: .modified)], "스테이지에 올리자 표시가 사라졌다")
    }

    /// 추적되지 않는 파일에는 `git diff` 가 아무 말도 안 한다. 표시가 하나도 없으면 사용자는
    /// 이 파일이 이미 저장소에 있는 것으로 읽는다.
    @Test("추적 안 되는 파일은 전부 추가다")
    func untrackedFileIsAllAdded() throws {
        let root = try makeRepository(["A.java": "one\n"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("x\ny\nz\n", to: "New.java", in: root)

        let changes = GitLineChangeProvider().changes(forFileAt: "New.java", repositoryRoot: root)
        #expect(changes.map(\.line) == [1, 2, 3])
        #expect(changes.allSatisfy { $0.kind == .added })
    }

    @Test("바꾸지 않았으면 표시가 없다")
    func unchangedFileHasNoMarks() throws {
        let root = try makeRepository(["A.java": "one\ntwo\n"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(GitLineChangeProvider().changes(forFileAt: "A.java", repositoryRoot: root).isEmpty)
    }

    /// git 저장소가 아닌 폴더에서도 죽지 않아야 한다 — 대부분의 사용자는 저장소가 아닌
    /// 폴더도 연다.
    @Test("저장소가 아니면 조용히 빈 목록이다")
    func nonRepositoryIsEmpty() throws {
        let root = NSTemporaryDirectory() + "plain-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("one\n", to: "A.java", in: root)

        #expect(GitLineChangeProvider().changes(forFileAt: "A.java", repositoryRoot: root).isEmpty)
    }

    @Test("지운 줄은 남아 있는 줄에 표시된다")
    func deletionIsAnchoredToASurvivingLine() throws {
        let root = try makeRepository(["A.java": "one\ntwo\nthree\nfour\n"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("one\nfour\n", to: "A.java", in: root)

        let changes = GitLineChangeProvider().changes(forFileAt: "A.java", repositoryRoot: root)
        #expect(changes.contains { $0.kind == .deleted }, "실제로 받은 것: \(changes)")
    }
}
