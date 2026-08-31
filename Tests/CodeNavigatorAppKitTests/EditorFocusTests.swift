import Testing
import AppKit
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Whether typing reaches Neovim at all.
///
/// Every other test around the grid calls `keyDown(with:)` directly, which answers "does
/// the view translate a key correctly" — not "is the view ever asked". It was not: nothing
/// in the application called `makeFirstResponder`, so the window stayed first responder,
/// `keyDown` was never invoked, and REQ-010 AC-1 did not hold in the shipped application
/// while the suite was green. These tests go through AppKit: a real window, a real
/// responder, a real `sendEvent`.
@MainActor
@Suite("에디터 키보드 포커스 — 타이핑이 실제로 Neovim 에 닿는가 (REQ-010 AC-1)")
struct EditorFocusTests {

    private func makeWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.frame = window.contentView!.bounds
        window.contentView!.addSubview(view)
        return window
    }

    private func keyDownEvent(_ characters: String) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        )
    }

    /// Parks the keyboard on an unrelated field, so a test starts from "not focused".
    private func giveTheKeyboardToSomethingElse(in window: NSWindow) {
        let field = NSTextField(frame: NSRect(x: 200, y: 200, width: 100, height: 24))
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
    }

    private func mouseDownEvent(in window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 20, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    @Test("에디터를 클릭하면 키보드 포커스를 가져온다 (REQ-010 AC-1)")
    func clickingTheEditorTakesKeyboardFocus() {
        // AppKit does not make a plain NSView first responder on click. Text views do it
        // for themselves; this one has to ask. Without the ask, every keystroke went to the
        // window and Neovim saw nothing — measured live before the fix.
        let view = EditorGridNSView()
        let window = makeWindow(view)
        // The keyboard starts somewhere else on purpose. Clicking an editor that already
        // holds focus proves nothing — and it is the real case: the user types a query,
        // then clicks back into the code.
        giveTheKeyboardToSomethingElse(in: window)
        guard let click = mouseDownEvent(in: window) else {
            Issue.record("합성 마우스 이벤트를 만들지 못했다")
            return
        }

        view.mouseDown(with: click)

        #expect(window.firstResponder === view, "클릭해도 포커스를 안 가져오면 타이핑이 Neovim 에 닿지 않는다")
    }

    @Test("포커스를 받은 에디터는 창이 보낸 키를 Neovim 으로 넘긴다 (REQ-010 AC-1)")
    func aFocusedEditorForwardsKeysTheWindowDelivers() {
        // Sent through the window, not by calling keyDown directly, so that a responder
        // that is never made first responder fails here.
        var forwarded: [String] = []
        let view = EditorGridNSView()
        view.onKey = { forwarded.append($0) }
        let window = makeWindow(view)
        window.makeFirstResponder(view)

        guard let event = keyDownEvent("i") else {
            Issue.record("합성 키 이벤트를 만들지 못했다")
            return
        }
        window.sendEvent(event)

        #expect(forwarded == ["i"], "창이 보낸 키가 에디터를 거쳐 나가지 않았다")
    }

    @Test("코디네이터가 에디터 차례라고 하면 등장 시 키보드를 가져간다 (REQ-010 AC-1)")
    func theEditorTakesTheKeyboardOnAppearanceWhenItIsItsTurn() {
        let view = EditorGridNSView()
        view.shouldOwnKeyboard = true
        let window = makeWindow(view)

        #expect(window.firstResponder === view)
    }

    @Test("다른 곳이 잡고 있어도 에디터 차례가 되면 되찾는다 (D-6 잔여)")
    func theEditorReclaimsTheKeyboardFromWhoeverHasIt() {
        // The defect this replaced a condition for. The old rule claimed the keyboard only
        // when nobody held it, which could never become true again once a modal's field
        // editor had taken it — so closing the modal left the editor unreachable and even
        // clicking it did not recover. Measured live after ⌘P.
        let view = EditorGridNSView()
        let window = makeWindow(view)
        giveTheKeyboardToSomethingElse(in: window)
        #expect(window.firstResponder !== view, "사전 조건이 성립하지 않으면 되찾기를 잰 게 아니다")

        view.claimKeyboard()

        #expect(window.firstResponder === view, "모달이 놓은 키보드를 에디터가 되찾지 못한다")
    }

    @Test("에디터 차례가 아니면 등장해도 가져가지 않는다")
    func theEditorDoesNotTakeTheKeyboardWhenItIsNotItsTurn() {
        // The safety that used to live in a check on the current responder now lives in the
        // coordinator, so this asserts the view honours that answer rather than second
        // guessing it. Without it, the grid would pull the caret out of the search field on
        // every SwiftUI update.
        let view = EditorGridNSView()
        view.shouldOwnKeyboard = false
        let window = makeWindow(view)

        #expect(window.firstResponder !== view)
    }

    @Test("입력이 막힌 동안에도 포커스는 가져온다")
    func focusIsTakenEvenWhileInputIsBlocked() {
        // The blocked state means "Neovim is not listening", not "the editor is not the
        // place you type". Losing focus here would leave the user with nowhere to type once
        // the session comes back.
        let view = EditorGridNSView()
        view.isInputBlocked = true
        let window = makeWindow(view)
        giveTheKeyboardToSomethingElse(in: window)
        guard let click = mouseDownEvent(in: window) else {
            Issue.record("합성 마우스 이벤트를 만들지 못했다")
            return
        }

        view.mouseDown(with: click)

        #expect(window.firstResponder === view)
    }
}
