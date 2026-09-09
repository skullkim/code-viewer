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

    private func arguments(root: String = "/tmp/project") -> [String] {
        NeovimEditorSession.launchArguments(projectRoot: root, quote: { "'\($0)'" })
    }

    /// `--clean` 은 강조와 함께 **키맵도** 버린다. 사용자가 `gd` 를 직접 매핑해 뒀으면
    /// 존중한다는 규칙이 깨져 테스트 다섯 개가 빨개졌다. 강조는 다른 방법으로 잡는다 —
    /// colorscheme 이 바뀔 때마다 우리 것을 다시 심는다(`NeovimHighlightScript`).
    @Test("설정은 읽되 --clean 으로 통째로 버리지는 않는다")
    func keepsTheUserConfiguration() {
        #expect(
            arguments().contains("--clean") == false,
            "--clean 은 사용자 키맵까지 버린다 — 불만은 강조에 한정된다"
        )
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
