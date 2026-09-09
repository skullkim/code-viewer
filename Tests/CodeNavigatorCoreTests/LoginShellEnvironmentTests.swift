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
