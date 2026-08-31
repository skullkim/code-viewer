import AppKit
import SwiftUI
import CodeNavigatorContract

/// The AppKit view that draws Neovim's grid and forwards input to it.
///
/// It never asks for a size (`intrinsicContentSize` is unset): the shell decides the
/// layout and this view works out how many cells fit, then tells Neovim. The prototype
/// lost its status bar to a view that grew instead (ADR-0104).
@MainActor
final class EditorGridNSView: NSView {

    var frameToDraw: GridFrame?
    var isInputBlocked = false
    /// What Neovim is doing, so a press can be read as a command or as prose (REQ-014).
    var editorMode: EditorMode = .normal
    var inputMode: InputMode = .vim

    var onKey: ((String) -> Void)?
    /// Tells the coordinator the user clicked here, so the rest of the window agrees.
    var onClaimKeyboard: (() -> Void)?
    var onMouse: ((EditorMouseEvent) -> Void)?
    var onGridSizeChange: ((Int, Int) -> Void)?

    private let renderer = GridRenderer()
    private let metrics = CellMetrics()
    private var lastReportedGeometry: GridGeometry?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    /// The shell owns the layout. Claiming a size here is what let the editor push the
    /// status bar off screen in the prototype.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        guard let frameToDraw else {
            context.setFillColor(NSColor.textBackgroundColor.cgColor)
            context.fill(bounds)
            return
        }
        renderer.draw(frameToDraw, in: context, viewSize: bounds.size, metrics: metrics)
    }

    // MARK: Size

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportGridSizeIfChanged()
    }

    private func reportGridSizeIfChanged() {
        let geometry = GridGeometry(viewSize: bounds.size, cellSize: metrics.size)
        // Neovim redraws everything on resize, so only a change in cell counts is worth
        // reporting — not every pixel of a drag.
        guard lastReportedGeometry.map({ geometry.differsInGridSize(from: $0) }) ?? true else {
            return
        }
        lastReportedGeometry = geometry
        onGridSizeChange?(geometry.columns, geometry.rows)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        // While an overlay is up the session cannot accept input. Dropping keys is chosen
        // over queueing them, so nothing is replayed into a session that may never arrive.
        guard !isInputBlocked else { return }
        // REQ-014 · D-13: the mode picks the path. Insert mode goes through the input
        // context so the IME can combine jamo into syllables — without it the buffer gets
        // `ㅎㅏㄴㄱㅡㄹ` where the user typed `한글` (QA measured 18 bytes on disk instead
        // of 6). Normal and visual translate the physical key instead, because `ㅑ` is not
        // `i` and Vim cannot read it.
        switch EditorKeyInput.route(
            for: KeyStroke(event),
            editorMode: editorMode,
            inputMode: inputMode,
            hasMarkedText: hasMarkedText(),
            latinCharacter: SystemKeyLayout.latinCharacter(forKeyCode:)
        ) {
        case .interpretForComposition:
            interpretKeyEvents([event])

        case .notation(let notation):
            guard !notation.isEmpty else { return }
            onKey?(notation)

        case .commitThenNotation(let notation):
            // Leaving insert mid-composition would throw the syllable away: the user typed
            // `한`, pressed Escape believing it was written, and it never reached the
            // buffer. Commit first, then transition.
            commitMarkedText()
            onKey?(notation)
        }
    }

    /// Returning false hands Command combinations to the menu bar and lets everything else
    /// fall through to `keyDown`. That single rule is the whole of REQ-011 AC-2: every
    /// Control chord Vim needs reaches Neovim untouched.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        false
    }

    // MARK: 조합 (NSTextInputClient)

    /// What the input method is still composing — not in Neovim's buffer yet.
    private var markedText = ""

    /// Sends whatever is being composed and clears it.
    ///
    /// Called before leaving insert mode. Composition holds text the buffer has never seen,
    /// so a transition that does not commit first is a silent loss of exactly the kind this
    /// change exists to remove.
    private func commitMarkedText() {
        guard !markedText.isEmpty else { return }
        let pending = markedText
        markedText = ""
        inputContext?.discardMarkedText()
        onKey?(pending)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        // AppKit does not hand a plain NSView the keyboard on click — text views ask for
        // it themselves, and this view has to do the same. Without the ask the window
        // stayed first responder, `keyDown` was never called, and nothing the user typed
        // reached Neovim (REQ-010 AC-1). Measured live in the built application.
        //
        // This runs even when input is blocked: "Neovim is not listening" is not the same
        // as "this is not where you type", and dropping focus would leave the user with
        // nowhere to type once the session came back.
        onClaimKeyboard?()
        window?.makeFirstResponder(self)
        forward(event, action: .press)
    }

    /// Takes the keyboard, because the coordinator says this is the editor's turn.
    ///
    /// The claim is unconditional by design. An earlier version only claimed when nobody
    /// else held the keyboard, which reads as safe and was the defect: once a modal's field
    /// editor had taken it, "nobody holds it" was never true again, so closing the modal
    /// left the editor unreachable and even clicking it did not recover. Measured live
    /// after ⌘P.
    ///
    /// What keeps this from yanking the caret out of a search field is not a check on the
    /// current responder — it is that the coordinator only says `.editor` when no other
    /// surface owns the keyboard (`KeyboardFocusCoordinator`). The decision moved to where
    /// the application state is, and this view just carries it out.
    func claimKeyboard() {
        guard let window, window.firstResponder !== self else { return }
        window.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if shouldOwnKeyboard {
            claimKeyboard()
        }
    }

    /// Whether the coordinator has given this view the keyboard.
    var shouldOwnKeyboard = true
    override func mouseDragged(with event: NSEvent) { forward(event, action: .drag) }
    override func mouseUp(with event: NSEvent) { forward(event, action: .release) }

    override func scrollWheel(with event: NSEvent) {
        guard !isInputBlocked else { return }
        let action: EditorMouseEvent.Action = event.scrollingDeltaY > 0 ? .wheelUp : .wheelDown
        forward(event, action: action, button: .wheel)
    }

    private func forward(_ event: NSEvent, action: EditorMouseEvent.Action, button: EditorMouseEvent.Button = .left) {
        guard !isInputBlocked else { return }
        let point = convert(event.locationInWindow, from: nil)
        // The view converts pixels to cells because it is the side that knows the cell
        // size; the contract's mouse coordinates are grid cells, like the cursor's.
        let column = max(0, Int(point.x / metrics.size.width))
        let row = max(0, Int((bounds.height - point.y) / metrics.size.height))
        onMouse?(EditorMouseEvent(
            button: button,
            action: action,
            row: row,
            column: column,
            modifiers: KeyStroke(event).neovimModifierNotation
        ))
    }
}

/// Marked as `@preconcurrency` because `NSTextInputClient` is not actor-isolated in the SDK
/// while every call arrives on the main thread — the input method talks to views, and views
/// are main-actor. Declaring it this way keeps the isolation honest rather than scattering
/// `assumeIsolated` through ten methods.
extension EditorGridNSView: @preconcurrency NSTextInputClient {

    /// The composed text, arriving when the input method commits it.
    ///
    /// This is where `한` shows up after `ㅎ`, `ㅏ` and `ㄴ` — one syllable rather than
    /// three jamo. Whatever arrives is forwarded unchanged: the application does not decide
    /// what Korean composes to, the input method does.
    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        markedText = ""
        guard !text.isEmpty else { return }
        onKey?(text)
    }

    /// Text the input method is still working on.
    ///
    /// Deliberately not sent to Neovim: it is not committed, and putting it in the buffer
    /// would leave characters there that the user may still replace or cancel. It is held
    /// so that leaving insert mode can commit it (`commitMarkedText`).
    ///
    /// Nothing draws it yet, so a syllable is invisible while being composed. That is a
    /// real gap and it is recorded as one — it makes typing awkward, not wrong.
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedText = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    }

    func unmarkText() {
        markedText = ""
    }

    func selectedRange() -> NSRange {
        NSRange(location: 0, length: 0)
    }

    func markedRange() -> NSRange {
        markedText.isEmpty
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: 0, length: markedText.utf16.count)
    }

    func hasMarkedText() -> Bool {
        !markedText.isEmpty
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard !markedText.isEmpty else { return nil }
        let clamped = NSRange(location: 0, length: min(range.length, markedText.utf16.count))
        actualRange?.pointee = clamped
        return NSAttributedString(string: markedText)
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.markedClauseSegment, .glyphInfo, .underlineStyle, .underlineColor]
    }

    /// Where the input method puts its candidate window.
    ///
    /// Anchored to the caret rather than the view's origin, so the candidate list does not
    /// cover the line being typed.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let metrics = CellMetrics()
        let row = CGFloat(frameToDraw?.cursor.row ?? 0)
        let column = CGFloat(frameToDraw?.cursor.column ?? 0)
        let caret = NSRect(
            x: column * metrics.size.width,
            y: bounds.height - (row + 1) * metrics.size.height,
            width: metrics.size.width,
            height: metrics.size.height
        )
        return window?.convertToScreen(convert(caret, to: nil)) ?? .zero
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }
}

/// SwiftUI's view of the editor area.
struct EditorGridView: NSViewRepresentable {
    private let frame: GridFrame?
    private let isInputBlocked: Bool
    private let editorMode: EditorMode
    private let inputMode: InputMode
    /// Whether the coordinator says the editor owns the keyboard right now.
    private let ownsKeyboard: Bool
    private let onKey: (String) -> Void
    private let onMouse: (EditorMouseEvent) -> Void
    private let onGridSizeChange: (Int, Int) -> Void
    private let onClaimKeyboard: () -> Void

    init(
        frame: GridFrame?,
        isInputBlocked: Bool,
        editorMode: EditorMode = .normal,
        inputMode: InputMode = .vim,
        ownsKeyboard: Bool = true,
        onKey: @escaping (String) -> Void,
        onMouse: @escaping (EditorMouseEvent) -> Void,
        onGridSizeChange: @escaping (Int, Int) -> Void,
        onClaimKeyboard: @escaping () -> Void = {}
    ) {
        self.editorMode = editorMode
        self.inputMode = inputMode
        self.ownsKeyboard = ownsKeyboard
        self.onClaimKeyboard = onClaimKeyboard
        self.frame = frame
        self.isInputBlocked = isInputBlocked
        self.onKey = onKey
        self.onMouse = onMouse
        self.onGridSizeChange = onGridSizeChange
    }

    func makeNSView(context: Context) -> EditorGridNSView {
        let view = EditorGridNSView()
        view.shouldOwnKeyboard = ownsKeyboard
        view.onClaimKeyboard = onClaimKeyboard
        view.editorMode = editorMode
        view.inputMode = inputMode
        view.onKey = onKey
        view.onMouse = onMouse
        view.onGridSizeChange = onGridSizeChange
        return view
    }

    func updateNSView(_ view: EditorGridNSView, context: Context) {
        view.onClaimKeyboard = onClaimKeyboard
        view.shouldOwnKeyboard = ownsKeyboard
        view.editorMode = editorMode
        view.inputMode = inputMode
        view.onKey = onKey
        view.onMouse = onMouse
        view.onGridSizeChange = onGridSizeChange
        view.isInputBlocked = isInputBlocked

        // Frames are whole pictures, so a changed revision means redraw everything; an
        // unchanged one means there is nothing to do.
        if view.frameToDraw?.revision != frame?.revision {
            view.frameToDraw = frame
            view.needsDisplay = true
        }

        // Retried on every update, which is what makes the keyboard come *back*. The
        // modal closing is a SwiftUI update, so this is the moment the editor reclaims what
        // the modal borrowed — the half that was missing before.
        if ownsKeyboard {
            view.claimKeyboard()
        }
    }
}
