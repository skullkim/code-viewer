import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// `currentProject` after a failed open, kept from the retired scenario file.
///
/// These drive `ProjectEngine` directly — the component the workspace holds one of per tab —
/// so they were never on the dead path either.
@Suite("currentProject — 실패한 열기 뒤의 권위", .serialized)
struct CurrentProjectAuthorityTests {

    @Test("열기에 실패해도 엔진은 이전 프로젝트를 계속 가리킨다")
    func staysOnThePreviousProjectAfterAFailedOpen() async throws {
        let opened = TemporaryProjectFixture()
        opened.write("src/App.kt", contents: "class Application")
        let engine = ProjectEngine()
        try await engine.openProject(at: opened.rootURL)

        let requested = URL(fileURLWithPath: "/nonexistent/second")
        await #expect(throws: (any Error).self) {
            try await engine.openProject(at: requested)
        }

        // 앱이 "요청한 경로"를 들고 있으면 여기서 갈라진다. 엔진이 답하는 쪽이 진짜다.
        #expect(await engine.currentProject()?.rootPath == opened.rootURL)
        #expect(await engine.definitions(named: "Application").count == 1)
    }

    @Test("프로젝트를 열기 전에는 가리키는 것이 없다")
    func hasNoProjectBeforeOpening() async {
        #expect(await ProjectEngine().currentProject() == nil)
    }

    @Test("이름은 루트 디렉토리 이름이다")
    func namesTheProjectAfterItsRootDirectory() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        let engine = ProjectEngine()
        try await engine.openProject(at: fixture.rootURL)

        let project = try #require(await engine.currentProject())
        #expect(project.name == fixture.rootURL.lastPathComponent)
    }
}
