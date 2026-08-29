import CodeNavigatorContract
import SwiftTreeSitter
import TreeSitterKotlin
import TreeSitterJava
import TreeSitterTypeScript
import TreeSitterTSX

/// Extracts symbol definitions from source text with tree-sitter.
///
/// One instance owns its parsers, and tree-sitter parsers are not safe to share across tasks.
/// The type is therefore deliberately **not** `Sendable`: create one per task when indexing in
/// parallel. Grammar pointers themselves are immutable static data and are safe to share.
///
/// Nothing here throws. A file that cannot be parsed yields no symbols and never stops the
/// indexing run (REQ-002 AC-4). tree-sitter's error recovery means a partially broken file still
/// yields the symbols in its healthy parts.
final class SymbolExtractor {
    private var parsersByGrammar: [GrammarKind: Parser] = [:]

    init() {}

    func extract(source: String, path: String) -> [SymbolDefinition] {
        guard let language = SourceLanguage(filePath: path),
              let grammar = GrammarKind(filePath: path),
              let parser = parser(for: grammar),
              let tree = parser.parse(source),
              let root = tree.rootNode
        else {
            return []
        }

        let reader = SyntaxNodeReader(source: source)
        let classifier = Self.classifier(for: language)
        let sourceLines = source.split(separator: "\n", omittingEmptySubsequences: false)

        var symbols: [SymbolDefinition] = []
        collect(
            node: root,
            reader: reader,
            classifier: classifier,
            sourceLines: sourceLines,
            path: path,
            into: &symbols
        )
        return symbols
    }

    // MARK: - Traversal

    /// Walks named children depth-first. Classification never prunes the walk: a class that
    /// produced a symbol still has its methods and properties visited.
    private func collect(
        node: SwiftTreeSitterNode,
        reader: SyntaxNodeReader,
        classifier: SymbolClassifying,
        sourceLines: [Substring],
        path: String,
        into symbols: inout [SymbolDefinition]
    ) {
        let access = SyntaxNodeAccess(node: node, reader: reader)
        if let classification = classifier.classify(node: access) {
            let zeroBasedRow = Int(classification.anchor.pointRange.lowerBound.row)
            let signatureLine = zeroBasedRow < sourceLines.count ? sourceLines[zeroBasedRow] : ""
            symbols.append(
                SymbolDefinition(
                    name: classification.name,
                    kind: classification.kind,
                    path: path,
                    line: zeroBasedRow + 1,
                    signature: PreviewTextBuilder.makeSignature(line: String(signatureLine))
                )
            )
        }

        for child in reader.namedChildren(of: node) {
            collect(
                node: child,
                reader: reader,
                classifier: classifier,
                sourceLines: sourceLines,
                path: path,
                into: &symbols
            )
        }
    }

    // MARK: - Parsers

    private func parser(for grammar: GrammarKind) -> Parser? {
        if let existing = parsersByGrammar[grammar] { return existing }

        let parser = Parser()
        do {
            try parser.setLanguage(Language(language: Self.grammarPointer(for: grammar)))
        } catch {
            return nil
        }
        parsersByGrammar[grammar] = parser
        return parser
    }

    private static func grammarPointer(for grammar: GrammarKind) -> OpaquePointer {
        switch grammar {
        case .kotlin: return tree_sitter_kotlin()
        case .java: return tree_sitter_java()
        case .typescript: return tree_sitter_typescript()
        case .tsx: return tree_sitter_tsx()
        }
    }

    private static func classifier(for language: SourceLanguage) -> SymbolClassifying {
        switch language {
        case .kotlin: return KotlinSymbolClassifier()
        case .java: return JavaSymbolClassifier()
        case .typescript, .javascript: return EcmaScriptSymbolClassifier()
        }
    }
}
