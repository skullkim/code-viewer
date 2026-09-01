import Testing
import AppKit
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// The two translations the `gd`/`gr` path depends on (REQ-015) and the appearance the palette
/// is built for (REQ-016 AC-6).
///
/// Both are one-line mappings, and both fail the same way if written backwards: everything runs,
/// nothing errors, and the user gets the other feature. `gd` opening the reference panel is not
/// a crash — it is a wrong answer delivered confidently.
@Suite("네비게이션 요청·외형 매핑")
struct NavigationRequestRoutingTests {

    @Test("gd 는 정의로, gr 은 참조로 간다 — 뒤집히지 않았다")
    func eachRequestMapsToItsOwnCommand() {
        #expect(EditorNavigationRequest.goToDefinition.menuCommand == .goToDefinition)
        #expect(EditorNavigationRequest.findReferences.menuCommand == .showReferences)
    }

    @Test("두 요청이 서로 다른 명령으로 간다")
    func theTwoRequestsDoNotCollapse() {
        // 둘 다 같은 명령으로 가도 위 테스트는 절반만 실패한다. 여기서 뭉개짐 자체를 막는다.
        let commands = Set(EditorNavigationRequest.allCases.map(\.menuCommand))

        #expect(EditorNavigationRequest.allCases.count == 2, "요청 종류가 늘면 이 표도 늘어야 한다")
        #expect(commands.count == 2, "두 요청이 한 명령으로 뭉개졌다")
    }

    @Test("다크 외형은 다크 팔레트를 부른다")
    func darkAppearanceSelectsTheDarkPalette() {
        let dark = try? #require(NSAppearance(named: .darkAqua))
        #expect(dark.map { AppearanceScheme($0) } == .dark)
    }

    @Test("라이트 외형은 라이트 팔레트를 부른다")
    func lightAppearanceSelectsTheLightPalette() {
        let light = try? #require(NSAppearance(named: .aqua))
        #expect(light.map { AppearanceScheme($0) } == .light)
    }

    /// 이름 비교로 짰다면 여기서 라이트로 떨어진다 — 대비 증가를 켠 다크 모드 사용자만 겪고,
    /// 그 사용자는 자기 화면이 왜 이상한지 말할 방법이 없다.
    @Test("고대비 다크도 다크로 읽는다")
    func theHighContrastDarkVariantIsStillDark() {
        guard let variant = NSAppearance(named: .accessibilityHighContrastDarkAqua) else {
            Issue.record("고대비 다크 외형을 만들지 못했다")
            return
        }

        #expect(AppearanceScheme(variant) == .dark)
    }
}
