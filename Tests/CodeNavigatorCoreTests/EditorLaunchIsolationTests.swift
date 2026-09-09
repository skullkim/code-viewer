import Testing
import Foundation
@testable import CodeNavigatorCore

/// 편집기는 **사용자의 nvim 설정과 무관하게** 떠야 한다.
///
/// 사용자가 겪은 것: "하이라이트가 intellJ랑 다르게 변수명, 함수 이름, 어노테이션 이런게
/// 제대로 안돼, 컴퓨터 마다 기존의 vim 설정이 달라서 그런거 같아."
///
/// 정확한 진단이었다. 우리는 사용자 설정을 그대로 로드했고, 각자의 colorscheme 이 우리가
/// 심은 강조를 덮어썼다. 같은 코드가 기계마다 다르게 보인다.
@Suite("편집기 기동 격리")
struct EditorLaunchIsolationTests {

    private func arguments(
        root: String = "/tmp/project", usesUserConfiguration: Bool = false
    ) -> [String] {
        NeovimEditorSession.launchArguments(
            projectRoot: root, usesUserConfiguration: usesUserConfiguration, quote: { "'\($0)'" }
        )
    }

    /// **기본은 사용자 설정을 안 읽는다.**
    ///
    /// colorscheme 이 바뀔 때 우리 색을 다시 심는 방법을 먼저 썼는데 절반이었다 — 한
    /// 기계에서 맞춰도 다른 기계에서 또 깨졌다. 플러그인은 자기 tree-sitter 설정과 쿼리를
    /// 들고 오고, 늦게 로드되며, 우리가 모르는 이벤트에서 색을 바꾼다. 남의 설정이 무엇을
    /// 할지 우리는 모른다.
    @Test("기본은 사용자 설정을 읽지 않는다")
    func isolatedByDefault() {
        #expect(arguments().contains("--clean"), "설정이 우리 강조를 덮으면 기계마다 달라진다")
    }

    /// 자기 키맵을 쓰고 싶은 사람은 켤 수 있다. 그때는 강조가 그 설정을 따른다.
    @Test("켜면 사용자 설정을 읽는다")
    func honoursTheOptIn() {
        #expect(arguments(usesUserConfiguration: true).contains("--clean") == false)
    }

    /// `--clean` 이 `--cmd` 보다 앞에 와야 한다. 뒤에 오면 그 사이에 설정이 읽힐 자리가 생긴다.
    @Test("--clean 이 먼저 온다")
    func cleanComesFirst() {
        let arguments = arguments()
        let clean = try! #require(arguments.firstIndex(of: "--clean"))
        let cmd = try! #require(arguments.firstIndex(of: "--cmd"))
        #expect(clean < cmd)
    }

    /// 프로젝트 폴더로 들어가는 것은 그대로여야 한다. 이게 빠지면 상대 경로가 전부 어긋난다.
    @Test("프로젝트 폴더로 들어간다")
    func stillChangesIntoTheProject() {
        let arguments = arguments(root: "/tmp/my project")
        let index = arguments.firstIndex(of: "--cmd")
        let cmdIndex = try! #require(index)
        #expect(arguments[cmdIndex + 1] == "cd '/tmp/my project'", "따옴표가 빠지면 공백에서 깨진다")
    }


}
