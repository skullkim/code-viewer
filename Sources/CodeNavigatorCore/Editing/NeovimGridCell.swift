/// One character cell of the editor grid.
struct NeovimGridCell: Equatable {
    var text: String
    var highlightIdentifier: Int

    static let blank = NeovimGridCell(text: " ", highlightIdentifier: 0)
}
