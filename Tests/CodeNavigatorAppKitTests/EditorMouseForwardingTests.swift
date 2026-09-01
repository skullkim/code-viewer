import Testing
import AppKit
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Whether a click in the editor ever becomes a mouse event Neovim can see.
///
/// The engine side is already covered live (`NeovimMouseInputTests` starts a real Neovim and
/// watches the cursor move), and it passes. That is exactly why it is not enough: those tests
/// begin at `session.sendMouse`, which is *after* the part that has to happen first. Nothing
/// asserted that the view ever calls `onMouse` — the same shape as REQ-010 AC-1, where every
/// key test passed while the shipped application delivered no keys at all because no one was
/// ever made first responder.
///
/// So these tests start where the user starts: an `NSEvent` on a real view in a real window.
@MainActor
@Suite("에디터 마우스 전달 — 클릭이 실제로 Neovim 으로 나가는가 (REQ-017)")
struct EditorMouseForwardingTests {

    private let viewSize = NSSize(width: 400, height: 300)

    private func makeWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: viewSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: NSRect(origin: .zero, size: viewSize))
        view.frame = window.contentView!.bounds
        window.contentView!.addSubview(view)
        return window
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    /// Builds a view already wired to a recorder, because an unwired view is the bug under test.
    private func makeRecordingView() -> (EditorGridNSView, @MainActor () -> [EditorMouseEvent]) {
        let view = EditorGridNSView()
        let box = EventBox()
        view.onMouse = { box.events.append($0) }
        return (view, { box.events })
    }

    @MainActor
    private final class EventBox {
        var events: [EditorMouseEvent] = []
    }

    @Test("클릭하면 press 가 Neovim 으로 나간다 (REQ-017 AC-1)")
    func clickingForwardsAPress() {
        let (view, events) = makeRecordingView()
        let window = makeWindow(view)
        guard let click = mouseEvent(.leftMouseDown, at: NSPoint(x: 40, y: 200), in: window) else {
            Issue.record("합성 마우스 이벤트를 만들지 못했다")
            return
        }

        view.mouseDown(with: click)

        // 빈 배열에서 저절로 참이 되는 단언을 쓰지 않는다 — 먼저 비지 않았음을 고정한다.
        #expect(events().count == 1, "클릭이 이벤트를 하나도 못 만들면 그 아래 계층은 전부 무의미하다")
        #expect(events().first?.action == .press)
        #expect(events().first?.button == .left)
    }

    @Test("누름 → 끌기 → 놓기가 순서대로 나간다 (REQ-017 AC-2)")
    func aDragForwardsPressThenDragThenRelease() {
        let (view, events) = makeRecordingView()
        let window = makeWindow(view)
        let path: [(NSEvent.EventType, NSPoint)] = [
            (.leftMouseDown, NSPoint(x: 40, y: 200)),
            (.leftMouseDragged, NSPoint(x: 80, y: 160)),
            (.leftMouseUp, NSPoint(x: 80, y: 160)),
        ]

        for (type, point) in path {
            guard let event = mouseEvent(type, at: point, in: window) else {
                Issue.record("합성 마우스 이벤트를 만들지 못했다")
                return
            }
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .leftMouseDragged: view.mouseDragged(with: event)
            default: view.mouseUp(with: event)
            }
        }

        #expect(events().count == 3, "세 단계가 다 나가지 않으면 선택이 만들어지지 않는다")
        #expect(events().map(\.action) == [.press, .drag, .release])
    }

    /// 좌표 공식을 테스트가 다시 쓰면 구현이 틀려도 같이 틀린다. 그래서 방향만 고정한다 —
    /// 뒤집힌 축은 공식을 몰라도 드러난다. `isFlipped` 가 false 라 y 는 아래에서 잰다.
    @Test("화면 위를 클릭하면 위쪽 행, 아래를 클릭하면 아래쪽 행이다 (REQ-017 AC-1)")
    func theVerticalAxisIsNotUpsideDown() {
        let (view, events) = makeRecordingView()
        let window = makeWindow(view)
        let nearTop = NSPoint(x: 40, y: viewSize.height - 4)
        let nearBottom = NSPoint(x: 40, y: 4)

        for point in [nearTop, nearBottom] {
            guard let click = mouseEvent(.leftMouseDown, at: point, in: window) else {
                Issue.record("합성 마우스 이벤트를 만들지 못했다")
                return
            }
            view.mouseDown(with: click)
        }

        #expect(events().count == 2)
        guard events().count == 2 else { return }
        #expect(events()[0].row == 0, "화면 맨 위 클릭은 0행이어야 한다")
        #expect(events()[0].row < events()[1].row, "축이 뒤집히면 위를 눌렀는데 아래로 간다")
    }

    @Test("왼쪽을 클릭하면 0열, 오른쪽을 클릭하면 더 큰 열이다 (REQ-017 AC-1)")
    func theHorizontalAxisRunsLeftToRight() {
        let (view, events) = makeRecordingView()
        let window = makeWindow(view)

        for x in [CGFloat(1), CGFloat(200)] {
            guard let click = mouseEvent(.leftMouseDown, at: NSPoint(x: x, y: 150), in: window) else {
                Issue.record("합성 마우스 이벤트를 만들지 못했다")
                return
            }
            view.mouseDown(with: click)
        }

        #expect(events().count == 2)
        guard events().count == 2 else { return }
        #expect(events()[0].column == 0, "맨 왼쪽 클릭은 0열이어야 한다")
        #expect(events()[0].column < events()[1].column)
    }
}
