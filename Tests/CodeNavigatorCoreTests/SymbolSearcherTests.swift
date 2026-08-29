import Testing
import CodeNavigatorContract
@testable import CodeNavigatorCore

private func definition(_ name: String, path: String = "src/A.kt", line: Int = 1) -> SymbolDefinition {
    SymbolDefinition(name: name, kind: .class, path: path, line: line, signature: "class \(name)")
}

@Suite("SymbolSearcher — 관련도 순위와 상한")
struct SymbolSearcherTests {
    private let searcher = SymbolSearcher()

    @Test("완전 일치가 접두 일치보다, 접두 일치가 흩어진 일치보다 앞선다")
    func ranksExactAbovePrefixAboveScattered() {
        // 입력 순서도, 그 역순도 기대 결과와 다르게 배치한다. 그래야 "정렬했다"가 아니라
        // "관련도로 정렬했다"를 검증한다.
        let results = searcher.search(query: "sym", in: [
            definition("SymbolIndexHolder"),
            definition("sym"),
            definition("SystemMemoryManager"),
        ])

        #expect(results.map(\.definition.name) == ["sym", "SymbolIndexHolder", "SystemMemoryManager"])
    }

    @Test("점수가 같으면 짧은 이름이 앞선다")
    func breaksScoreTiesByShorterName() {
        let results = searcher.search(query: "index", in: [
            definition("indexBuilderFactory"),
            definition("indexer"),
        ])

        #expect(results.map(\.definition.name) == ["indexer", "indexBuilderFactory"])
    }

    @Test("점수와 이름 길이가 같으면 경로 다음 라인 순으로 안정 정렬된다")
    func breaksRemainingTiesByPathThenLine() {
        let results = searcher.search(query: "widget", in: [
            definition("Widget", path: "src/b.kt", line: 5),
            definition("Widget", path: "src/a.kt", line: 9),
            definition("Widget", path: "src/a.kt", line: 2),
        ])

        #expect(results.map { "\($0.definition.path):\($0.definition.line)" }
            == ["src/a.kt:2", "src/a.kt:9", "src/b.kt:5"])
    }

    @Test("매치되지 않는 심볼은 결과에 없다")
    func excludesNonMatchingSymbols() {
        let results = searcher.search(query: "zzz", in: [definition("SymbolIndexHolder")])
        #expect(results.isEmpty)
    }

    @Test("빈 질의는 빈 결과다")
    func emptyQueryReturnsNothing() {
        #expect(searcher.search(query: "", in: [definition("Anything")]).isEmpty)
    }

    @Test("결과는 상한을 넘지 않는다")
    func capsResultCount() {
        let definitions = (0..<200).map { definition("Item\($0)", path: "src/File\($0).kt") }
        let results = searcher.search(query: "item", in: definitions)

        #expect(results.count == SymbolSearcher.resultLimit)
    }

    @Test("하이라이트 구간이 함께 온다")
    func carriesHighlightRanges() throws {
        let results = searcher.search(query: "sym", in: [definition("SymbolIndexHolder")])
        let ranges = try #require(results.first?.matchRanges)
        #expect(ranges == [MatchRange(start: 0, end: 3)])
    }
}
