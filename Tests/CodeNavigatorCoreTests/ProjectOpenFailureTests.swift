import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-001 AC-3 (프로젝트 열기 실패 시 **명확한 에러**, 이전 상태 유지)
///
/// QA 라이브 실측에서 "권한 프롬프트를 허용하기 전 첫 시도가 **조용히 실패**했다 — 프로젝트가 안
/// 열리고 에러 표시도 없었다"가 나왔다. 조용한 실패는 빈 결과와 구분되지 않아 사용자가 원인을
/// 알 수 없다. 여기서는 실패가 **던져지는지**, **종류별로 구분되는지**, **문구가 사람이 읽을 만한지**를 본다.
@Suite("프로젝트 열기 — 실패 경로")
struct ProjectOpenFailureTests {

    private func makeUnreadableDirectory() throws -> (url: URL, restore: () -> Void) {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class App\n")
        let path = fixture.rootURL.path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        return (
            fixture.rootURL,
            {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
                _ = fixture  // 정리 시점까지 픽스처를 살려 둔다
            }
        )
    }

    @Test("없는 경로를 열면 경로 없음으로 실패한다")
    func missingPathFailsAsNotFound() async throws {
        let engine = ProjectEngine()

        await #expect(throws: NavigatorError.projectNotFound(path: "/nonexistent/project")) {
            try await engine.openProject(at: URL(fileURLWithPath: "/nonexistent/project"))
        }
    }

    @Test("파일을 프로젝트 루트로 지정하면 디렉토리가 아니라고 실패한다")
    func fileAsRootFailsAsNotReadable() async throws {
        let fixture = TemporaryProjectFixture()
        let fileURL = fixture.write("src/App.kt", contents: "class App\n")
        let engine = ProjectEngine()

        await #expect(throws: (any Error).self) {
            try await engine.openProject(at: fileURL)
        }
    }

    @Test("읽을 수 없는 디렉토리를 열면 조용히 성공하지 않는다")
    func unreadableRootDoesNotSucceedSilently() async throws {
        // root 로 돌면 권한 검사가 통과해 이 케이스를 만들 수 없다.
        guard getuid() != 0 else {
            return
        }

        let (rootURL, restore) = try makeUnreadableDirectory()
        defer { restore() }

        let engine = ProjectEngine()

        // 이것이 QA 가 본 증상이다: 열기는 "성공"하고 결과만 비어 있으면, 사용자는 프로젝트가
        // 빈 것인지 권한이 없는 것인지 구분할 수 없다.
        var thrown: NavigatorError?
        do {
            try await engine.openProject(at: rootURL)
        } catch let error as NavigatorError {
            thrown = error
        }

        let error = try #require(thrown, "읽을 수 없는 루트인데 조용히 성공했다")
        let description = try #require(error.errorDescription)

        // 원인을 이름으로 말해야 한다. "읽을 수 없습니다"만으로는 사용자가 무엇을 해야 할지 모른다.
        #expect(description.contains("권한"), "권한 문제인데 문구가 그 사실을 말하지 않는다: \(description)")
    }

    @Test("실패 종류가 서로 구분된다 — 안내 문구를 만들 수 있어야 한다")
    func failureKindsAreDistinguishable() async throws {
        let engine = ProjectEngine()

        var missingPathError: NavigatorError?
        do {
            try await engine.openProject(at: URL(fileURLWithPath: "/nonexistent/project"))
        } catch let error as NavigatorError {
            missingPathError = error
        }

        let fixture = TemporaryProjectFixture()
        let fileURL = fixture.write("src/App.kt", contents: "class App\n")
        var fileAsRootError: NavigatorError?
        do {
            try await engine.openProject(at: fileURL)
        } catch let error as NavigatorError {
            fileAsRootError = error
        }

        let missing = try #require(missingPathError)
        let fileAsRoot = try #require(fileAsRootError)
        #expect(missing != fileAsRoot, "두 실패가 같은 에러로 뭉개지면 사용자에게 다른 안내를 줄 수 없다")
    }

    @Test("에러 문구가 사람이 읽을 수 있는 한국어 안내다")
    func errorDescriptionIsHumanReadable() async throws {
        let engine = ProjectEngine()

        do {
            try await engine.openProject(at: URL(fileURLWithPath: "/nonexistent/project"))
            Issue.record("실패해야 하는데 성공했다")
        } catch let error as NavigatorError {
            let description = try #require(error.errorDescription)
            // 시스템 문자열("Operation not permitted")만 노출되면 사용자는 무슨 일인지 모른다.
            #expect(description.contains("프로젝트"))
            #expect(!description.isEmpty)
        }
    }

    @Test("열기에 실패해도 이전 프로젝트가 유지된다 (REQ-001 AC-3)")
    func failedOpenKeepsThePreviousProject() async throws {
        let good = TemporaryProjectFixture()
        good.write("src/App.kt", contents: "class App\n")
        let engine = ProjectEngine()
        try await engine.openProject(at: good.rootURL)

        let before = await engine.currentProject()
        #expect(before?.rootPath == good.rootURL)

        _ = try? await engine.openProject(at: URL(fileURLWithPath: "/nonexistent/project"))

        let after = await engine.currentProject()
        #expect(after?.rootPath == good.rootURL, "실패한 열기가 이전 프로젝트를 날려버렸다")
    }
}
