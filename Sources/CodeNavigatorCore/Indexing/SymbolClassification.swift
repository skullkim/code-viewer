import CodeNavigatorContract

/// What a classifier decided about one syntax node: its kind, declared name, and the node whose
/// position the symbol is reported at.
struct SymbolClassification {
    let kind: SymbolKind
    let name: String
    /// The node the reported line comes from — the name, not the declaration, so annotations and
    /// modifiers above a declaration do not drag the reported position up with them.
    let anchor: SwiftTreeSitterNode
}

/// Maps one syntax node to a symbol, or to nothing.
///
/// Returning `nil` means "this node is not a symbol" — an anonymous declaration, a constructor
/// we deliberately exclude, or a node type the language does not index. It never means an error.
protocol SymbolClassifying {
    func classify(node: SyntaxNodeAccess) -> SymbolClassification?
}

/// The node plus the reader that can inspect it, so classifiers stay free of tree-sitter setup.
struct SyntaxNodeAccess {
    let node: SwiftTreeSitterNode
    let reader: SyntaxNodeReader

    var nodeType: String { node.nodeType ?? "" }
}
