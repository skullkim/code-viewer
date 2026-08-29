import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-002 AC-3 (미지원 확장자 파일은 인덱싱되지 않지만 **전문 검색 대상에는 포함**된다)
///
/// 이 스위트는 검색 범위가 `scan.filePaths`(전부)인지 `scan.indexableFilePaths`(파싱 가능한 것만)인지를
/// 엔진 수준에서 고정한다. `TextSearcher` 단위 테스트는 파일 목록을 인자로 받으므로 이 구분을 잡지 못한다 —
/// 목록을 고르는 쪽은 `ProjectEngine`이다.
@Suite("ProjectEngine — 검색 범위")
struct ProjectEngineSearchScopeTests {

    private func makeProject() -> TemporaryProjectFixture {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Widget {}\n")
        fixture.write("README.md", contents: "Widget 사용법\n")
        fixture.write("notes.txt", contents: "Widget 메모\n")
        return fixture
    }

    @Test("미지원 확장자 파일도 전문 검색 결과에 나온다")
    func unsupportedExtensionsAreStillSearched() async throws {
        let fixture = makeProject()
        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)

        let result = try await engine.searchText("Widget", mode: .literal)

        #expect(result.items.map(\.path) == ["README.md", "notes.txt", "src/App.kt"])
    }

    @Test("참조 검색도 미지원 확장자 파일을 훑는다")
    func referenceSearchAlsoScansUnsupportedExtensions() async throws {
        let fixture = makeProject()
        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)

        let result = try await engine.references(to: "Widget")

        #expect(result.references.map(\.path) == ["README.md", "notes.txt", "src/App.kt"])
    }

    @Test("그 파일들이 심볼 인덱싱 대상은 아니다")
    func unsupportedExtensionsAreNotIndexed() async throws {
        let fixture = makeProject()
        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)

        // 검색 범위와 인덱싱 범위가 다르다는 것 자체가 REQ-002 AC-3의 내용이다.
        let definitions = await engine.definitions(named: "Widget")

        #expect(definitions.map(\.path) == ["src/App.kt"])
    }
}

@Suite("TextSearchResult.filesSearched — 검색 범위 보고", .serialized)
struct TextSearchFilesSearchedTests {

    @Test("검색한 파일 수를 보고한다")
    func reportsHowManyFilesWereRead() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/A.kt", contents: "val needle = 1")
        fixture.write("src/B.kt", contents: "val other = 2")
        fixture.write("README.md", contents: "문서")
        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)

        let result = try await engine.searchText("needle", mode: .literal)
        #expect(result.items.count == 1)
        // 일치한 파일 수(1)가 아니라 훑은 파일 수(3)다 — 문구가 "M 파일 검색"이기 때문.
        #expect(result.filesSearched == 3)
    }

    @Test("빈 질의는 아무 파일도 읽지 않는다")
    func emptyQueryReadsNothing() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/A.kt", contents: "val needle = 1")
        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)

        let result = try await engine.searchText("", mode: .literal)
        #expect(result.filesSearched == 0)
    }

    @Test("상한에서 멈추면 읽은 파일 수가 전체보다 작다 — 하지 않은 일을 보고하지 않는다")
    func stopsCountingWhenTruncated() async throws {
        let fixture = TemporaryProjectFixture()
        // 첫 파일 하나가 상한을 넘기고, 나머지는 읽히지 않아야 한다.
        fixture.write("src/Flooded.kt", contents: (1...600).map { "val needle\($0) = \($0)" }
            .joined(separator: "\n"))
        for index in 0..<20 {
            fixture.write("src/Untouched\(index).kt", contents: "val needle = 1")
        }
        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)

        let result = try await engine.searchText("needle", mode: .literal)
        #expect(result.truncated)
        #expect(result.filesSearched < 21)
    }
}
