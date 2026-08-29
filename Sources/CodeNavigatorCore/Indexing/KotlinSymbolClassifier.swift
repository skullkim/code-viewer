import CodeNavigatorContract

/// Classifies Kotlin declarations.
///
/// Kotlin's grammar expresses classes, interfaces and enums with one node type
/// (`class_declaration`), distinguished by an anonymous `interface` keyword child or by an
/// enum body. Properties declared in a class body wrap their name one level deeper, in a
/// `variable_declaration` child.
///
/// Primary-constructor properties are not indexed. They are parameters as much as declarations,
/// and indexing them buries the real declarations under constructor noise.
struct KotlinSymbolClassifier: SymbolClassifying {
    func classify(node access: SyntaxNodeAccess) -> SymbolClassification? {
        let reader = access.reader
        let node = access.node

        switch access.nodeType {
        case "class_declaration":
            guard let declaration = reader.declaration(of: node) else { return nil }
            if reader.hasChild(ofType: "interface", in: node) {
                return SymbolClassification(kind: .interface, name: declaration.name, anchor: declaration.node)
            }
            if reader.hasChild(ofType: "enum_class_body", in: node)
                || reader.modifiers(of: node, contain: "enum") {
                return SymbolClassification(kind: .enum, name: declaration.name, anchor: declaration.node)
            }
            return SymbolClassification(kind: .class, name: declaration.name, anchor: declaration.node)

        case "object_declaration":
            return reader.declaration(of: node).map { SymbolClassification(kind: .object, name: $0.name, anchor: $0.node) }

        case "function_declaration":
            return reader.declaration(of: node).map { SymbolClassification(kind: .function, name: $0.name, anchor: $0.node) }

        case "property_declaration":
            guard let variable = reader.firstNamedChild(ofType: "variable_declaration", in: node),
                  let declaration = reader.declaration(of: variable)
            else {
                return nil
            }
            return SymbolClassification(kind: .property, name: declaration.name, anchor: declaration.node)

        case "type_alias":
            return reader.declaration(of: node).map { SymbolClassification(kind: .typeAlias, name: $0.name, anchor: $0.node) }

        default:
            return nil
        }
    }
}
