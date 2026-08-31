import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// The query scenarios from §8, driven through the engine the application actually uses.
///
/// `AcceptanceScenarioTests` runs these against `CodeNavigatorEngine`, which has no source callers
/// — so they were green about a path nothing ships. Moving them is not a formality: the first
/// scenario moved this way (SC-3 with two tabs) failed on its first run and exposed a real defect.
///
/// The editor is deliberately absent here. These scenarios are about the index, the tree and
/// search, and W-8 says those must work without Neovim — so running them with no editor asserts
/// the scenario and that promise at once, and keeps them fast enough to run often.
@Suite("수용 시나리오 (조회) — 앱이 쓰는 경로", .serialized)
struct WorkspaceQueryAcceptanceTests {

    private func makeProject() -> TemporaryProjectFixture {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/SymbolIndexHolder.kt", contents: """
        package com.example

        class SymbolIndexHolder {
            fun addSymbol(name: String): Boolean {
                return true
            }
        }
        """)
        fixture.write("src/Consumer.kt", contents: """
        package com.example

        class Consumer {
            fun use() {
                val holder = SymbolIndexHolder()
                holder.addSymbol("value")
            }
        }
        """)
        fixture.write("src/first/Duplicate.kt", contents: "package a\nfun duplicated() {}\n")
        fixture.write("src/second/Duplicate.kt", contents: "package b\nfun duplicated() {}\n")
        fixture.write("src/third/Duplicate.kt", contents: "package c\nfun duplicated() {}\n")
        return fixture
    }

    private func openedSession(
        _ fixture: TemporaryProjectFixture, in workspace: ProjectWorkspaceEngine
    ) async throws -> any ProjectSession {
        let tab = try await workspace.openProject(at: fixture.rootURL)
        return try #require(await workspace.session(for: tab.tab.id))
    }

    private func makeWorkspace() -> ProjectWorkspaceEngine {
        ProjectWorkspaceEngine(columns: 80, rows: 24, editorExecutableOverridePath: "/nonexistent/nvim")
    }

    @Test("SC-1: 심볼의 정의 위치로 이동한다")
    func goesToDefinition() async throws {
        // 픽스처를 지역 변수로 붙든다. 인라인으로 넘기면 호출 직후 해제되고 `deinit` 이
        // 디렉토리를 지운다 — 인덱싱은 이미 끝나 심볼 조회는 통과하지만, 디스크를 다시 읽는
        // 참조·트리 조회는 사라진 폴더를 만난다. 통과하는 검사와 실패하는 검사가 갈린 이유다.
        let fixture = makeProject()
        let workspace = makeWorkspace()
        let session = try await openedSession(fixture, in: workspace)

        let definitions = await session.definitions(named: "addSymbol")
        #expect(definitions.count == 1)
        #expect(definitions.first?.path == "src/SymbolIndexHolder.kt")
        await workspace.shutDown()
    }

    @Test("SC-2: 동명 정의가 셋이면 후보 셋이 나온다")
    func offersEveryCandidate() async throws {
        // 픽스처를 지역 변수로 붙든다. 인라인으로 넘기면 호출 직후 해제되고 `deinit` 이
        // 디렉토리를 지운다 — 인덱싱은 이미 끝나 심볼 조회는 통과하지만, 디스크를 다시 읽는
        // 참조·트리 조회는 사라진 폴더를 만난다. 통과하는 검사와 실패하는 검사가 갈린 이유다.
        let fixture = makeProject()
        let workspace = makeWorkspace()
        let session = try await openedSession(fixture, in: workspace)

        let definitions = await session.definitions(named: "duplicated")
        #expect(definitions.count == 3)
        // 경로순으로 안정적이어야 한다 — 목록이 실행마다 흔들리면 사용자가 위치를 기억할 수 없다.
        #expect(definitions.map(\.path) == definitions.map(\.path).sorted())
        await workspace.shutDown()
    }

    @Test("SC-6: 잘못된 정규식은 에러다 — 빈 결과로 위장하지 않는다")
    func anInvalidRegularExpressionIsAnError() async throws {
        // 픽스처를 지역 변수로 붙든다. 인라인으로 넘기면 호출 직후 해제되고 `deinit` 이
        // 디렉토리를 지운다 — 인덱싱은 이미 끝나 심볼 조회는 통과하지만, 디스크를 다시 읽는
        // 참조·트리 조회는 사라진 폴더를 만난다. 통과하는 검사와 실패하는 검사가 갈린 이유다.
        let fixture = makeProject()
        let workspace = makeWorkspace()
        let session = try await openedSession(fixture, in: workspace)

        await #expect(throws: (any Error).self) {
            try await session.searchText("class SymbolIndexHolder(", mode: .regularExpression)
        }
        await workspace.shutDown()
    }

    @Test("참조 목록에 정의가 포함되고 플래그로 구분된다")
    func referencesIncludeTheDefinitionAndSaySo() async throws {
        // 픽스처를 지역 변수로 붙든다. 인라인으로 넘기면 호출 직후 해제되고 `deinit` 이
        // 디렉토리를 지운다 — 인덱싱은 이미 끝나 심볼 조회는 통과하지만, 디스크를 다시 읽는
        // 참조·트리 조회는 사라진 폴더를 만난다. 통과하는 검사와 실패하는 검사가 갈린 이유다.
        let fixture = makeProject()
        let workspace = makeWorkspace()
        let session = try await openedSession(fixture, in: workspace)

        let result = try await session.references(to: "addSymbol")
        #expect(result.references.contains { $0.isDefinition })
        #expect(result.references.contains { $0.isDefinition == false })
        await workspace.shutDown()
    }

    @Test("심볼 퍼지 검색이 관련도순으로 응답한다")
    func fuzzySearchRanksByRelevance() async throws {
        // 픽스처를 지역 변수로 붙든다. 인라인으로 넘기면 호출 직후 해제되고 `deinit` 이
        // 디렉토리를 지운다 — 인덱싱은 이미 끝나 심볼 조회는 통과하지만, 디스크를 다시 읽는
        // 참조·트리 조회는 사라진 폴더를 만난다. 통과하는 검사와 실패하는 검사가 갈린 이유다.
        let fixture = makeProject()
        let workspace = makeWorkspace()
        let session = try await openedSession(fixture, in: workspace)

        let results = await session.searchSymbols(matching: "addSym")
        #expect(results.isEmpty == false)
        #expect(results.map(\.score) == results.map(\.score).sorted(by: >))
        await workspace.shutDown()
    }

    @Test("파일 트리가 한 레벨씩, 디렉토리 우선으로 나온다")
    func theTreeIsOneLevelDirectoriesFirst() async throws {
        // 픽스처를 지역 변수로 붙든다. 인라인으로 넘기면 호출 직후 해제되고 `deinit` 이
        // 디렉토리를 지운다 — 인덱싱은 이미 끝나 심볼 조회는 통과하지만, 디스크를 다시 읽는
        // 참조·트리 조회는 사라진 폴더를 만난다. 통과하는 검사와 실패하는 검사가 갈린 이유다.
        let fixture = makeProject()
        let workspace = makeWorkspace()
        let session = try await openedSession(fixture, in: workspace)

        let entries = try await session.directoryEntries(atRelativePath: "src")
        let directories = entries.prefix { $0.isDirectory }
        #expect(directories.isEmpty == false)
        #expect(entries.dropFirst(directories.count).allSatisfy { $0.isDirectory == false })
        await workspace.shutDown()
    }

    /// The workspace has no "no project open" state the way the single-project engine did — an
    /// unknown tab is the equivalent, and it must be an error rather than an empty answer.
    @Test("열지 않은 탭으로 조회하면 명확한 에러다")
    func queryingAnUnknownTabIsAnError() async throws {
        let workspace = makeWorkspace()
        _ = try await openedSession(makeProject(), in: workspace)

        #expect(await workspace.session(for: ProjectTabIdentifier()) == nil)
        await #expect(throws: NavigatorError.noProjectOpen) {
            try await workspace.renderSource(atRelativePath: "src/Consumer.kt", in: ProjectTabIdentifier())
        }
        await workspace.shutDown()
    }

    /// Switching projects used to mean replacing the one index. Here both stay, so the scenario
    /// becomes: each tab keeps answering for its own project after the switch.
    @Test("탭을 옮겨도 각 탭이 자기 프로젝트로 답한다")
    func eachTabKeepsAnsweringForItsOwnProject() async throws {
        let alpha = makeProject()
        let beta = TemporaryProjectFixture()
        beta.write("src/Other.kt", contents: "class OtherOnly")
        let workspace = makeWorkspace()

        let first = try await workspace.openProject(at: alpha.rootURL)
        let second = try await workspace.openProject(at: beta.rootURL)
        try await workspace.activate(first.tab.id)

        let alphaSession = try #require(await workspace.session(for: first.tab.id))
        let betaSession = try #require(await workspace.session(for: second.tab.id))
        #expect(await alphaSession.definitions(named: "SymbolIndexHolder").isEmpty == false)
        #expect(await alphaSession.definitions(named: "OtherOnly").isEmpty)
        #expect(await betaSession.definitions(named: "OtherOnly").isEmpty == false)
        await workspace.shutDown()
    }
}
