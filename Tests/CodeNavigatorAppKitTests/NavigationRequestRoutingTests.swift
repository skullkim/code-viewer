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

    /// `gd` 는 정의로 가고 **동시에** 사용처를 나열한다.
    ///
    /// 사용자의 원래 요구가 그것이었다 — *"gd 를 누르면 해당 클래스를 사용하는 모든 곳이
    /// 나열됐으면 좋겠어."* 처음엔 `gd`=정의 / `gr`=참조로 갈랐는데, 참조 패널이 정의를
    /// `정의` 배지로 함께 싣기 때문에 한 번에 둘 다 보이는 편이 요구에 맞다.
    @Test("gd 는 참조를 나열한 뒤 정의로 간다")
    func goToDefinitionAlsoListsUsages() {
        #expect(EditorNavigationRequest.goToDefinition.menuCommands == [.showReferences, .goToDefinition])
    }

    /// 순서가 뒤집히면 조용히 틀린다: `goToDefinition` 이 먼저면 커서가 정의로 옮겨간 뒤에
    /// 참조를 찾게 되고, 커서 아래 낱말이 달라지는 경우 다른 심볼의 참조가 나온다.
    @Test("참조를 먼저 뽑는다 — 커서가 움직이기 전에")
    func usagesAreResolvedBeforeTheCursorMoves() {
        let commands = EditorNavigationRequest.goToDefinition.menuCommands
        let references = try? #require(commands.firstIndex(of: .showReferences))
        let definition = try? #require(commands.firstIndex(of: .goToDefinition))
        #expect(references != nil && definition != nil)
        if let references, let definition {
            #expect(references < definition, "정의로 먼저 가면 참조를 다른 낱말로 찾는다")
        }
    }

    @Test("gr 은 참조만 나열한다 — gd 와 뭉개지지 않았다")
    func findReferencesStaysReferencesOnly() {
        #expect(EditorNavigationRequest.findReferences.menuCommands == [.showReferences])
        #expect(
            EditorNavigationRequest.goToDefinition.menuCommands
                != EditorNavigationRequest.findReferences.menuCommands,
            "두 요청이 같은 동작으로 뭉개졌다"
        )
    }

    @Test("모든 요청이 최소 한 명령으로 간다 — 빈 목록은 조용한 무동작이다")
    func everyRequestRoutesSomewhere() {
        #expect(EditorNavigationRequest.allCases.count == 2, "요청 종류가 늘면 이 표도 늘어야 한다")
        for request in EditorNavigationRequest.allCases {
            #expect(!request.menuCommands.isEmpty, "\(request) 가 아무 명령으로도 안 간다")
        }
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
