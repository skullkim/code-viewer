import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Whether the palette and the `gd`/`gr` signal actually travel (REQ-016 AC-6, REQ-015).
///
/// `SyntaxPaletteBuilderTests` proves the palette is *built* correctly. That is a different
/// question from whether anyone ever *sends* it — which is the failure this project keeps
/// finding: a correct value with no path out. So these tests assert the calls happen, and the
/// fake counts them.
@MainActor
@Suite("팔레트·네비게이션 배선 — 값이 실제로 나가는가")
struct SyntaxPaletteWiringTests {

    private func makeModel() -> (AppModel, FakeEditorSession) {
        let editor = FakeEditorSession()
        let model = AppModel(
            editorSession: editor,
            workspace: FakeWorkspace(sharedSession: FakeProjectSession()),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (model, editor)
    }

    /// 조건이 설 때까지의 상한. 고정 대기가 아니라 상한이라, 빨리 되면 빨리 끝난다.
    private static let pollLimit = 200
    private static let pollInterval = Duration.milliseconds(5)

    /// 세션이 붙을 때까지 기다린다. `handle(sessionState:)` 가 `Task` 로 팔레트를 보내므로
    /// 같은 턴에서는 아직 도착하지 않았을 수 있다 — 고정 대기 대신 조건으로 기다린다.
    private func waitForPalettes(_ editor: FakeEditorSession, count: Int) async {
        for _ in 0..<Self.pollLimit where editor.appliedSyntaxPalettes.count < count {
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    @Test("세션이 연결되면 팔레트를 보낸다 (REQ-016 AC-3)")
    func connectingSendsThePalette() async {
        let (model, editor) = makeModel()
        #expect(editor.appliedSyntaxPalettes.isEmpty, "시작 전에 이미 보냈다면 뒤의 단언이 무의미하다")

        model.handle(sessionState: .connected)
        await waitForPalettes(editor, count: 1)

        #expect(editor.appliedSyntaxPalettes.count == 1, "연결됐는데 팔레트가 안 나갔다")
        #expect(editor.appliedSyntaxPalettes.first == SyntaxPaletteBuilder.palette(for: .light))
    }

    @Test("재연결마다 다시 보낸다 — 재시작이 테마를 조용히 잃지 않는다")
    func reconnectingResendsThePalette() async {
        // nvim 이 죽고 다시 뜨면 기본색으로 돌아온다. 한 번만 보내는 구현은 여기서만 드러난다.
        let (model, editor) = makeModel()

        model.handle(sessionState: .connected)
        await waitForPalettes(editor, count: 1)
        model.handle(sessionState: .disconnected(reason: "크래시"))
        model.handle(sessionState: .connected)
        await waitForPalettes(editor, count: 2)

        #expect(editor.appliedSyntaxPalettes.count == 2, "재연결 후 팔레트가 다시 안 나갔다")
    }

    @Test("외형이 바뀌면 그 외형의 팔레트를 다시 보낸다 (REQ-016 AC-6)")
    func changingAppearanceResendsTheMatchingPalette() async {
        let (model, editor) = makeModel()

        await model.appearanceChanged(to: .dark)

        #expect(editor.appliedSyntaxPalettes.count == 1)
        #expect(editor.appliedSyntaxPalettes.last == SyntaxPaletteBuilder.palette(for: .dark))
        #expect(
            editor.appliedSyntaxPalettes.last != SyntaxPaletteBuilder.palette(for: .light),
            "다크로 바꿨는데 라이트 색이 나갔다"
        )
    }

    @Test("같은 외형이 다시 와도 보내지 않는다")
    func anUnchangedAppearanceSendsNothing() async {
        // AppKit 은 외형 통지를 여러 번 보낸다. 매번 nvim 왕복을 만들면 편집 중에 튄다.
        let (model, editor) = makeModel()

        await model.appearanceChanged(to: .dark)
        await model.appearanceChanged(to: .dark)

        #expect(editor.appliedSyntaxPalettes.count == 1, "같은 외형에 두 번 보냈다")
    }

    @Test("팔레트 적용이 실패해도 편집은 계속된다 (INV-8)")
    func aFailedPaletteDoesNotStopEditing() async {
        // 강조는 파생물이다. 색을 못 바르는 것과 파일을 못 여는 것은 같은 무게가 아니다.
        let (model, editor) = makeModel()
        editor.paletteError = NavigatorError.editorUnavailable(reason: "테스트")

        await model.applySyntaxPalette()
        try? await editor.sendKeys("ihello")

        #expect(editor.appliedSyntaxPalettes.isEmpty, "실패했는데 기록됐다면 이 테스트는 실패를 안 재고 있다")
        #expect(editor.sentKeys == ["ihello"], "팔레트 실패가 입력까지 막았다")
    }

    @Test("gd / gr 신호가 실제로 앱에 도착한다 (REQ-015 AC-1·2)")
    func navigationRequestsReachTheApplication() async {
        let (model, editor) = makeModel()
        let received = RequestBox()
        model.onNavigationRequest = { received.values.append($0) }
        model.start()
        defer { model.stop() }

        // 구독이 설 때까지 기다린다 — 구독 전에 쏘면 이벤트는 그냥 사라진다(replay 안 함).
        for _ in 0..<Self.pollLimit where received.values.isEmpty {
            editor.emitNavigationRequest(.goToDefinition)
            try? await Task.sleep(for: Self.pollInterval)
        }

        #expect(!received.values.isEmpty, "gd 신호가 앱에 닿지 않았다 — 배선이 없다")
        #expect(received.values.allSatisfy { $0 == .goToDefinition })
    }

    @MainActor
    private final class RequestBox {
        var values: [EditorNavigationRequest] = []
    }
}
