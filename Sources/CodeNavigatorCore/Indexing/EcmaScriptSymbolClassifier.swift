import CodeNavigatorContract

/// Classifies TypeScript, TSX and JavaScript declarations, which share one grammar family.
///
/// Two rules carry most of the weight:
/// - `constructor` is excluded by name. Every class has one, and indexing them means every
///   project has hundreds of identical hits that bury real results.
/// - Variables are indexed only at module level. A `const` inside a function body is a local,
///   not a declaration anyone navigates to.
struct EcmaScriptSymbolClassifier: SymbolClassifying {
    private static let constructorName = "constructor"

    func classify(node access: SyntaxNodeAccess) -> SymbolClassification? {
        let reader = access.reader
        let node = access.node

        switch access.nodeType {
        case "class_declaration", "abstract_class_declaration":
            return reader.declaration(of: node).map { SymbolClassification(kind: .class, name: $0.name, anchor: $0.node) }

        case "interface_declaration":
            return reader.declaration(of: node).map { SymbolClassification(kind: .interface, name: $0.name, anchor: $0.node) }

        case "enum_declaration":
            return reader.declaration(of: node).map { SymbolClassification(kind: .enum, name: $0.name, anchor: $0.node) }

        case "type_alias_declaration":
            return reader.declaration(of: node).map { SymbolClassification(kind: .typeAlias, name: $0.name, anchor: $0.node) }

        case "function_declaration", "generator_function_declaration", "function_signature":
            return reader.declaration(of: node).map { SymbolClassification(kind: .function, name: $0.name, anchor: $0.node) }

        case "method_definition", "method_signature":
            guard let declaration = reader.declaration(of: node),
                  declaration.name != Self.constructorName
            else {
                return nil
            }
            return SymbolClassification(kind: .function, name: declaration.name, anchor: declaration.node)

        case "public_field_definition", "field_definition":
            guard let declaration = reader.declaration(of: node) else { return nil }
            let kind: SymbolKind = reader.valueIsFunction(of: node) ? .function : .property
            return SymbolClassification(kind: kind, name: declaration.name, anchor: declaration.node)

        case "variable_declarator":
            guard isModuleLevel(node), let declaration = reader.declaration(of: node) else { return nil }
            let kind: SymbolKind = reader.valueIsFunction(of: node) ? .function : .property
            return SymbolClassification(kind: kind, name: declaration.name, anchor: declaration.node)

        default:
            return nil
        }
    }

    /// A declarator is module level when its declaration sits directly in the program body,
    /// or in an export statement at the program body.
    private func isModuleLevel(_ declarator: SwiftTreeSitterNode) -> Bool {
        guard let declaration = declarator.parent, let container = declaration.parent else {
            return false
        }
        let containerType = container.nodeType ?? ""
        return containerType == "program" || containerType == "export_statement"
    }
}
