import SwiftTreeSitter

/// Reads text and structure out of a parsed syntax tree.
///
/// The parser is fed UTF-16, so `Node.range` is already an `NSRange` in UTF-16 code units —
/// the same space every contract offset lives in (ADR-0007). No conversion is needed here.
///
/// Classification needs two different child views: `namedChildren` walks grammar rules, while
/// `allChildren` also sees anonymous keyword tokens such as Kotlin's `interface`. Keeping both
/// available is what lets us tell an interface from a class.
struct SyntaxNodeReader {
    private let sourceUTF16: [UInt16]

    init(source: String) {
        self.sourceUTF16 = Array(source.utf16)
    }

    func text(of node: Node) -> String {
        let range = node.range
        guard range.location >= 0, range.length >= 0,
              range.location + range.length <= sourceUTF16.count
        else {
            return ""
        }
        let slice = sourceUTF16[range.location..<(range.location + range.length)]
        return String(decoding: slice, as: UTF16.self)
    }

    func namedChildren(of node: Node) -> [Node] {
        (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
    }

    func allChildren(of node: Node) -> [Node] {
        (0..<node.childCount).compactMap { node.child(at: $0) }
    }

    func hasChild(ofType type: String, in node: Node) -> Bool {
        allChildren(of: node).contains { $0.nodeType == type }
    }

    func firstNamedChild(ofType type: String, in node: Node) -> Node? {
        namedChildren(of: node).first { $0.nodeType == type }
    }

    /// True when the node's `modifiers` child contains the given keyword, for grammars that
    /// express a declaration's flavour as a modifier rather than a distinct node type.
    func modifiers(of node: Node, contain keyword: String) -> Bool {
        guard let modifiers = firstNamedChild(ofType: "modifiers", in: node) else { return false }
        return text(of: modifiers).contains(keyword)
    }

    /// The declared name of a node: its `name` field when the grammar provides one, otherwise
    /// the first identifier-like named child. `nil` means the declaration is anonymous and is
    /// therefore not indexed — we never invent a placeholder name.
    func declarationName(of node: Node) -> String? {
        declaration(of: node)?.name
    }

    /// The declared name together with the node carrying it.
    ///
    /// The name node matters as much as the text: a declaration node starts at its annotations
    /// and modifiers, so anchoring a symbol on the declaration node would report an annotation
    /// line and show `@Service` as the signature. Anchoring on the name lands on the line a
    /// reader would call the declaration.
    func declaration(of node: Node) -> (name: String, node: Node)? {
        if let nameNode = node.child(byFieldName: "name") {
            return (text(of: nameNode), nameNode)
        }
        for child in namedChildren(of: node) where Self.identifierNodeTypes.contains(child.nodeType ?? "") {
            return (text(of: child), child)
        }
        return nil
    }

    /// True when the node's `value` field holds a function, so a constant or field that holds a
    /// lambda is indexed as a function rather than a property.
    func valueIsFunction(of node: Node) -> Bool {
        guard let value = node.child(byFieldName: "value"), let type = value.nodeType else {
            return false
        }
        return type == "arrow_function" || type == "function_expression"
    }

    private static let identifierNodeTypes: Set<String> = [
        "identifier", "simple_identifier", "type_identifier", "property_identifier",
    ]
}
