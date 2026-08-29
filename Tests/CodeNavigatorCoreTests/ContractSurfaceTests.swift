import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: 계약 §3.2 `ProjectSession` 표면 전체와 그 위의 오프셋 불변식
///
/// 이번 빌드에서 계약에 멤버가 추가됐는데 구현이 따라오지 못해 트리가 두 번 깨졌다. 컴파일러가
/// 준수 여부는 잡아주지만, **선언된 표면이 실제로 동작하는지**는 잡아주지 않는다 — 계약에 있는데
/// 아무도 부르지 않는 메서드는 "구현됐다"와 "동작한다" 사이에서 조용히 썩는다.
///
/// 그래서 여기서는 구체 타입이 아니라 **`any ProjectSession` 으로만** 호출한다. 계약 밖으로 삐져나온
/// 것에 기대면 프론트가 쓸 수 없는 경로를 검증하게 된다.
@Suite("계약 표면 — ProjectSession")
struct ContractSurfaceTests {

    private func makeProject() -> TemporaryProjectFixture {
        let fixture = TemporaryProjectFixture()
        fixture.write(
            "src/Repository.kt",
            contents: """
                class UserRepository {
                    fun findUser(identifier: Int): String = "user"
                }
                """
        )
        fixture.write("src/Caller.kt", contents: "val repository = UserRepository()\n")
        fixture.write("docs/README.md", contents: "UserRepository 사용법\n")
        return fixture
    }

    @Test("계약에 선언된 모든 메서드가 프로토콜 타입으로 호출된다")
    func everyDeclaredMemberIsUsableThroughTheProtocol() async throws {
        let fixture = makeProject()
        let session: any ProjectSession = ProjectEngine()

        try await session.openProject(at: fixture.rootURL)

        let project = await session.currentProject()
        #expect(project?.rootPath == fixture.rootURL)
        #expect(await session.indexState() == .ready)

        // 구독 즉시 현재 상태를 1회 방출한다 (§3.2).
        var stateIterator = await session.indexStateUpdates().makeAsyncIterator()
        #expect(await stateIterator.next() == .ready)

        let statistics = await session.indexStatistics()
        #expect(statistics.symbolCount > 0)
        #expect(statistics.lastUpdatedAt != nil)

        #expect(await session.definitions(named: "UserRepository").count == 1)
        #expect(!(await session.searchSymbols(matching: "UsrRepo")).isEmpty)

        let references = try await session.references(to: "UserRepository")
        #expect(references.limit > 0)
        #expect(references.references.contains { $0.isDefinition })

        let textResults = try await session.searchText("UserRepository", mode: .literal)
        #expect(!textResults.items.isEmpty)

        let entries = try await session.directoryEntries(atRelativePath: "")
        #expect(entries.map(\.name) == ["docs", "src"])
    }

    // 오프셋 불변식 — UTF-8/UTF-16 혼동은 한글이 섞인 줄에서만 드러난다.

    @Test("참조 결과의 강조 구간이 미리보기 안에 있다")
    func referenceMatchRangesStayInsideTheirPreview() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write(
            "src/Hangul.kt",
            contents: """
                // 한글 주석 안의 UserRepository 언급
                val 저장소 = UserRepository()
                    val 들여쓰기 = UserRepository()
                """
        )
        let session: any ProjectSession = ProjectEngine()
        try await session.openProject(at: fixture.rootURL)

        let result = try await session.references(to: "UserRepository")

        #expect(!result.references.isEmpty)
        for reference in result.references {
            let previewLength = reference.previewText.utf16.count
            for range in reference.matchRanges {
                #expect(range.start >= 0)
                #expect(range.end <= previewLength)
                #expect(range.start < range.end)
            }
        }
    }

    @Test("전문 검색 결과의 강조 구간이 실제로 그 문자열을 가리킨다")
    func textSearchMatchRangesPointAtTheQuery() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write(
            "src/Hangul.kt",
            contents: """
                val 값 = "needle 한글"
                    val 들여쓰기값 = "needle 뒤"
                """
        )
        let session: any ProjectSession = ProjectEngine()
        try await session.openProject(at: fixture.rootURL)

        let result = try await session.searchText("needle", mode: .literal)

        #expect(result.items.count == 2)
        for item in result.items {
            let utf16 = Array(item.previewText.utf16)
            for range in item.matchRanges {
                #expect(range.end <= utf16.count)
                // 구간이 가리키는 자리에 실제로 질의어가 있어야 한다 — 오프셋이 어긋나면 여기서 걸린다.
                let matched = String(decoding: utf16[range.start..<range.end], as: UTF16.self)
                #expect(matched == "needle")
            }
        }
    }
}
