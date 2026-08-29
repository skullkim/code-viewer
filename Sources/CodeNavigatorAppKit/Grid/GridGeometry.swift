import CoreGraphics

/// Maps between the editor view's pixels and Neovim's grid cells.
///
/// Every position here is arithmetic on the cell size. The measurements behind ADR-0101
/// showed a laid-out line placing column N up to eleven cells away from `N * cellWidth`
/// on combining marks, so the text engine is never consulted about where a column is.
public struct GridGeometry: Sendable, Hashable {
    public let columns: Int
    public let rows: Int
    public let cellSize: CGSize

    public init(viewSize: CGSize, cellSize: CGSize) {
        self.cellSize = cellSize
        // Partial cells are dropped rather than drawn clipped, and the grid never reaches
        // zero: Neovim refuses a zero-sized UI, so a degenerate view must still ask for
        // one cell rather than take the session down.
        self.columns = max(1, Int((viewSize.width / cellSize.width).rounded(.down)))
        self.rows = max(1, Int((viewSize.height / cellSize.height).rounded(.down)))
    }

    public func originX(ofColumn column: Int) -> CGFloat {
        CGFloat(column) * cellSize.width
    }

    /// The y coordinate of a row's top edge, in a bottom-left origin coordinate space.
    public func topEdgeY(ofRow row: Int, inViewHeight viewHeight: CGFloat) -> CGFloat {
        viewHeight - CGFloat(row + 1) * cellSize.height
    }

    /// The rectangle covering `cellWidth` cells starting at a position.
    ///
    /// `cellWidth` is the run's own cell count, not its character count: a double-width
    /// character occupies two cells and a cursor drawn one cell wide would cover half a
    /// glyph.
    public func cellRect(row: Int, column: Int, cellWidth: Int, inViewHeight viewHeight: CGFloat) -> CGRect {
        CGRect(
            x: originX(ofColumn: column),
            y: topEdgeY(ofRow: row, inViewHeight: viewHeight),
            width: cellSize.width * CGFloat(cellWidth),
            height: cellSize.height
        )
    }

    /// Whether a resize changed the grid, as opposed to only the pixels around it.
    ///
    /// Neovim redraws everything when the UI is resized, so one request per dragged pixel
    /// would be wasteful; only a change in cell counts is worth reporting.
    public func differsInGridSize(from other: GridGeometry) -> Bool {
        columns != other.columns || rows != other.rows
    }
}
