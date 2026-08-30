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

    var onKey: ((String) -> Void)?
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
        guard let notation = KeyNotation.notation(for: KeyStroke(event)) else { return }
        onKey?(notation)
    }

    /// Returning false hands Command combinations to the menu bar and lets everything else
    /// fall through to `keyDown`. That single rule is the whole of REQ-011 AC-2: every
    /// Control chord Vim needs reaches Neovim untouched.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        false
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
        window?.makeFirstResponder(self)
        forward(event, action: .press)
    }

    /// Takes the keyboard on appearance, but only if nothing else has claimed it.
    ///
    /// The editor is where typing goes by default, so requiring a click before the first
    /// keystroke would be wrong. The condition is what keeps that from becoming a bug of
    /// its own: SwiftUI updates this view on every frame, and an unconditional grab would
    /// pull the caret out of the symbol-search field mid-query. A window that is its own
    /// first responder is one where nobody has claimed the keyboard.
    func takeFocusIfUnclaimed() {
        guard let window, window.firstResponder === window else { return }
        window.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        takeFocusIfUnclaimed()
    }
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

/// SwiftUI's view of the editor area.
struct EditorGridView: NSViewRepresentable {
    private let frame: GridFrame?
    private let isInputBlocked: Bool
    private let onKey: (String) -> Void
    private let onMouse: (EditorMouseEvent) -> Void
    private let onGridSizeChange: (Int, Int) -> Void

    init(
        frame: GridFrame?,
        isInputBlocked: Bool,
        onKey: @escaping (String) -> Void,
        onMouse: @escaping (EditorMouseEvent) -> Void,
        onGridSizeChange: @escaping (Int, Int) -> Void
    ) {
        self.frame = frame
        self.isInputBlocked = isInputBlocked
        self.onKey = onKey
        self.onMouse = onMouse
        self.onGridSizeChange = onGridSizeChange
    }

    func makeNSView(context: Context) -> EditorGridNSView {
        let view = EditorGridNSView()
        view.onKey = onKey
        view.onMouse = onMouse
        view.onGridSizeChange = onGridSizeChange
        return view
    }

    func updateNSView(_ view: EditorGridNSView, context: Context) {
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

        // The view is often added to its window after `viewDidMoveToWindow` would have
        // been useful, so the claim is retried here. It is conditional, so retrying is
        // harmless once someone holds the keyboard.
        view.takeFocusIfUnclaimed()
    }
}
