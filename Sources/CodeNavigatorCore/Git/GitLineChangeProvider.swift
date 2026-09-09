import CodeNavigatorContract
import Foundation

/// 한 파일이 저장소의 것과 어떻게 다른지 git 에 묻는다.
///
/// **HEAD 와 견준다.** 스테이지에 올린 것도 아직 안 올린 것도 다 "내가 고친 것" 이라 화면에
/// 보여야 한다 — IntelliJ 도 그렇게 한다. 인덱스와만 견주면 방금 `git add` 한 줄이 표시에서
/// 사라져서, 사용자는 그 변경이 없어진 것으로 읽는다.
///
/// 파싱은 `GitLineChangeParser` 가 한다. 여기는 프로세스만 다룬다 — 그래야 규칙을 진짜
/// 저장소 없이 시험할 수 있다.
public struct GitLineChangeProvider: Sendable {

    /// git 이 오래 걸리면 편집이 그만큼 늦어진다. 큰 저장소의 첫 호출은 인덱스를 읽느라
    /// 느릴 수 있으므로 넉넉히 주되, 무한정 기다리지는 않는다.
    static let timeout: TimeInterval = 5

    public init() {}

    /// - Parameters:
    ///   - relativePath: 저장소 루트 기준 경로.
    ///   - repositoryRoot: `git` 을 돌릴 폴더.
    /// - Returns: 바뀐 줄들. git 이 없거나 저장소가 아니면 빈 목록 — 표시가 없는 것이지
    ///   오류가 아니다.
    /// - Parameter bufferContents: 편집기가 들고 있는 **저장 전** 내용. 주면 디스크가 아니라
    ///   이것을 저장소와 견준다 — 저장하기 전에도 막대가 보여야 하기 때문이다. IntelliJ 가
    ///   타이핑하는 즉시 그리는 것이 이 경로다.
    public func changes(
        forFileAt relativePath: String, repositoryRoot: String, bufferContents: String
    ) -> [GitLineChange] {
        guard run(["rev-parse", "--is-inside-work-tree"], in: repositoryRoot) != nil else {
            return []
        }
        // 저장소에 그 파일이 없으면 통째로 새 것이다. `git show` 가 실패하는 것이 그 신호다.
        guard let committed = run(["show", "HEAD:\(relativePath)"], in: repositoryRoot) else {
            return Self.allLinesAdded(of: bufferContents)
        }

        // 두 내용을 파일로 놓고 `--no-index` 로 견준다. git 이 diff 를 만들게 두는 편이
        // 우리가 알고리즘을 하나 더 갖는 것보다 낫다 — 같은 헝크 형식이라 파서도 그대로다.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("git-buffer-\(UUID().uuidString)")
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
        else {
            return []
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        let headFile = directory.appendingPathComponent("head")
        let bufferFile = directory.appendingPathComponent("buffer")
        guard
            (try? committed.write(to: headFile, atomically: true, encoding: .utf8)) != nil,
            (try? bufferContents.write(to: bufferFile, atomically: true, encoding: .utf8)) != nil
        else {
            return []
        }

        // `--no-index` 는 차이가 있으면 종료 코드 1 을 낸다. 그건 실패가 아니라 답이므로
        // 종료 코드로 판정하는 `run` 을 쓰지 않는다.
        let output = runAllowingDifferences(
            ["diff", "--no-index", "-U0", "--no-color", "--", headFile.path, bufferFile.path],
            in: repositoryRoot
        )
        return GitLineChangeParser.parse(unifiedDiff: output ?? "")
    }

    private static func allLinesAdded(of contents: String) -> [GitLineChange] {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).count
        let effective = contents.hasSuffix("\n") ? lines - 1 : lines
        guard effective > 0 else { return [] }
        return (1...effective).map { GitLineChange(line: $0, kind: .added) }
    }

    public func changes(forFileAt relativePath: String, repositoryRoot: String) -> [GitLineChange] {
        // **저장소인지 먼저 본다.** 이걸 안 보면 저장소가 아닌 폴더에서 `ls-files` 가 실패
        // 하는 것을 "추적 안 되는 파일" 로 읽고, 파일 전체를 새 줄로 칠한다 — 사용자는 손도
        // 안 댄 파일이 통째로 바뀐 것으로 본다. 실제로 그렇게 만들었고 테스트가 잡았다.
        guard run(["rev-parse", "--is-inside-work-tree"], in: repositoryRoot) != nil else {
            return []
        }

        // 추적되지 않는 파일은 `git diff` 가 아무것도 말하지 않는다. 그런 파일은 통째로
        // 새로 생긴 것이므로 모든 줄이 추가다 — 아무 표시도 없으면 사용자는 이 파일이 이미
        // 저장소에 있는 것으로 읽는다.
        if isUntracked(relativePath, repositoryRoot: repositoryRoot) {
            return untrackedChanges(relativePath, repositoryRoot: repositoryRoot)
        }

        let output = run(
            ["diff", "-U0", "--no-color", "--no-ext-diff", "HEAD", "--", relativePath],
            in: repositoryRoot
        )
        guard let output else { return [] }
        return GitLineChangeParser.parse(unifiedDiff: output)
    }

    private func isUntracked(_ relativePath: String, repositoryRoot: String) -> Bool {
        // `--error-unmatch` 는 추적되지 않는 경로에서 0 이 아닌 값을 낸다. 출력이 아니라
        // 종료 코드로 판정하므로 파일 이름에 무엇이 들어 있든 흔들리지 않는다.
        run(["ls-files", "--error-unmatch", "--", relativePath], in: repositoryRoot) == nil
    }

    private func untrackedChanges(_ relativePath: String, repositoryRoot: String) -> [GitLineChange] {
        let full = (repositoryRoot as NSString).appendingPathComponent(relativePath)
        guard let contents = try? String(contentsOfFile: full, encoding: .utf8) else { return [] }
        return Self.allLinesAdded(of: contents)
    }

    /// 종료 코드를 판정에 쓰지 않는 실행. `git diff --no-index` 는 **차이가 있을 때 1** 을
    /// 내는데, 그건 실패가 아니라 답이다.
    private func runAllowingDifferences(_ arguments: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// - Returns: 표준 출력. 종료 코드가 0 이 아니거나 실행 자체가 안 되면 nil.
    private func run(_ arguments: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let output = Pipe()
        process.standardOutput = output
        // 오류 문구를 결과에 섞지 않는다. 섞이면 파서가 그것을 diff 로 읽는다.
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        // 파이프를 먼저 비운다. 큰 diff 는 파이프 버퍼를 채우고, 그러면 git 이 쓰기에서
        // 막혀 영원히 안 끝난다 — `waitUntilExit` 을 먼저 부르면 그대로 교착이다.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
