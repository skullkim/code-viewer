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

/// 프로젝트 루트가 **저장소의 하위 폴더**인 경우. 사용자의 실제 모양이다 —
/// `2022-thankoo/backend` 를 열면 git 루트는 그 위다. 여기서 조용히 빈 목록이 되면
/// 변경 막대가 아예 안 나온다.
@Suite("Git 변경 조회 — 저장소 하위 폴더를 열었을 때", .serialized)
struct GitSubdirectoryProviderTests {

    @Test("하위 폴더를 프로젝트로 열어도 변경이 나온다")
    func worksWhenTheProjectRootIsBelowTheRepositoryRoot() throws {
        let repository = NSTemporaryDirectory() + "gitsub-\(UUID().uuidString)"
        let module = (repository as NSString).appendingPathComponent("backend")
        try FileManager.default.createDirectory(atPath: module, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: repository) }

        let file = (module as NSString).appendingPathComponent("A.java")
        try "one\ntwo\nthree\n".write(toFile: file, atomically: true, encoding: .utf8)

        for arguments in [
            ["init", "-q", "-b", "main"], ["config", "user.email", "p@e.invalid"],
            ["config", "user.name", "P"], ["add", "."], ["commit", "-q", "-m", "first", "--no-verify"],
        ] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            process.currentDirectoryURL = URL(fileURLWithPath: repository)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }
        try "one\nTWO\nthree\n".write(toFile: file, atomically: true, encoding: .utf8)

        // 프로젝트 루트는 `backend` 다 — git 루트가 아니다.
        let changes = GitLineChangeProvider().changes(forFileAt: "A.java", repositoryRoot: module)
        #expect(changes == [GitLineChange(line: 2, kind: .modified)], "실제로 받은 것: \(changes)")
    }
}

/// **저장하기 전**의 편집도 막대에 나와야 한다.
///
/// 사용자가 겪은 것: "변경된 코드 왼쪽에 노란줄 안나오자낭." 저장소는 커밋 기준으로
/// 깨끗했고, 고친 내용은 편집기 버퍼에만 있었다. `git diff` 는 디스크만 보므로 아무것도
/// 못 봤다 — 우리 눈에는 "변경 없음" 과 구별되지 않는다.
///
/// IntelliJ 는 타이핑하는 즉시 그린다. 메모리의 문서를 저장소 내용과 견주기 때문이다.
@Suite("Git 변경 조회 — 저장 전 버퍼", .serialized)
struct GitBufferChangeProviderTests {

    private func makeRepository(_ files: [String: String]) throws -> String {
        let root = NSTemporaryDirectory() + "gitbuf-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        for (path, contents) in files {
            try contents.write(
                toFile: (root as NSString).appendingPathComponent(path),
                atomically: true, encoding: .utf8
            )
        }
        for arguments in [
            ["init", "-q", "-b", "main"], ["config", "user.email", "p@e.invalid"],
            ["config", "user.name", "P"], ["add", "."], ["commit", "-q", "-m", "first", "--no-verify"],
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

    @Test("디스크는 그대로인데 버퍼만 고쳤어도 표시된다")
    func reportsUnsavedEdits() throws {
        let root = try makeRepository(["A.java": "one\ntwo\nthree\n"])
        defer { try? FileManager.default.removeItem(atPath: root) }

        // 디스크는 손대지 않는다 — 편집기 버퍼만 다르다.
        let changes = GitLineChangeProvider().changes(
            forFileAt: "A.java", repositoryRoot: root, bufferContents: "one\nTWO\nthree\n"
        )
        #expect(changes == [GitLineChange(line: 2, kind: .modified)], "실제로 받은 것: \(changes)")
    }

    @Test("버퍼에 줄을 넣으면 추가로 나온다")
    func reportsUnsavedInsertions() throws {
        let root = try makeRepository(["A.java": "one\ntwo\n"])
        defer { try? FileManager.default.removeItem(atPath: root) }

        let changes = GitLineChangeProvider().changes(
            forFileAt: "A.java", repositoryRoot: root, bufferContents: "one\nnew\ntwo\n"
        )
        #expect(changes == [GitLineChange(line: 2, kind: .added)], "실제로 받은 것: \(changes)")
    }

    /// 버퍼가 저장소와 같으면 표시가 없어야 한다. 되돌리기로 원래대로 만든 경우다.
    @Test("버퍼가 저장소와 같으면 표시가 없다")
    func noMarksWhenTheBufferMatchesHead() throws {
        let root = try makeRepository(["A.java": "one\ntwo\n"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(
            GitLineChangeProvider().changes(
                forFileAt: "A.java", repositoryRoot: root, bufferContents: "one\ntwo\n"
            ).isEmpty
        )
    }

    /// 저장소에 없는 새 파일을 편집 중이면 모든 줄이 추가다.
    @Test("추적 안 되는 파일의 버퍼는 전부 추가다")
    func untrackedBufferIsAllAdded() throws {
        let root = try makeRepository(["A.java": "one\n"])
        defer { try? FileManager.default.removeItem(atPath: root) }

        let changes = GitLineChangeProvider().changes(
            forFileAt: "New.java", repositoryRoot: root, bufferContents: "x\ny\n"
        )
        #expect(changes.map(\.line) == [1, 2])
        #expect(changes.allSatisfy { $0.kind == .added })
    }

    /// 저장소가 아니면 버퍼가 있어도 표시가 없다.
    @Test("저장소가 아니면 버퍼가 있어도 빈 목록이다")
    func nonRepositoryStaysEmpty() throws {
        let root = NSTemporaryDirectory() + "plainbuf-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(
            GitLineChangeProvider().changes(
                forFileAt: "A.java", repositoryRoot: root, bufferContents: "x\n"
            ).isEmpty
        )
    }
}
