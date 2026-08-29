import CodeNavigatorContract

/// Classifies Java declarations.
///
/// Constructors are indexed as functions named after their class, so a search for the class name
/// finds both the type and the place it is built. Java gives constructors their own node type, so
/// no name-based filtering is involved.
struct JavaSymbolClassifier: SymbolClassifying {
    func classify(node access: SyntaxNodeAccess) -> SymbolClassification? {
        let reader = access.reader
        let node = access.node

        switch access.nodeType {
        case "class_declaration", "record_declaration":
            return reader.declaration(of: node).map { SymbolClassification(kind: .class, name: $0.name, anchor: $0.node) }

        case "interface_declaration":
            return reader.declaration(of: node).map { SymbolClassification(kind: .interface, name: $0.name, anchor: $0.node) }

        case "enum_declaration":
            return reader.declaration(of: node).map { SymbolClassification(kind: .enum, name: $0.name, anchor: $0.node) }

        case "method_declaration", "constructor_declaration":
            return reader.declaration(of: node).map { SymbolClassification(kind: .function, name: $0.name, anchor: $0.node) }

        case "field_declaration":
            guard let declarator = reader.firstNamedChild(ofType: "variable_declarator", in: node),
                  let declaration = reader.declaration(of: declarator)
            else {
                return nil
            }
            return SymbolClassification(kind: .property, name: declaration.name, anchor: declaration.node)

        default:
            return nil
        }
    }
}
