import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: 인증용 라이브 E2E 픽스처(`_workspace/e2e-fixture`)가 엔진에서 기대대로 색인되는지
///
/// 인증 도중 결과가 틀리면 **앱이 틀린 건지 픽스처가 틀린 건지** 가리느라 시간을 태운다. 그 분기를
/// 미리 없애는 것이 이 스위트의 목적이다. 픽스처가 깨지면 여기서 먼저 빨간불이 난다.
@Suite("인증 픽스처 — 엔진 사전 검증")
struct CertificationFixtureTests {

    /// 레포 안의 실제 픽스처를 가리킨다. 복사하지 않는다 — 인증이 쓰는 바로 그 파일이어야 한다.
    private var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CodeNavigatorCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("_workspace/e2e-fixture")
    }

    private func openedEngine() async throws -> ProjectEngine {
        let engine = ProjectEngine()
        try await engine.openProject(at: fixtureRoot)
        return engine
    }

    @Test("SC-1: SymbolIndex 정의가 정확히 한 곳이다")
    func symbolIndexHasExactlyOneDefinition() async throws {
        let engine = try await openedEngine()

        let definitions = await engine.definitions(named: "SymbolIndex")

        #expect(definitions.count == 1)
        #expect(definitions.first?.path == "src/core/SymbolIndex.ts")
        #expect(definitions.first?.kind == .class)
    }

    @Test("SC-1: 이름이 겹치는 SymbolIndexHolder 가 섞이지 않는다")
    func lookalikeSymbolDoesNotContaminateResults() async throws {
        let engine = try await openedEngine()

        let references = try await engine.references(to: "SymbolIndex")

        // SymbolIndexHolder 선언 줄은 부분 단어라 결과에 없어야 한다.
        let holderDeclarations = references.references.filter {
            $0.previewText.contains("class SymbolIndexHolder")
        }
        #expect(holderDeclarations.isEmpty)
        // 반대로 온전한 토큰으로 쓰인 자리는 잡혀야 한다.
        #expect(references.references.contains { $0.previewText.contains("readonly index: SymbolIndex") })
    }

    @Test("SC-2: resolveTarget 정의가 정확히 세 곳이다")
    func resolveTargetHasThreeDefinitions() async throws {
        let engine = try await openedEngine()

        let definitions = await engine.definitions(named: "resolveTarget")

        #expect(definitions.map(\.path).sorted() == [
            "src/core/resolveTarget.ts",
            "src/search/resolveTarget.ts",
            "src/tree/resolveTarget.ts",
        ])
    }

    @Test("제외: node_modules 가 트리·검색·색인 어디에도 없다")
    func nodeModulesIsExcludedEverywhere() async throws {
        let engine = try await openedEngine()

        let entries = try await engine.directoryEntries(atRelativePath: "")
        #expect(!entries.contains { $0.name == "node_modules" })

        let textResults = try await engine.searchText("junk", mode: .literal)
        #expect(!textResults.items.contains { $0.path.hasPrefix("node_modules") })
    }

    @Test("한글: 강조 구간이 실제 질의어 자리를 가리킨다")
    func hangulLineHighlightsPointAtTheQuery() async throws {
        let engine = try await openedEngine()

        let result = try await engine.searchText("검색", mode: .literal)

        #expect(!result.items.isEmpty)
        for item in result.items {
            let utf16 = Array(item.previewText.utf16)
            for range in item.matchRanges {
                #expect(range.end <= utf16.count)
                let matched = String(decoding: utf16[range.start..<range.end], as: UTF16.self)
                #expect(matched == "검색")
            }
        }
    }

    @Test("한글: 사용자Index 는 Index 참조 검색에 걸리지 않는다")
    func hangulGluedIdentifierIsNotAReference() async throws {
        let engine = try await openedEngine()

        let references = try await engine.references(to: "Index")

        // 이 픽스처에서 `Index` 는 `사용자Index` 안에만 있다. 경계 규칙이 살아 있으면 0건이다.
        #expect(references.references.isEmpty)

        // 0건이 "검색이 고장나서 0건"이 아님을 같은 자리에서 확인한다 — 음성 단언에는
        // 반드시 양성 대조가 붙어야 한다.
        let positiveControl = try await engine.references(to: "SymbolIndex")
        #expect(!positiveControl.references.isEmpty)
    }
}
