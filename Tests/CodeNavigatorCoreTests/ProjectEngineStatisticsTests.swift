import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: 계약 `IndexStatistics` (REQ-002 AC-4 — 건너뛴 파일이 보이지 않으면 인덱스가 조용히
/// 적게 보고하고 아무도 이유를 모른다)
@Suite("ProjectEngine — 인덱스 통계")
struct ProjectEngineStatisticsTests {

    @Test("통계가 인덱스의 실제 내용을 전달한다")
    func statisticsReflectIndexContents() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class App {}\n")
        // 파싱은 되는데 심볼이 없는 파일. 읽지 못한 것이 아니므로 건너뛴 것에 들어가면 안 된다 —
        // "심볼이 없다"와 "읽지 못했다"는 사용자에게 다른 뜻이다.
        fixture.write("src/Empty.kt", contents: "// 주석뿐이다\n")
        // 미지원 확장자는 애초에 인덱싱 대상이 아니라 건너뛴 것에도 들어가지 않는다.
        fixture.write("README.md", contents: "문서\n")
        // 소스 확장자를 달았지만 읽을 수 없는 파일 — 이것이 진짜 "건너뜀"이다.
        try Data([0x00, 0x01, 0x02] + Array("class Blob {}".utf8))
            .write(to: fixture.rootURL.appendingPathComponent("src/Blob.kt"))

        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)

        let statistics = await engine.indexStatistics()

        #expect(statistics.symbolCount == 1)
        #expect(statistics.fileCount == 1)
        // 읽지 못한 Blob.kt 하나만 건너뛴 것이다. Empty.kt 는 여기 들어가지 않는다.
        #expect(statistics.skippedCount == 1)
        #expect(statistics.lastUpdatedAt != nil)
    }

    @Test("프로젝트를 열기 전에는 빈 통계이고 갱신 시각이 없다")
    func statisticsAreEmptyBeforeAnyProjectIsOpened() async {
        let engine = ProjectEngine()

        let statistics = await engine.indexStatistics()

        #expect(statistics.fileCount == 0)
        #expect(statistics.symbolCount == 0)
        #expect(statistics.skippedCount == 0)
        #expect(statistics.lastUpdatedAt == nil)
    }
}
