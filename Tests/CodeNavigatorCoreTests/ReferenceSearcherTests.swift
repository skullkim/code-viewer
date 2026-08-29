import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-006 AC-1 (사용 위치 + 미리보기) · AC-2 (정의 구분 표시) · AC-4 (참조 0건)
@Suite("ReferenceSearcher")
struct ReferenceSearcherTests {

    private func search(
        in fixture: TemporaryProjectFixture,
        for symbolName: String,
        symbolIndex: SymbolIndex = SymbolIndex()
    ) async throws -> ReferenceSearchResult {
        let scan = try ProjectScanner().scan(rootPath: fixture.rootURL)
        return await ReferenceSearcher().search(
            symbolName: symbolName,
            filePaths: scan.filePaths,
            rootPath: fixture.rootURL,
            symbolIndex: symbolIndex
        )
    }

    // 단어 경계 — 이 기능의 존재 이유다.

    @Test("온전한 토큰만 잡고 부분 단어는 잡지 않는다")
    func matchesWholeTokensOnly() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write(
            "src/Use.kt",
            contents: """
                val value = Index()
                fun buildIndex() {}
                class AlphaIndexer {}
                val underscored = Index_v2
                val digited = Index2
                val hangul = 사용자Index
                """
        )

        let result = try await search(in: fixture, for: "Index")

        #expect(result.references.map(\.line) == [1])
    }

    @Test("구분자로 둘러싸인 이름은 잡는다")
    func matchesNameSurroundedBySeparators() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write(
            "src/Use.kt",
            contents: """
                import com.example.Index
                val call = repository.Index(argument)
                val list = [Index]
                """
        )

        let result = try await search(in: fixture, for: "Index")

        #expect(result.references.map(\.line) == [1, 2, 3])
    }

    @Test("검색어는 정규식이 아니라 글자 그대로 다뤄진다")
    func queryIsTreatedLiterally() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Use.kt", contents: "val abc = 1\nval a.c = 2\n")

        let result = try await search(in: fixture, for: "a.c")

        #expect(result.references.map(\.line) == [2])
    }

    // 정의 구분 — 걸러내지 않고 플래그로만 구분한다 (AC-2).

    @Test("정의 위치는 플래그로 구분되고 목록에서 빠지지 않는다")
    func definitionSitesAreFlaggedNotFiltered() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Repository.kt", contents: "class Repository {}\n")
        fixture.write("src/Use.kt", contents: "val repository = Repository()\n")

        let symbolIndex = SymbolIndex()
        await symbolIndex.replaceFile(
            "src/Repository.kt",
            with: [
                SymbolDefinition(
                    name: "Repository",
                    kind: .class,
                    path: "src/Repository.kt",
                    line: 1,
                    signature: "class Repository {}"
                )
            ]
        )

        let result = try await search(in: fixture, for: "Repository", symbolIndex: symbolIndex)

        #expect(result.references.count == 2)
        #expect(result.references.map(\.isDefinition) == [true, false])
        #expect(result.references.map(\.path) == ["src/Repository.kt", "src/Use.kt"])
    }

    // 결과 모양.

    @Test("결과가 경로 다음 라인 순으로 정렬된다")
    func resultsAreSortedByPathThenLine() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/b.kt", contents: "Target\nx\nTarget\n")
        fixture.write("src/a.kt", contents: "x\nTarget\n")

        let result = try await search(in: fixture, for: "Target")

        let locations = result.references.map { "\($0.path):\($0.line)" }
        #expect(locations == ["src/a.kt:2", "src/b.kt:1", "src/b.kt:3"])
    }

    @Test("미리보기는 앞뒤 공백이 제거된 그 줄이다")
    func previewIsTheTrimmedLine() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Use.kt", contents: "        val value = Target()   \n")

        let result = try await search(in: fixture, for: "Target")

        #expect(result.references.first?.previewText == "val value = Target()")
    }

    @Test("한 줄에 여러 번 나와도 참조는 그 줄 하나다")
    func repeatedNameOnOneLineIsOneReference() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Use.kt", contents: "Target(Target, Target)\n")

        let result = try await search(in: fixture, for: "Target")

        // Reference.id가 "경로:라인"이라 한 줄에 여러 건이면 목록에서 id가 충돌한다.
        #expect(result.references.count == 1)
        #expect(result.total == 1)
    }

    @Test("참조가 없으면 빈 목록으로 성공한다")
    func noReferencesYieldsEmptyResult() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Use.kt", contents: "val value = Other()\n")

        let result = try await search(in: fixture, for: "Target")

        #expect(result.references.isEmpty)
        #expect(result.total == 0)
        #expect(result.truncated == false)
        #expect(result.limit == ReferenceSearcher.resultLimit)
    }

    // 상한 경계.

    @Test("정확히 상한만큼이면 잘리지 않는다")
    func exactlyAtLimitIsNotTruncated() async throws {
        let fixture = TemporaryProjectFixture()
        let limit = ReferenceSearcher.resultLimit
        fixture.write("src/Many.kt", contents: String(repeating: "Target\n", count: limit))

        let result = try await search(in: fixture, for: "Target")

        #expect(result.references.count == limit)
        #expect(result.total == limit)
        #expect(result.truncated == false)
    }

    @Test("상한을 넘으면 상한까지만 담고 잘렸다고 알린다")
    func beyondLimitIsTruncated() async throws {
        let fixture = TemporaryProjectFixture()
        let limit = ReferenceSearcher.resultLimit
        fixture.write("src/Many.kt", contents: String(repeating: "Target\n", count: limit + 1))

        let result = try await search(in: fixture, for: "Target")

        #expect(result.references.count == limit)
        #expect(result.truncated == true)
        // 관측한 수 — 레포 전체를 마저 세지 않는다.
        #expect(result.total == limit + 1)
    }

    @Test("빈 이름은 아무것도 찾지 않는다")
    func emptyNameFindsNothing() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Use.kt", contents: "val value = Target()\n")

        let result = try await search(in: fixture, for: "")

        #expect(result.references.isEmpty)
    }
}
