import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// The highlight ranges on a reference must come from the same boundary rule that decided the
/// line is a reference at all. If the view re-found the name itself, it would highlight text the
/// engine deliberately refused to match.
@Suite("Reference.matchRanges — 강조 위치", .serialized)
struct ReferenceHighlightTests {

    private func search(_ fixture: TemporaryProjectFixture, for name: String) async throws -> ReferenceSearchResult {
        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)
        return try await engine.references(to: name)
    }

    @Test("강조 구간이 미리보기 안의 심볼 위치를 가리킨다")
    func rangesPointAtTheSymbolInsideThePreview() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Use.kt", contents: "val holder = SymbolIndex()\n")

        let result = try await search(fixture, for: "SymbolIndex")
        let reference = try #require(result.references.first)
        let range = try #require(reference.matchRanges.first)

        let preview = Array(reference.previewText.utf16)
        let highlighted = String(decoding: preview[range.start..<range.end], as: UTF16.self)
        #expect(highlighted == "SymbolIndex")
    }

    @Test("한 줄에 두 번 나오면 구간이 둘이다 — 항목은 하나지만 강조는 여럿")
    func reportsEveryOccurrenceOnTheLine() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Use.kt", contents: "val a = Widget(); val b = Widget()\n")

        let result = try await search(fixture, for: "Widget")
        let reference = try #require(result.references.first)
        #expect(result.references.count == 1)
        #expect(reference.matchRanges.count == 2)

        let preview = Array(reference.previewText.utf16)
        for range in reference.matchRanges {
            #expect(String(decoding: preview[range.start..<range.end], as: UTF16.self) == "Widget")
        }
    }

    @Test("부분 단어는 강조되지 않는다 — 엔진이 매치하지 않은 것을 UI가 칠하지 않는다")
    func doesNotHighlightPartialWords() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Use.kt", contents: """
        val one = buildIndex()
        val two = Index()
        """)

        let result = try await search(fixture, for: "Index")
        // buildIndex 줄은 아예 참조가 아니다.
        #expect(result.references.count == 1)
        let reference = try #require(result.references.first)
        #expect(reference.line == 2)

        let preview = Array(reference.previewText.utf16)
        let range = try #require(reference.matchRanges.first)
        #expect(String(decoding: preview[range.start..<range.end], as: UTF16.self) == "Index")
    }

    @Test("한글이 앞에 붙은 식별자는 강조되지 않는다 — 경계 규칙이 한 벌이다")
    func koreanPrefixedIdentifierIsNotHighlighted() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Use.kt", contents: """
        val one = 사용자Index()
        val two = Index()
        """)

        let result = try await search(fixture, for: "Index")
        #expect(result.references.count == 1)
        #expect(result.references.first?.line == 2)
    }

    @Test("한글이 섞인 줄에서도 강조 구간이 정확하다 — UTF-16 환산")
    func rangesAreCorrectOnKoreanLines() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Use.kt", contents: "// 심볼 인덱스를 만든다\nval 값 = SymbolIndex()\n")

        let result = try await search(fixture, for: "SymbolIndex")
        let reference = try #require(result.references.first)
        let range = try #require(reference.matchRanges.first)

        let preview = Array(reference.previewText.utf16)
        #expect(String(decoding: preview[range.start..<range.end], as: UTF16.self) == "SymbolIndex")
    }

    @Test("선행 공백이 있어도 구간이 미리보기 기준으로 보정된다")
    func rangesShiftWithTrimmedIndentation() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Use.kt", contents: "        val holder = SymbolIndex()\n")

        let result = try await search(fixture, for: "SymbolIndex")
        let reference = try #require(result.references.first)
        let range = try #require(reference.matchRanges.first)

        #expect(reference.previewText.hasPrefix("val holder"))
        let preview = Array(reference.previewText.utf16)
        #expect(String(decoding: preview[range.start..<range.end], as: UTF16.self) == "SymbolIndex")
    }

    @Test("정의 위치도 강조 구간을 갖는다")
    func definitionSitesAlsoCarryRanges() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Widget.kt", contents: "class Widget\n")

        let result = try await search(fixture, for: "Widget")
        let definition = try #require(result.references.first { $0.isDefinition })
        #expect(definition.matchRanges.isEmpty == false)
    }
}
