import Testing
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Compact form for asserting extraction results.
private struct ExtractedSymbol: Hashable, CustomStringConvertible {
    let kind: SymbolKind
    let name: String
    let line: Int

    var description: String { "\(kind.rawValue) \(name) @\(line)" }
}

private func extractSymbols(from source: String, path: String) -> [ExtractedSymbol] {
    let extractor = SymbolExtractor()
    return extractor.extract(source: source, path: path).map {
        ExtractedSymbol(kind: $0.kind, name: $0.name, line: $0.line)
    }
}

/// Line number of the first line containing `snippet`, 1-based — so expectations stay correct
/// when the fixture text is edited.
private func lineContaining(_ snippet: String, in source: String) -> Int {
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
    for (index, line) in lines.enumerated() where line.contains(snippet) {
        return index + 1
    }
    Issue.record("픽스처에 '\(snippet)' 가 없다")
    return -1
}

@Suite("SymbolExtractor — Kotlin")
struct KotlinSymbolExtractorTests {
    let source = """
    package com.example.demo

    import org.springframework.stereotype.Service

    @Service
    class SymbolIndexHolder(private val rootPath: String) {
        private val entries = mutableMapOf<String, Int>()
        var count: Int = 0

        fun addSymbol(name: String): Boolean {
            return true
        }

        suspend fun loadAll(): List<String> = entries.keys.toList()

        companion object {
            const val MAX = 100
            fun empty() = SymbolIndexHolder("")
        }
    }

    interface SymbolSource {
        fun symbols(): List<String>
        val id: String
    }

    enum class SymbolKindLabel {
        CLASS, INTERFACE;

        fun lower() = name.lowercase()
    }

    object Registry {
        fun get(): Int = 1
    }

    data class Symbol(val name: String, val kind: SymbolKindLabel)

    typealias Handler = (String) -> Unit

    fun String.slug(): String = lowercase()
    """

    @Test("클래스·인터페이스·enum·object·함수·프로퍼티·타입별칭이 모두 추출된다")
    func extractsEveryKotlinSymbolKind() {
        let symbols = extractSymbols(from: source, path: "Sample.kt")
        let byKind = Dictionary(grouping: symbols, by: \.kind).mapValues { $0.map(\.name) }

        #expect(byKind[.class]?.contains("SymbolIndexHolder") == true)
        #expect(byKind[.class]?.contains("Symbol") == true)
        #expect(byKind[.interface]?.contains("SymbolSource") == true)
        #expect(byKind[.enum]?.contains("SymbolKindLabel") == true)
        #expect(byKind[.object]?.contains("Registry") == true)
        #expect(byKind[.function]?.contains("addSymbol") == true)
        #expect(byKind[.function]?.contains("loadAll") == true)
        #expect(byKind[.function]?.contains("slug") == true)
        #expect(byKind[.property]?.contains("entries") == true)
        #expect(byKind[.property]?.contains("count") == true)
        #expect(byKind[.typeAlias]?.contains("Handler") == true)
    }

    @Test("interface는 class로 잘못 분류되지 않는다")
    func doesNotMisclassifyInterfaceAsClass() {
        let symbols = extractSymbols(from: source, path: "Sample.kt")
        #expect(symbols.contains(ExtractedSymbol(
            kind: .interface, name: "SymbolSource", line: lineContaining("interface SymbolSource", in: source))))
        #expect(!symbols.contains(where: { $0.name == "SymbolSource" && $0.kind == .class }))
    }

    @Test("enum class는 enum으로 분류된다")
    func classifiesEnumClassAsEnum() {
        let symbols = extractSymbols(from: source, path: "Sample.kt")
        #expect(!symbols.contains(where: { $0.name == "SymbolKindLabel" && $0.kind == .class }))
    }

    @Test("주 생성자의 프로퍼티는 추출되지 않는다 — 본문 프로퍼티만 인덱싱한다")
    func skipsPrimaryConstructorProperties() {
        let symbols = extractSymbols(from: source, path: "Sample.kt")
        #expect(!symbols.contains(where: { $0.name == "rootPath" }))
    }

    @Test("라인 번호는 1부터 시작하고, 어노테이션이 아니라 선언 줄을 가리킨다")
    func reportsOneBasedDeclarationLines() {
        let symbols = extractSymbols(from: source, path: "Sample.kt")
        let holder = symbols.first { $0.name == "SymbolIndexHolder" && $0.kind == .class }
        // @Service 가 바로 윗줄에 있다. 선언 노드는 어노테이션에서 시작하므로,
        // 이름 노드를 기준으로 잡지 않으면 어노테이션 줄로 밀린다.
        #expect(holder?.line == lineContaining("class SymbolIndexHolder", in: source))
    }

    @Test("어노테이션이 붙어도 시그니처는 선언 줄이다 — '@Service'가 시그니처가 되지 않는다")
    func signatureShowsTheDeclarationNotTheAnnotation() {
        let extractor = SymbolExtractor()
        let symbols = extractor.extract(source: source, path: "Sample.kt")
        let holder = symbols.first { $0.name == "SymbolIndexHolder" && $0.kind == .class }
        #expect(holder?.signature.hasPrefix("class SymbolIndexHolder") == true)
    }
}

@Suite("SymbolExtractor — Java")
struct JavaSymbolExtractorTests {
    let source = """
    package com.example;

    public class SymbolIndexHolder implements SymbolSource {
        private final String rootPath;

        public SymbolIndexHolder(String rootPath) {
            this.rootPath = rootPath;
        }

        public boolean addSymbol(String name) {
            return true;
        }
    }

    interface SymbolSource {
        List<String> symbols();
    }

    enum SymbolKindLabel { CLASS, INTERFACE }

    record Point(int x, int y) {}
    """

    @Test("클래스·인터페이스·enum·record·메서드·필드가 추출된다")
    func extractsEveryJavaSymbolKind() {
        let symbols = extractSymbols(from: source, path: "Sample.java")
        let byKind = Dictionary(grouping: symbols, by: \.kind).mapValues { $0.map(\.name) }

        #expect(byKind[.class]?.contains("SymbolIndexHolder") == true)
        #expect(byKind[.class]?.contains("Point") == true)
        #expect(byKind[.interface]?.contains("SymbolSource") == true)
        #expect(byKind[.enum]?.contains("SymbolKindLabel") == true)
        #expect(byKind[.function]?.contains("addSymbol") == true)
        #expect(byKind[.property]?.contains("rootPath") == true)
    }

    @Test("생성자는 클래스와 같은 이름의 함수로 추출된다")
    func extractsConstructorAsFunctionNamedAfterTheClass() {
        let symbols = extractSymbols(from: source, path: "Sample.java")
        let named = symbols.filter { $0.name == "SymbolIndexHolder" }
        #expect(named.contains { $0.kind == .class })
        #expect(named.contains { $0.kind == .function })
    }
}

@Suite("SymbolExtractor — TypeScript / JavaScript")
struct EcmaScriptSymbolExtractorTests {
    let typeScriptSource = """
    export interface SymbolSource { symbols(): string[]; }
    export type Handler = (value: string) => void;
    export enum SymbolKindLabel { Class, Interface }

    export abstract class BaseIndex {
      abstract load(): void;
    }

    export class SymbolIndexHolder extends BaseIndex {
      private entries = new Map<string, number>();
      public limit: number = 500;
      handler = (value: string) => value.length;
      constructor(private root: string) { super(); }
      addSymbol(name: string): boolean { return true; }
      load(): void {}
      *walk(): Generator<string> { yield "a"; }
    }

    export const arrowFunction = (value: number) => value + 1;
    export const RESULT_LIMIT = 500;
    function topLevel() { const innerValue = 2; return innerValue; }
    declare function ambient(x: number): void;
    """

    let javaScriptSource = """
    export class Widget {
      count = 0;
      render = () => this.count;
      constructor(n) { this.count = n; }
      update(n) { this.count = n; }
    }
    export const make = (n) => new Widget(n);
    export const LIMIT = 42;
    function* generate() { yield 1; }
    function plain() { const hidden = 1; return hidden; }
    """

    @Test("TS의 모든 선언 종류가 추출된다")
    func extractsEveryTypeScriptSymbolKind() {
        let symbols = extractSymbols(from: typeScriptSource, path: "sample.ts")
        let byKind = Dictionary(grouping: symbols, by: \.kind).mapValues { $0.map(\.name) }

        #expect(byKind[.interface]?.contains("SymbolSource") == true)
        #expect(byKind[.typeAlias]?.contains("Handler") == true)
        #expect(byKind[.enum]?.contains("SymbolKindLabel") == true)
        #expect(byKind[.class]?.contains("BaseIndex") == true)
        #expect(byKind[.class]?.contains("SymbolIndexHolder") == true)
        #expect(byKind[.function]?.contains("addSymbol") == true)
        #expect(byKind[.function]?.contains("walk") == true)
        #expect(byKind[.function]?.contains("ambient") == true)
        #expect(byKind[.property]?.contains("entries") == true)
        #expect(byKind[.property]?.contains("limit") == true)
    }

    @Test("constructor는 심볼이 아니다 — 검색 노이즈를 만들지 않는다")
    func excludesConstructorFromTypeScriptAndJavaScript() {
        #expect(!extractSymbols(from: typeScriptSource, path: "sample.ts").contains { $0.name == "constructor" })
        #expect(!extractSymbols(from: javaScriptSource, path: "sample.js").contains { $0.name == "constructor" })
    }

    @Test("화살표 함수를 담은 상수·필드는 function, 값 상수는 property다")
    func classifiesArrowFunctionValuesAsFunctions() {
        let typeScript = extractSymbols(from: typeScriptSource, path: "sample.ts")
        #expect(typeScript.contains { $0.name == "arrowFunction" && $0.kind == .function })
        #expect(typeScript.contains { $0.name == "RESULT_LIMIT" && $0.kind == .property })
        #expect(typeScript.contains { $0.name == "handler" && $0.kind == .function })

        let javaScript = extractSymbols(from: javaScriptSource, path: "sample.js")
        #expect(javaScript.contains { $0.name == "render" && $0.kind == .function })
        #expect(javaScript.contains { $0.name == "count" && $0.kind == .property })
        #expect(javaScript.contains { $0.name == "make" && $0.kind == .function })
        #expect(javaScript.contains { $0.name == "LIMIT" && $0.kind == .property })
    }

    @Test("블록 스코프 지역 변수는 인덱싱하지 않는다 — 모듈 레벨만")
    func skipsBlockScopedVariables() {
        #expect(!extractSymbols(from: typeScriptSource, path: "sample.ts").contains { $0.name == "innerValue" })
        #expect(!extractSymbols(from: javaScriptSource, path: "sample.js").contains { $0.name == "hidden" })
    }

    @Test("JS 파일은 TSX 문법으로 파싱되어도 결과가 동일하다")
    func parsesJavaScriptWithTheTsxGrammar() {
        let symbols = extractSymbols(from: javaScriptSource, path: "sample.js")
        #expect(symbols.contains { $0.name == "Widget" && $0.kind == .class })
        #expect(symbols.contains { $0.name == "update" && $0.kind == .function })
        #expect(symbols.contains { $0.name == "generate" && $0.kind == .function })
        #expect(symbols.contains { $0.name == "plain" && $0.kind == .function })
    }
}

@Suite("SymbolExtractor — 견고성과 시그니처")
struct SymbolExtractorRobustnessTests {

    @Test("미지원 확장자는 빈 결과를 돌려주고 에러를 내지 않는다")
    func returnsEmptyForUnsupportedExtensions() {
        #expect(extractSymbols(from: "# 제목\n본문", path: "README.md").isEmpty)
        #expect(extractSymbols(from: "key: value", path: "config.yaml").isEmpty)
    }

    @Test("완전히 깨진 소스에서도 죽지 않는다")
    func survivesCompletelyBrokenSource() {
        let symbols = extractSymbols(from: " {{{{ %%% ]]]] class @@@@ ", path: "broken.kt")
        #expect(symbols.count >= 0)
    }

    @Test("일부만 깨진 소스에서 정상 부분의 심볼은 추출된다")
    func extractsHealthySymbolsFromPartiallyBrokenSource() {
        let source = """
        fun healthyFunction(): Int = 1

        ((((broken @@@ ]]]]
        """
        let symbols = extractSymbols(from: source, path: "partial.kt")
        #expect(symbols.contains { $0.name == "healthyFunction" && $0.kind == .function })
    }

    @Test("빈 소스는 빈 결과다")
    func returnsEmptyForEmptySource() {
        #expect(extractSymbols(from: "", path: "Empty.kt").isEmpty)
    }

    @Test("시그니처는 선언 줄을 다듬은 것이고 120 UTF-16 코드 유닛으로 잘린다")
    func buildsTrimmedAndTruncatedSignature() {
        let longName = String(repeating: "가", count: 200)
        let source = "        fun shortOne(): Int = 1\nval \(longName) = 1\n"
        let extractor = SymbolExtractor()
        let symbols = extractor.extract(source: source, path: "Sig.kt")

        let shortOne = symbols.first { $0.name == "shortOne" }
        #expect(shortOne?.signature == "fun shortOne(): Int = 1")

        let long = symbols.first { $0.name.hasPrefix("가") }
        #expect(long?.signature.utf16.count == 120)
    }

    // 한글은 문자열 리터럴·주석·백틱 식별자로 나타난다. 문법(tree-sitter-kotlin 1.1.0)이
    // 백틱 없는 한글 식별자는 받지 않으므로, 실제 코드에 나오는 형태로 UTF-16 경로를 검증한다.
    @Test("한글 문자열 리터럴이 섞여도 이름·시그니처가 깨지지 않는다")
    func keepsKoreanStringLiteralsIntact() {
        let source = "fun 한글없는이름ASCII(): String = \"한글 값입니다\"\n"
            .replacingOccurrences(of: "한글없는이름ASCII", with: "loadMessage")
        let extractor = SymbolExtractor()
        let symbols = extractor.extract(source: source, path: "Korean.kt")
        #expect(symbols.first?.name == "loadMessage")
        #expect(symbols.first?.signature == "fun loadMessage(): String = \"한글 값입니다\"")
    }

    @Test("한글 주석 위의 선언이 정상 추출된다")
    func extractsDeclarationsBelowKoreanComments() {
        let source = """
        // 심볼 인덱스를 만든다
        fun buildIndex(): Int = 1
        """
        let extractor = SymbolExtractor()
        let symbols = extractor.extract(source: source, path: "Comment.kt")
        #expect(symbols.first?.name == "buildIndex")
        #expect(symbols.first?.line == 2)
    }

    @Test("백틱으로 감싼 한글 식별자가 추출된다 — 코틀린 테스트 함수명 관용구")
    func extractsBacktickQuotedKoreanIdentifiers() {
        let source = "fun `인덱스를 만든다`() = 1\n"
        let extractor = SymbolExtractor()
        let symbols = extractor.extract(source: source, path: "Backtick.kt")
        #expect(symbols.first?.name == "`인덱스를 만든다`")
    }

    @Test("경로는 그대로 보존된다")
    func preservesTheGivenPath() {
        let extractor = SymbolExtractor()
        let symbols = extractor.extract(source: "class A", path: "src/main/kotlin/A.kt")
        #expect(symbols.first?.path == "src/main/kotlin/A.kt")
    }
}
