import Testing
import AppKit
@testable import CodeNavigatorAppKit

/// Whether the editor ever tells anyone which appearance it is drawing in (REQ-016 AC-6).
///
/// The palette chain is only as good as its first link. `SyntaxPaletteWiringTests` proves the
/// model resends when it is told the appearance changed; that proof is worth nothing if the view
/// never tells it. This is the same shape as the mouse defect found earlier in this increment —
/// every layer correct, and no one calling the first one.
@MainActor
@Suite("에디터 외형 보고 — 뷰가 실제로 알리는가 (REQ-016 AC-6)")
struct EditorAppearanceReportingTests {

    private func makeWindow(_ view: NSView, appearance: NSAppearance.Name) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.frame = window.contentView!.bounds
        window.contentView!.addSubview(view)
        return window
    }

    @MainActor
    private final class AppearanceBox {
        var reported: [AppearanceScheme] = []
    }

    @Test("창에 붙는 순간 외형을 알린다 — 다크로 태어나도 라이트로 시작하지 않는다")
    func mountingReportsTheAppearance() {
        // `viewDidChangeEffectiveAppearance` 는 외형이 *바뀔 때* 온다. 처음부터 다크인 창에
        // 태어난 뷰에는 안 올 수 있고, 그러면 첫 팔레트가 라이트로 나간 채 사용자가 시스템
        // 테마를 건드릴 때까지 그대로 있는다.
        let view = EditorGridNSView()
        let box = AppearanceBox()
        view.onAppearanceChange = { box.reported.append(AppearanceScheme($0)) }

        _ = makeWindow(view, appearance: .darkAqua)

        #expect(!box.reported.isEmpty, "마운트했는데 아무것도 안 알렸다 — 팔레트가 외형을 못 따라간다")
        #expect(box.reported.last == .dark, "다크 창에 붙었는데 \(String(describing: box.reported.last)) 로 알렸다")
    }

    @Test("라이트 창에서는 라이트로 알린다")
    func aLightWindowReportsLight() {
        // 위 테스트만 있으면 "항상 .dark 를 반환한다"는 구현도 통과한다.
        let view = EditorGridNSView()
        let box = AppearanceBox()
        view.onAppearanceChange = { box.reported.append(AppearanceScheme($0)) }

        _ = makeWindow(view, appearance: .aqua)

        #expect(box.reported.last == .light)
    }

    /// 여기서는 `viewDidChangeEffectiveAppearance()` 를 **직접 부르지 않는다.** 창의 외형을
    /// 바꾸기만 하고, 그것만으로 보고가 오는지를 본다 — 사용자가 시스템 테마를 바꿀 때 실제로
    /// 일어나는 일이 그것이기 때문이다. 직접 부르면 "내가 부른 함수가 동작한다"만 확인하게
    /// 되고, **AppKit 이 그 함수를 부르는가**라는 정작 중요한 질문은 안 물은 채로 통과한다.
    /// (첫 판이 그렇게 돼 있었고, 보고가 두 번 온 덕에 드러났다.)
    @Test("시스템이 외형을 바꾸면 AppKit 이 알아서 알린다")
    func aSystemAppearanceChangeIsReportedWithoutBeingAsked() {
        let view = EditorGridNSView()
        let box = AppearanceBox()
        let window = makeWindow(view, appearance: .aqua)
        view.onAppearanceChange = { box.reported.append(AppearanceScheme($0)) }
        #expect(box.reported.isEmpty, "구독을 마운트 뒤에 걸었으니 여기서는 비어 있어야 한다")

        window.appearance = NSAppearance(named: .darkAqua)

        #expect(!box.reported.isEmpty, "외형이 바뀌었는데 아무 보고도 없다 — 팔레트가 따라가지 못한다")
        #expect(box.reported.allSatisfy { $0 == .dark }, "실제 보고: \(box.reported)")
    }
}
