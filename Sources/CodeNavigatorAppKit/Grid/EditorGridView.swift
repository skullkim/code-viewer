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

    override func mouseDown(with event: NSEvent) { forward(event, action: .press) }
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
    }
}
