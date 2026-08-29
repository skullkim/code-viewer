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

    private func drawGlyphs(
        _ frame: GridFrame,
        in context: CGContext,
        geometry: GridGeometry,
        viewSize: CGSize,
        metrics: CellMetrics
    ) {
        context.textMatrix = .identity

        for batch in GlyphBatcher.batches(for: frame.cells) {
            var glyphs: [CGGlyph] = []
            var positions: [CGPoint] = []
            glyphs.reserveCapacity(batch.cells.count)
            positions.reserveCapacity(batch.cells.count)

            for cell in batch.cells {
                guard let glyph = glyphCache.glyph(for: cell.character, bold: batch.isBold, metrics: metrics) else {
                    continue
                }
                glyphs.append(glyph)
                positions.append(CGPoint(
                    x: geometry.originX(ofColumn: cell.column),
                    y: geometry.topEdgeY(ofRow: cell.row, inViewHeight: viewSize.height) + metrics.baselineOffset
                ))
            }

            guard !glyphs.isEmpty else { continue }
            context.setFillColor(batch.foreground.cgColor)
            let font = (batch.isBold ? metrics.boldFont : metrics.font) as CTFont
            CTFontDrawGlyphs(font, glyphs, positions, glyphs.count, context)
        }
    }
}

extension RGBColor {
    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
