import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

@Suite("ProjectIndexer — 인덱싱과 증분 갱신", .serialized)
struct ProjectIndexerTests {

    private func openedIndexer(_ fixture: TemporaryProjectFixture) async throws -> ProjectIndexer {
        let indexer = ProjectIndexer()
        try await indexer.openProject(at: fixture.rootURL)
        return indexer
    }

    @Test("프로젝트를 열면 전체 인덱싱이 끝나고 최신 상태가 된다")
    func indexesEverythingOnOpen() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application\nfun start() {}\n")
        fixture.write("src/Helper.java", contents: "class Helper { void help() {} }")
        fixture.write("README.md", contents: "# 문서")

        let indexer = try await openedIndexer(fixture)

        #expect(await indexer.indexState() == .ready)
        #expect(await indexer.definitions(named: "Application").count == 1)
        #expect(await indexer.definitions(named: "Helper").count == 1)
        #expect(await indexer.indexedFileCount() == 2)
    }

    @Test("제외 대상과 gitignore 파일은 인덱싱되지 않는다")
    func respectsExclusionsWhileIndexing() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write(".gitignore", contents: "generated/\n")
        fixture.write("src/App.kt", contents: "class Application")
        fixture.write("generated/Gen.kt", contents: "class Generated")
        fixture.write("node_modules/lib/Vendor.kt", contents: "class Vendor")

        let indexer = try await openedIndexer(fixture)

        #expect(await indexer.definitions(named: "Application").count == 1)
        #expect(await indexer.definitions(named: "Generated").isEmpty)
        #expect(await indexer.definitions(named: "Vendor").isEmpty)
    }

    @Test("존재하지 않는 경로는 에러이고 이전 프로젝트가 유지된다")
    func keepsPreviousProjectWhenOpeningAnInvalidPath() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        let indexer = try await openedIndexer(fixture)

        await #expect(throws: (any Error).self) {
            try await indexer.openProject(at: URL(fileURLWithPath: "/nonexistent/project"))
        }

        #expect(await indexer.definitions(named: "Application").count == 1)
        #expect(await indexer.currentProject()?.rootPath == fixture.rootURL)
    }

    @Test("파일이 바뀌면 그 파일만 다시 인덱싱된다")
    func reindexesChangedFile() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        let indexer = try await openedIndexer(fixture)

        fixture.write("src/App.kt", contents: "class Application\nfun freshlyAdded() {}\n")
        await indexer.noteChange(relativePath: "src/App.kt", kind: .changed)
        await indexer.waitUntilIdle()

        #expect(await indexer.definitions(named: "freshlyAdded").count == 1)
        #expect(await indexer.indexState() == .ready)
    }

    @Test("파일이 삭제되면 심볼이 사라진다 — 유령 결과 금지")
    func removesSymbolsOfDeletedFile() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Gone.kt", contents: "class WillVanish")
        let indexer = try await openedIndexer(fixture)
        #expect(await indexer.definitions(named: "WillVanish").count == 1)

        fixture.remove("src/Gone.kt")
        await indexer.noteChange(relativePath: "src/Gone.kt", kind: .removed)
        await indexer.waitUntilIdle()

        #expect(await indexer.definitions(named: "WillVanish").isEmpty)
    }

    @Test("이름이 바뀌면 옛 경로 잔재가 남지 않는다")
    func handlesRenameWithoutLeavingStalePaths() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Old.kt", contents: "class Movable")
        let indexer = try await openedIndexer(fixture)

        fixture.remove("src/Old.kt")
        fixture.write("src/New.kt", contents: "class Movable")
        await indexer.noteChange(relativePath: "src/Old.kt", kind: .removed)
        await indexer.noteChange(relativePath: "src/New.kt", kind: .changed)
        await indexer.waitUntilIdle()

        let definitions = await indexer.definitions(named: "Movable")
        #expect(definitions.map(\.path) == ["src/New.kt"])
    }

    @Test("지원하지 않는 파일의 변경은 재인덱싱을 유발하지 않는다")
    func ignoresChangesToUnsupportedFiles() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        let indexer = try await openedIndexer(fixture)

        fixture.write("README.md", contents: "# 바뀐 문서")
        await indexer.noteChange(relativePath: "README.md", kind: .changed)

        // 대기 중인 작업이 아예 없어야 한다 — 상태가 ready 에서 움직이지 않는다.
        #expect(await indexer.indexState() == .ready)
    }

    @Test("gitignore에 새로 걸린 파일은 삭제처럼 인덱스에서 빠진다")
    func treatsNewlyIgnoredFileAsRemoved() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        fixture.write("temp/Scratch.kt", contents: "class Scratch")
        let indexer = try await openedIndexer(fixture)
        #expect(await indexer.definitions(named: "Scratch").count == 1)

        fixture.write(".gitignore", contents: "temp/\n")
        await indexer.noteChange(relativePath: "temp/Scratch.kt", kind: .changed)
        await indexer.waitUntilIdle()

        #expect(await indexer.definitions(named: "Scratch").isEmpty)
    }

    @Test("대량 변경은 전체 재스캔으로 폴백하고 INV-1이 성립한다")
    func fallsBackToFullRescanOnBulkChange() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Doomed.kt", contents: "class Doomed")
        let indexer = try await openedIndexer(fixture)
        #expect(await indexer.definitions(named: "Doomed").count == 1)

        // 임계 이상 변경 + 파일 하나 삭제. 삭제는 개별 통지 없이도 재스캔이 잡아내야 한다.
        fixture.remove("src/Doomed.kt")
        for index in 0..<FileChangeBatch.bulkChangeThreshold {
            fixture.write("bulk/Item\(index).kt", contents: "class Item\(index)")
            await indexer.noteChange(relativePath: "bulk/Item\(index).kt", kind: .changed)
        }
        await indexer.waitUntilIdle()

        #expect(await indexer.definitions(named: "Doomed").isEmpty)
        #expect(await indexer.definitions(named: "Item0").count == 1)
        #expect(await indexer.definitions(named: "Item49").count == 1)
        #expect(await indexer.indexState() == .ready)
    }

    @Test("드롭 신호가 오면 전체 재스캔한다")
    func fullRescanOnDropSignal() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        let indexer = try await openedIndexer(fixture)

        fixture.write("src/Late.kt", contents: "class ArrivedUnnoticed")
        await indexer.noteFullRescanRequired()
        await indexer.waitUntilIdle()

        #expect(await indexer.definitions(named: "ArrivedUnnoticed").count == 1)
    }

    @Test("상태 스트림이 구독 즉시 현재 상태를 준다")
    func stateStreamReplaysCurrentState() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        let indexer = try await openedIndexer(fixture)

        var iterator = await indexer.indexStateUpdates().makeAsyncIterator()
        #expect(await iterator.next() == .ready)
    }

    @Test("파싱이 깨지는 파일이 있어도 나머지는 인덱싱된다")
    func oneBrokenFileDoesNotStopTheRun() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Good.kt", contents: "class PerfectlyFine")
        fixture.write("src/Broken.kt", contents: "((((%%%% ]]]] @@@@")
        let indexer = try await openedIndexer(fixture)

        #expect(await indexer.definitions(named: "PerfectlyFine").count == 1)
        #expect(await indexer.indexState() == .ready)
    }

    @Test("바이너리 파일과 지나치게 큰 파일은 건너뛴다")
    func skipsBinaryAndOversizedFiles() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/Good.kt", contents: "class PerfectlyFine")

        let binaryURL = fixture.rootURL.appendingPathComponent("src/Binary.kt")
        try Data([0x00, 0x01, 0x02, 0x00]).write(to: binaryURL)

        let hugeURL = fixture.rootURL.appendingPathComponent("src/Huge.kt")
        let huge = String(repeating: "class Padding\n", count: 120_000)
        try huge.write(to: hugeURL, atomically: true, encoding: .utf8)

        let indexer = try await openedIndexer(fixture)

        #expect(await indexer.definitions(named: "PerfectlyFine").count == 1)
        #expect(await indexer.definitions(named: "Padding").isEmpty)
        #expect(await indexer.indexState() == .ready)
    }
}
