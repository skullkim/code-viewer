import AppKit
import CoreText

/// Draws a `GridFrame` into a graphics context.
///
/// Positions are arithmetic on the cell size — never the text engine's idea of where a
/// column is. Measured on 2026-08-29, a laid-out line put column N up to eleven cells away
/// from `N * cellWidth` on combining marks and nearly three cells away on CJK. Drawing
/// cell by cell removes that failure mode by construction and, batched by font and colour,
/// is also the fastest of the four approaches tried (ADR-0101).
@MainActor
final class GridRenderer {
    private let glyphCache = GlyphCache()

    func draw(_ frame: GridFrame, in context: CGContext, viewSize: CGSize, metrics: CellMetrics) {
        let geometry = GridGeometry(viewSize: viewSize, cellSize: metrics.size)

        context.setFillColor(frame.defaultBackground.cgColor)
        context.fill(CGRect(origin: .zero, size: viewSize))

        drawBackgrounds(frame, in: context, geometry: geometry, viewSize: viewSize)
        drawCursor(frame, in: context, geometry: geometry, viewSize: viewSize)
        drawUnderlines(frame, in: context, geometry: geometry, viewSize: viewSize, metrics: metrics)
        drawGlyphs(frame, in: context, geometry: geometry, viewSize: viewSize, metrics: metrics)
    }

    private func drawBackgrounds(_ frame: GridFrame, in context: CGContext, geometry: GridGeometry, viewSize: CGSize) {
        for run in frame.backgroundRuns {
            context.setFillColor(run.color.cgColor)
            context.fill(geometry.cellRect(
                row: run.row, column: run.startColumn, cellWidth: run.cellWidth, inViewHeight: viewSize.height
            ))
        }
    }

    private func drawCursor(_ frame: GridFrame, in context: CGContext, geometry: GridGeometry, viewSize: CGSize) {
        // The cursor is one of the few things the application draws over Neovim's output.
        // Its width follows the character underneath so it never covers half a syllable.
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor)
        context.fill(geometry.cellRect(
            row: frame.cursor.row,
            column: frame.cursor.column,
            cellWidth: frame.cursor.cellWidth,
            inViewHeight: viewSize.height
        ))
    }

    /// Underlines every cell that carries the trait.
    ///
    /// Drawn from the frame's cells rather than from the glyph batches, because the batcher
    /// drops blanks — they have nothing to draw. An underline is not a glyph: it marks an
    /// extent (a diagnostic range, a search match), and a space inside that extent belongs
    /// to it. Taking underlines from the batches left gaps wherever the range crossed a
    /// space, which a pixel test caught.
    private func drawUnderlines(
        _ frame: GridFrame,
        in context: CGContext,
        geometry: GridGeometry,
        viewSize: CGSize,
        metrics: CellMetrics
    ) {
        for cell in frame.cells where cell.style.isUnderlined {
            let baseline = geometry.topEdgeY(ofRow: cell.row, inViewHeight: viewSize.height) + metrics.baselineOffset
            context.setFillColor(cell.foreground.cgColor)
            context.fill(CGRect(
                x: geometry.originX(ofColumn: cell.column),
                y: baseline + metrics.underlineOffset,
                width: metrics.size.width,
                height: metrics.underlineThickness
            ))
        }
    }

    private func drawGlyphs(
        _ frame: GridFrame,
        in context: CGContext,
        geometry: GridGeometry,
        viewSize: CGSize,
        metrics: CellMetrics
    ) {
        context.textMatrix = .identity

        for batch in GlyphBatcher.batches(for: frame.cells) {
            // Split again by the font that actually resolved each glyph. Most cells use the
            // batch's own face, but a character it cannot draw comes back from a fallback
            // font, and `CTFontDrawGlyphs` takes one font per call — mixing them would draw
            // the fallback's glyph ids out of the wrong font, which is worse than a blank.
            var runsByFont: [FontKey: (font: CTFont, glyphs: [CGGlyph], positions: [CGPoint])] = [:]

            for cell in batch.cells {
                guard let resolved = glyphCache.resolve(cell.character, style: batch.style, metrics: metrics) else {
                    continue
                }
                let position = CGPoint(
                    x: geometry.originX(ofColumn: cell.column),
                    y: geometry.topEdgeY(ofRow: cell.row, inViewHeight: viewSize.height) + metrics.baselineOffset
                )
                let key = FontKey(resolved.font)
                runsByFont[key, default: (resolved.font, [], [])].glyphs.append(resolved.glyph)
                runsByFont[key]?.positions.append(position)
            }

            guard !runsByFont.isEmpty else { continue }
            context.setFillColor(batch.foreground.cgColor)
            for run in runsByFont.values where !run.glyphs.isEmpty {
                CTFontDrawGlyphs(run.font, run.glyphs, run.positions, run.glyphs.count, context)
            }
        }
    }
}

/// Identifies a font for grouping, since `CTFont` is not `Hashable`.
private struct FontKey: Hashable {
    private let name: String
    private let size: CGFloat

    init(_ font: CTFont) {
        self.name = CTFontCopyPostScriptName(font) as String
        self.size = CTFontGetSize(font)
    }
}

extension RGBColor {
    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
