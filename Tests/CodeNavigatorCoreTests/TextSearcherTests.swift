import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-008 AC-1 (리터럴 + 미리보기) · AC-2 (잘못된 정규식은 에러) ·
///         AC-3 (제외 대상 미노출) · AC-4 (상한과 안내)
@Suite("TextSearcher")
struct TextSearcherTests {

    private func search(
        in fixture: TemporaryProjectFixture,
        for query: String,
        mode: TextSearchMode = .literal
    ) throws -> TextSearchResult {
        let scan = try ProjectScanner().scan(rootPath: fixture.rootURL)
        return try TextSearcher().search(
            query: query,
            mode: mode,
            filePaths: scan.filePaths,
            rootPath: fixture.rootURL
        )
    }

    // 리터럴 검색.

    @Test("리터럴 일치를 파일·라인·미리보기와 함께 돌려준다")
    func findsLiteralMatchesWithPreview() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "val a = 1\nval needle = 2\n")

        let result = try search(in: fixture, for: "needle")

        #expect(result.items.map(\.path) == ["src/App.kt"])
        #expect(result.items.map(\.line) == [2])
        #expect(result.items.first?.previewText == "val needle = 2")
    }

    @Test("한글이 섞인 줄에서 강조 구간이 UTF-16 오프셋으로 나온다")
    func matchRangesAreUtf16OffsetsOnHangulLine() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "    val 한글 = \"needle\"\n")

        let result = try search(in: fixture, for: "needle")

        // 트림된 미리보기 기준: v0 a1 l2 ␠3 한4 글5 ␠6 =7 ␠8 "9 n10 … e15
        #expect(result.items.first?.previewText == "val 한글 = \"needle\"")
        #expect(result.items.first?.matchRanges == [MatchRange(start: 10, end: 16)])
    }

    @Test("리터럴 모드에서 정규식 메타문자는 글자 그대로다")
    func literalModeTreatsMetacharactersLiterally() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "value.map(x)\nvalueXmap(x)\n")

        let result = try search(in: fixture, for: "value.map(")

        #expect(result.items.map(\.line) == [1])
    }

    @Test("대소문자를 구분한다")
    func searchIsCaseSensitive() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "Needle\nneedle\n")

        let result = try search(in: fixture, for: "needle")

        #expect(result.items.map(\.line) == [2])
    }

    @Test("한 줄에 여러 번 일치하면 항목은 하나, 강조 구간은 여럿이다")
    func repeatedMatchesOnOneLineShareOneItem() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "Target Target\n")

        let result = try search(in: fixture, for: "Target")

        #expect(result.items.count == 1)
        #expect(result.items.first?.matchRanges == [
            MatchRange(start: 0, end: 6),
            MatchRange(start: 7, end: 13),
        ])
    }

    // 정규식 검색.

    @Test("정규식 모드가 패턴으로 일치시킨다")
    func regularExpressionModeMatchesByPattern() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "fun compute() {}\nval x = 1\n")

        let result = try search(in: fixture, for: #"fun\s+\w+"#, mode: .regularExpression)

        #expect(result.items.map(\.line) == [1])
        #expect(result.items.first?.matchRanges == [MatchRange(start: 0, end: 11)])
    }

    @Test("정규식 일치 구간도 UTF-16 오프셋으로 나온다")
    func regularExpressionRangesAreUtf16Offsets() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "val x = 값값값\n")

        let result = try search(in: fixture, for: "값+", mode: .regularExpression)

        #expect(result.items.first?.matchRanges == [MatchRange(start: 8, end: 11)])
    }

    @Test("잘못된 정규식은 빈 결과가 아니라 에러다")
    func invalidRegularExpressionThrows() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "anything\n")

        // SC-6: "([unclosed"는 "결과 없음"이 아니라 "잘못된 정규식"으로 보고되어야 한다.
        #expect(throws: NavigatorError.self) {
            try search(in: fixture, for: "([unclosed", mode: .regularExpression)
        }
    }

    // 제외·정렬·상한.

    @Test("제외 대상은 결과에 나오지 않는다")
    func excludedFilesNeverAppear() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write(".gitignore", contents: "generated/\n")
        fixture.write("src/App.kt", contents: "needle\n")
        fixture.write("node_modules/pkg/index.js", contents: "needle\n")
        fixture.write("generated/Output.kt", contents: "needle\n")
        fixture.write(".hidden.kt", contents: "needle\n")

        let result = try search(in: fixture, for: "needle")

        #expect(result.items.map(\.path) == ["src/App.kt"])
    }

    @Test("이진 파일은 훑지 않는다")
    func binaryFilesAreSkipped() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "needle\n")
        let binaryURL = fixture.rootURL.appendingPathComponent("assets/blob.bin")
        try FileManager.default.createDirectory(
            at: binaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x00, 0x01] + Array("needle".utf8)).write(to: binaryURL)

        let result = try search(in: fixture, for: "needle")

        #expect(result.items.map(\.path) == ["src/App.kt"])
    }

    @Test("결과가 경로 다음 라인 순으로 정렬된다")
    func resultsAreSortedByPathThenLine() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/b.kt", contents: "needle\nx\nneedle\n")
        fixture.write("src/a.kt", contents: "x\nneedle\n")

        let result = try search(in: fixture, for: "needle")

        #expect(result.items.map { "\($0.path):\($0.line)" } == ["src/a.kt:2", "src/b.kt:1", "src/b.kt:3"])
    }

    @Test("정확히 상한만큼이면 잘리지 않는다")
    func exactlyAtLimitIsNotTruncated() throws {
        let fixture = TemporaryProjectFixture()
        let limit = TextSearcher.resultLimit
        fixture.write("src/Many.kt", contents: String(repeating: "needle\n", count: limit))

        let result = try search(in: fixture, for: "needle")

        #expect(result.items.count == limit)
        #expect(result.total == limit)
        #expect(result.truncated == false)
        #expect(result.limit == limit)
    }

    @Test("상한을 넘으면 상한까지만 담고 잘렸다고 알린다")
    func beyondLimitIsTruncated() throws {
        let fixture = TemporaryProjectFixture()
        let limit = TextSearcher.resultLimit
        fixture.write("src/Many.kt", contents: String(repeating: "needle\n", count: limit + 1))

        let result = try search(in: fixture, for: "needle")

        #expect(result.items.count == limit)
        #expect(result.truncated == true)
        #expect(result.total == limit + 1)
    }

    @Test("일치가 없으면 빈 결과로 성공한다")
    func noMatchesYieldEmptyResult() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "nothing here\n")

        let result = try search(in: fixture, for: "needle")

        #expect(result.items.isEmpty)
        #expect(result.total == 0)
        #expect(result.truncated == false)
    }

    @Test("빈 질의는 아무것도 찾지 않는다")
    func emptyQueryFindsNothing() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "needle\n")

        #expect(try search(in: fixture, for: "").items.isEmpty)
    }
}
