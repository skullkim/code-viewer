import Testing
import Foundation
@testable import CodeNavigatorCore

/// Measures the performance requirements rather than assuming them (REQ-NF-001, REQ-NF-002).
///
/// The bounds are the requirement's own numbers. They are generous relative to what this machine
/// does, which is the point: the test should fail when a change makes indexing an order of
/// magnitude slower, not flicker because the machine was briefly busy.
@Suite("성능 — 중형 레포 기준 (REQ-NF-001)", .serialized)
struct IndexingPerformanceTests {

    /// Builds a repository of roughly the size the requirement names.
    private func makeMediumProject(fileCount: Int) -> TemporaryProjectFixture {
        let fixture = TemporaryProjectFixture()
        let languages = ["kt", "java", "ts", "js"]

        for index in 0..<fileCount {
            let fileExtension = languages[index % languages.count]
            let body: String
            switch fileExtension {
            case "kt":
                body = """
                package com.example.module\(index % 50)

                class Service\(index)(private val repository: Repository\(index)) {
                    val identifier: Int = \(index)
                    fun handle(request: String): Boolean {
                        return repository.store(request)
                    }
                    fun describe(): String = "service-\(index)"
                }

                interface Repository\(index) {
                    fun store(value: String): Boolean
                }
                """
            case "java":
                body = """
                package com.example.module\(index % 50);

                public class Handler\(index) {
                    private final String name;
                    public Handler\(index)(String name) { this.name = name; }
                    public boolean handle(String request) { return true; }
                }
                """
            case "ts":
                body = """
                export interface Options\(index) { limit: number; }
                export class Controller\(index) {
                  private cache = new Map<string, number>();
                  handle(request: string): boolean { return true; }
                }
                export const build\(index) = (value: number) => value + \(index);
                """
            default:
                body = """
                export class Widget\(index) {
                  count = \(index);
                  render = () => this.count;
                  update(next) { this.count = next; }
                }
                export const make\(index) = (n) => new Widget\(index)(n);
                """
            }
            fixture.write("src/module\(index % 50)/File\(index).\(fileExtension)", contents: body)
        }
        return fixture
    }

    @Test("중형 레포(5,000 파일) 초기 인덱싱이 10초 안에 끝난다", .timeLimit(.minutes(2)))
    func indexesMediumProjectWithinBudget() async throws {
        let fileCount = 5_000
        let fixture = makeMediumProject(fileCount: fileCount)

        let indexer = ProjectIndexer()
        let start = Date()
        try await indexer.openProject(at: fixture.rootURL)
        let elapsed = Date().timeIntervalSince(start)

        let indexedFiles = await indexer.indexedFileCount()
        let symbols = await indexer.symbolCount()
        print("[성능] \(fileCount)파일 인덱싱 \(String(format: "%.2f", elapsed))초 · 파일 \(indexedFiles) · 심볼 \(symbols)")

        #expect(indexedFiles == fileCount)
        #expect(elapsed < 10.0)
    }

    @Test("심볼 검색이 100ms 안에 응답한다", .timeLimit(.minutes(2)))
    func searchesSymbolsWithinBudget() async throws {
        let fixture = makeMediumProject(fileCount: 5_000)
        let indexer = ProjectIndexer()
        try await indexer.openProject(at: fixture.rootURL)

        // 인덱스가 4로 나눠떨어지는 파일만 Kotlin 이라 Service 클래스를 갖는다.
        let start = Date()
        let definitions = await indexer.definitions(named: "Service1236")
        let elapsed = Date().timeIntervalSince(start)
        print("[성능] 정의 조회 \(String(format: "%.1f", elapsed * 1000))ms")

        #expect(definitions.count == 1)
        #expect(elapsed < 0.1)
    }

    @Test("단일 파일 증분 갱신이 500ms 안에 끝난다", .timeLimit(.minutes(2)))
    func incrementalUpdateWithinBudget() async throws {
        let fixture = makeMediumProject(fileCount: 5_000)
        let indexer = ProjectIndexer()
        try await indexer.openProject(at: fixture.rootURL)

        fixture.write("src/module0/File0.kt", contents: "class ReplacedEntirely\nfun brandNew() {}\n")

        let start = Date()
        await indexer.reindexFile(atRelativePath: "src/module0/File0.kt")
        let elapsed = Date().timeIntervalSince(start)
        print("[성능] 단일 파일 증분 갱신 \(String(format: "%.1f", elapsed * 1000))ms")

        #expect(await indexer.definitions(named: "brandNew").count == 1)
        #expect(elapsed < 0.5)
    }
}
