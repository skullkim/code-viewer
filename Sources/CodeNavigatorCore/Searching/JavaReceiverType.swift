import Foundation
import SwiftTreeSitter
import TreeSitterJava

/// Answers one question about a Java source line: **what type is the receiver of this call?**
///
/// Reference search matches names, so `member.getId()` returns every `getId` in the project.
/// Measured on a 463-file repository, `getId` appeared on 670 lines spread over 15 unrelated
/// receiver types — the user looking at a `Member` was handed `Organization`, `Coupon` and a
/// dozen others in the same list. This is what lets the list be narrowed to the type in hand.
///
/// This is **not** a type checker, and it is written not to pretend otherwise. It reads declared
/// types out of the syntax tree and nothing else: no inference, no generics substitution, no
/// following a chain of calls. When the answer is not written down in the file, it says `nil`.
///
/// `nil` is load-bearing. A wrong answer removes a real reference from the list, and the user has
/// no way to discover what went missing. "I don't know" keeps the hit, which costs a line of
/// noise — the cheaper of the two mistakes by a wide margin.
enum JavaReceiverType {

    /// The receiver type of the occurrence of `symbolName` on `line` (1-based), or `nil`.
    ///
    /// Parses on every call. Fine for one question; use `Resolver` when asking a file many, which
    /// is what reference search does — measured, re-parsing per hit cost 1.6s over 670 hits in a
    /// 463-file repository, and the parse is nearly all of it.
    static func resolve(source: String, line: Int, symbolName: String) -> String? {
        Resolver(source: source).receiverType(line: line, symbolName: symbolName)
    }

    /// Holds one file's parse so a file with many hits is parsed once.
    struct Resolver {
        private let source: String
        private let lines: [Substring]
        private let tree: MutableTree?
        private let reader: SyntaxNodeReader

        init(source: String) {
            self.source = source
            self.lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            self.tree = source.isEmpty ? nil : JavaReceiverType.parse(source)
            self.reader = SyntaxNodeReader(source: source)
        }

        func receiverType(line: Int, symbolName: String) -> String? {
            JavaReceiverType.receiverType(
                line: line,
                symbolName: symbolName,
                lines: lines,
                tree: tree,
                reader: reader
            )
        }
    }

    private static func receiverType(
        line: Int,
        symbolName: String,
        lines: [Substring],
        tree: MutableTree?,
        reader: SyntaxNodeReader
    ) -> String? {
        guard !symbolName.isEmpty, line > 0, line <= lines.count else { return nil }

        // The receiver is read from the text of the one line, because that is where it is: a
        // qualified call writes its receiver immediately before the dot. Parsing decides what the
        // receiver *means*; the line decides what it is.
        guard let receiver = receiverName(inLine: String(lines[line - 1]), symbolName: symbolName) else {
            return nil
        }

        guard let root = tree?.rootNode else { return nil }

        switch receiver {
        case .unresolvable:
            return nil
        case .enclosingClass:
            return enclosingTypeName(root: root, reader: reader, line: line)
        case .staticType(let name):
            return name
        case .identifier(let name):
            return declaredType(of: name, root: root, reader: reader, line: line)
        }
    }

    // MARK: - 한 줄에서 수신자 읽기

    private enum Receiver {
        case identifier(String)
        /// `Coupon.of(…)` — 대문자로 시작하는 수신자는 값이 아니라 타입이다.
        case staticType(String)
        /// `getId()` 나 `this.getId()`.
        case enclosingClass
        /// `find(id).getId()` 처럼 수신자가 다른 호출의 결과인 경우.
        case unresolvable
    }

    private static func receiverName(inLine line: String, symbolName: String) -> Receiver? {
        let characters = Array(line)
        let needle = Array(symbolName)

        var index = 0
        while let range = wholeWordRange(of: needle, in: characters, from: index) {
            index = range.upperBound

            // 호출이 아닌 것은 여기서 답할 수 없다. `getId` 라는 단어가 주석이나 문자열에
            // 있을 수도 있고, 그건 수신자가 없는 것이 아니라 **호출이 아닌 것**이다.
            //
            // 메서드 참조(`Coupon::getId`)는 예외다. 뒤에 `(` 가 없지만 수신자는 바로 앞에
            // 적혀 있고, 그것을 못 읽으면 다른 타입의 참조가 "판정 못 함"으로 목록에 남는다.
            var after = range.upperBound
            while after < characters.count, characters[after] == " " { after += 1 }
            let isCall = after < characters.count && characters[after] == "("

            var before = range.lowerBound - 1
            while before >= 0, characters[before] == " " { before -= 1 }
            let isMethodReference = before >= 1
                && characters[before] == ":" && characters[before - 1] == ":"
            guard isCall || isMethodReference else { continue }

            if isMethodReference {
                before -= 2
            } else {
                guard before >= 0, characters[before] == "." else {
                    return .enclosingClass
                }
                before -= 1
            }
            while before >= 0, characters[before] == " " { before -= 1 }
            guard before >= 0 else { return .unresolvable }

            // 수신자가 `)` 로 끝나면 다른 호출의 결과다. 그 타입은 이 줄에 적혀 있지 않다.
            guard characters[before] != ")", characters[before] != "]" else { return .unresolvable }

            var start = before
            while start >= 0, characters[start].isLetter || characters[start].isNumber
                || characters[start] == "_" || characters[start] == "$" {
                start -= 1
            }
            let name = String(characters[(start + 1)...before])
            guard let first = name.first else { return .unresolvable }

            // `a.b.getId()` 처럼 수신자 앞에 또 점이 있으면 `b` 만 보고는 타입을 못 정한다.
            if start >= 0, characters[start] == "." { return .unresolvable }

            if name == "this" || name == "super" { return .enclosingClass }
            return first.isUppercase ? .staticType(name) : .identifier(name)
        }
        return nil
    }

    private static func wholeWordRange(
        of needle: [Character],
        in characters: [Character],
        from start: Int
    ) -> Range<Int>? {
        guard !needle.isEmpty, characters.count >= needle.count else { return nil }
        var index = start
        while index + needle.count <= characters.count {
            if Array(characters[index..<(index + needle.count)]) == needle {
                let beforeIsPartOfWord = index > 0 && isIdentifierCharacter(characters[index - 1])
                let afterIndex = index + needle.count
                let afterIsPartOfWord = afterIndex < characters.count && isIdentifierCharacter(characters[afterIndex])
                if !beforeIsPartOfWord, !afterIsPartOfWord {
                    return index..<afterIndex
                }
            }
            index += 1
        }
        return nil
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "$"
    }

    // MARK: - 트리에서 선언 찾기

    /// 선언은 가까운 것부터 이긴다: 감싸는 메서드 안의 선언 → 감싸는 타입의 필드.
    ///
    /// 파일 전체에서 한 번만 찾으면 다른 메서드의 동명 지역 변수가 새어 들어온다. 그러면
    /// 좁히기가 노이즈를 줄이는 대신 **틀린 타입으로 진짜 참조를 지우는** 도구가 된다.
    private static func declaredType(
        of identifier: String,
        root: Node,
        reader: SyntaxNodeReader,
        line: Int
    ) -> String? {
        let path = nodePath(to: line, from: root)
        for node in path.reversed() where isScope(node) {
            if let type = declaredType(of: identifier, within: node, reader: reader) {
                return type
            }
        }
        return nil
    }

    private static func isScope(_ node: Node) -> Bool {
        switch node.nodeType {
        case "method_declaration", "constructor_declaration", "class_declaration",
             "interface_declaration", "enum_declaration", "record_declaration",
             "block", "for_statement", "enhanced_for_statement", "catch_clause",
             "lambda_expression", "compact_constructor_declaration":
            return true
        default:
            return false
        }
    }

    /// 이 스코프가 **직접** 담고 있는 선언만 본다 — 중첩된 메서드/클래스 안쪽은 다른
    /// 스코프이고, 그 안의 동명 변수는 여기서 보이지 않는다.
    private static func declaredType(of identifier: String, within scope: Node, reader: SyntaxNodeReader) -> String? {
        var found: String?
        walk(scope) { node in
            switch node.nodeType {
            case "local_variable_declaration", "field_declaration", "formal_parameter",
                 "enhanced_for_statement", "catch_formal_parameter", "spread_parameter":
                guard let typeNode = node.child(byFieldName: "type") else { return .keepGoing }
                let declaredNames = declaredIdentifiers(in: node, reader: reader)
                if declaredNames.contains(identifier) {
                    found = baseTypeName(reader.text(of: typeNode))
                    return .stop
                }
                return .keepGoing
            case "method_declaration", "constructor_declaration", "class_declaration",
                 "interface_declaration", "enum_declaration", "record_declaration",
                 "lambda_expression":
                // 다른 스코프의 속을 들여다보지 않는다. 단, 스코프 자신의 파라미터는 본다.
                return node.id == scope.id ? .keepGoing : .skipChildren
            default:
                return .keepGoing
            }
        }
        return found
    }

    private static func declaredIdentifiers(in node: Node, reader: SyntaxNodeReader) -> Set<String> {
        var names: Set<String> = []
        if let nameNode = node.child(byFieldName: "name") {
            names.insert(reader.text(of: nameNode))
        }
        // `int a = 1, b = 2;` 는 declarator 가 여럿이다.
        for child in reader.namedChildren(of: node) where child.nodeType == "variable_declarator" {
            if let nameNode = child.child(byFieldName: "name") {
                names.insert(reader.text(of: nameNode))
            }
        }
        return names
    }

    /// `Optional<Member>` → `Optional`, `Member[]` → `Member`.
    private static func baseTypeName(_ text: String) -> String? {
        let base = text
            .prefix { $0 != "<" && $0 != "[" }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = base.split(separator: ".").last, !last.isEmpty else { return nil }
        return String(last)
    }

    // MARK: - 감싸는 타입

    private static func enclosingTypeName(root: Node, reader: SyntaxNodeReader, line: Int) -> String? {
        for node in nodePath(to: line, from: root).reversed() {
            switch node.nodeType {
            case "class_declaration", "interface_declaration", "enum_declaration", "record_declaration":
                if let nameNode = node.child(byFieldName: "name") {
                    return reader.text(of: nameNode)
                }
            default:
                continue
            }
        }
        return nil
    }

    // MARK: - 트리 걷기

    private enum WalkDecision { case keepGoing, skipChildren, stop }

    private static func walk(_ node: Node, _ visit: (Node) -> WalkDecision) {
        var shouldStop = false
        func step(_ current: Node) {
            guard !shouldStop else { return }
            switch visit(current) {
            case .stop: shouldStop = true; return
            case .skipChildren: return
            case .keepGoing: break
            }
            for index in 0..<current.childCount {
                guard let child = current.child(at: index) else { continue }
                step(child)
                if shouldStop { return }
            }
        }
        step(node)
    }

    /// The chain of nodes from the root down to the deepest one covering `line` (1-based).
    private static func nodePath(to line: Int, from root: Node) -> [Node] {
        let row = UInt32(line - 1)
        var path: [Node] = []
        var current = root
        while true {
            path.append(current)
            var descended = false
            for index in 0..<current.childCount {
                guard let child = current.child(at: index) else { continue }
                if child.pointRange.lowerBound.row <= row, row <= child.pointRange.upperBound.row {
                    current = child
                    descended = true
                    break
                }
            }
            if !descended { return path }
        }
    }

    private static func parse(_ source: String) -> MutableTree? {
        let parser = Parser()
        try? parser.setLanguage(Language(tree_sitter_java()))
        return parser.parse(source)
    }
}
