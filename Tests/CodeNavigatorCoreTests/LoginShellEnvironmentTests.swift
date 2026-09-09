import Testing
import Foundation
@testable import CodeNavigatorCore

/// Finder 로 띄운 앱은 로그인 셸의 `PATH` 를 물려받지 않는다.
///
/// 실측: `launchctl getenv PATH` 는 비어 있고, GUI 앱이 받는 것은
/// `/usr/bin:/bin:/usr/sbin:/sbin` 뿐이다. 그 PATH 로는 homebrew 에 깐 `npm`·`node`·
/// `gradle` 이 전부 "command not found" 다. 터미널에서 앱을 띄우면 셸의 PATH 를 물려받아
/// 되기 때문에 개발 중에는 드러나지 않는다 — 사용자만 겪는다.
@Suite("로그인 셸 환경", .serialized)
struct LoginShellEnvironmentTests {

    @Test("로그인 셸의 PATH 를 받아 온다")
    func readsTheLoginPath() {
        let resolved = LoginShellEnvironment.resolvedPath(shellPath: "/bin/zsh")
        let path = try! #require(resolved)
        #expect(path.contains("/usr/bin"), "받아 온 PATH: \(path)")
        #expect(path.contains(":"), "PATH 는 여러 항목이다: \(path)")
    }

    /// 없는 셸을 주면 조용히 nil — 그때는 물려받은 환경을 그대로 쓴다. 여기서 죽으면
    /// 터미널이 아예 안 뜬다.
    @Test("셸이 없으면 nil 이다")
    func missingShellIsNil() {
        #expect(LoginShellEnvironment.resolvedPath(shellPath: "/그런/셸/없음") == nil)
    }

    /// 물려받은 환경 위에 얹는다. 통째로 갈아 끼우면 사용자가 실행 설정에 적은 값이 사라진다.
    @Test("물려받은 환경의 PATH 만 바꾼다")
    func replacesOnlyThePath() {
        let augmented = LoginShellEnvironment.augment(
            ["PATH": "/usr/bin:/bin", "MY_VALUE": "keep"], with: "/opt/homebrew/bin:/usr/bin:/bin"
        )
        #expect(augmented["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin")
        #expect(augmented["MY_VALUE"] == "keep", "다른 값이 사라졌다")
    }

    /// 로그인 PATH 를 못 받았으면 원래 환경 그대로다.
    @Test("받아 온 PATH 가 없으면 그대로 둔다")
    func keepsTheEnvironmentWhenNothingResolved() {
        let original = ["PATH": "/usr/bin:/bin"]
        #expect(LoginShellEnvironment.augment(original, with: nil) == original)
    }

    /// 실제로 이 기계의 도구를 찾을 수 있어야 한다. 이게 이 기능의 존재 이유다.
    @Test("받아 온 PATH 로 homebrew 도구를 찾을 수 있다")
    func findsToolsThatTheGuiPathCannot() throws {
        let guiPath = "/usr/bin:/bin:/usr/sbin:/sbin"
        let brewTool = "/opt/homebrew/bin/node"
        try #require(
            FileManager.default.isExecutableFile(atPath: brewTool),
            "이 기계에 \(brewTool) 이 없어 이 검사를 할 수 없다"
        )
        #expect(
            !guiPath.split(separator: ":").contains { $0 == "/opt/homebrew/bin" },
            "GUI PATH 에 이미 있으면 이 검사가 아무것도 증명하지 않는다"
        )
        let resolved = try #require(LoginShellEnvironment.resolvedPath(shellPath: "/bin/zsh"))
        #expect(
            resolved.split(separator: ":").contains { $0 == "/opt/homebrew/bin" },
            "로그인 PATH 에 homebrew 가 없다: \(resolved)"
        )
    }
}

/// 셸에서 PATH 를 못 받아도 **도구는 찾아야 한다.**
///
/// 사용자가 다른 컴퓨터에서 `command not found` 를 겪었다. 우리는 로그인 셸에 PATH 를
/// 묻는데, 그 방법은 기계마다 실패할 수 있다:
/// - zsh 는 `-l -c` 에서 `.zshrc` 를 **읽지 않는다.** 대부분 거기에 homebrew 를 넣는다.
/// - fish 는 `$PATH` 가 목록이라 콜론으로 안 나온다.
/// - 프로파일이 인사말을 찍으면 그 글자가 PATH 에 섞인다.
///
/// 그래서 셸 대답에만 기대지 않고, **디스크에 실제로 있는** 흔한 위치를 합친다.
@Suite("PATH 안전망", .serialized)
struct LoginPathFallbackTests {

    @Test("셸에서 못 받아도 흔한 위치가 들어간다")
    func fallsBackToWellKnownDirectories() {
        let path = LoginShellEnvironment.composedPath(shellPath: "/그런/셸/없음")
        let resolved = try! #require(path)
        let entries = Set(resolved.split(separator: ":").map(String.init))
        #expect(entries.contains("/usr/bin"))
        #expect(entries.contains("/bin"))
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin") {
            #expect(entries.contains("/opt/homebrew/bin"), "이 기계에 있는데 안 넣었다: \(resolved)")
        }
    }

    /// 없는 폴더를 넣으면 PATH 만 길어지고 아무 도움이 안 된다.
    @Test("없는 폴더는 넣지 않는다")
    func skipsDirectoriesThatDoNotExist() {
        let resolved = try! #require(LoginShellEnvironment.composedPath(shellPath: "/그런/셸/없음"))
        for entry in resolved.split(separator: ":") {
            #expect(
                FileManager.default.fileExists(atPath: String(entry)),
                "없는 폴더가 들어갔다: \(entry)"
            )
        }
    }

    @Test("같은 폴더를 두 번 넣지 않는다")
    func hasNoDuplicates() {
        let resolved = try! #require(LoginShellEnvironment.composedPath(shellPath: "/bin/zsh"))
        let entries = resolved.split(separator: ":").map(String.init)
        #expect(entries.count == Set(entries).count, "중복: \(entries)")
    }

    /// 셸이 준 것이 앞에 와야 한다. 사용자가 버전을 골라 둔 것이 있으면 그것이 이겨야 한다 —
    /// 우리가 붙인 기본 위치가 앞서면 다른 java 가 잡힌다.
    @Test("셸이 준 항목이 앞에 온다")
    func shellEntriesComeFirst() throws {
        let shellPath = try #require(LoginShellEnvironment.resolvedPath(shellPath: "/bin/zsh"))
        let composed = try #require(LoginShellEnvironment.composedPath(shellPath: "/bin/zsh"))
        let firstFromShell = try #require(shellPath.split(separator: ":").first)
        #expect(composed.hasPrefix(String(firstFromShell)), "합친 PATH: \(composed)")
    }

    /// 프로파일이 인사말을 찍으면 그 글자가 PATH 로 들어온다.
    @Test("PATH 로 안 보이는 대답은 버린다")
    func rejectsOutputThatIsNotAPath() {
        #expect(LoginShellEnvironment.parsePath(fromShellOutput: "안녕하세요\n") == nil)
        #expect(LoginShellEnvironment.parsePath(fromShellOutput: "") == nil)
        // fish 는 목록이라 공백으로 나온다 — 콜론이 없으면 PATH 가 아니다.
        #expect(LoginShellEnvironment.parsePath(fromShellOutput: "/usr/bin /bin") == nil)
        // 인사말이 앞에 붙어도 마지막 줄이 PATH 면 건진다.
        #expect(
            LoginShellEnvironment.parsePath(fromShellOutput: "환영합니다\n/opt/homebrew/bin:/usr/bin")
                == "/opt/homebrew/bin:/usr/bin"
        )
    }
}
