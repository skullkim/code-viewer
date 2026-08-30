import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// The editor is an enhancement over the index, not a prerequisite for it.
///
/// W-8 promises the user in so many words that "트리·심볼 검색·참조·전문 검색은 계속 사용할 수
/// 있습니다" when Neovim cannot start. That promise is only true if a failed editor leaves the
/// index open. Reporting the editor's failure by failing the whole open makes the application
/// discard a perfectly good index, and the user sees `인덱스 없음` on a project that indexed fine.
///
/// The editor reports its own failure through `state()`, which is what the overlay reads.
@Suite("편집기 실패는 인덱스를 무너뜨리지 않는다", .serialized)
struct EditorFailureKeepsIndexTests {

    /// A path where no editor exists yet. Tests that want one later write it in place.
    private func absentEditorPath() -> String {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nvim-absent-\(UUID().uuidString)")
            .path
    }

    /// A wrapper that answers the version probe and then becomes the real editor.
    private func installEditor(at path: String, realEditor: URL) throws {
        try """
        #!/bin/sh
        case "$1" in
          --version) exec \(realEditor.path) --version ;;
        esac
        exec \(realEditor.path) "$@"
        """.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    @Test("편집기가 없어도 프로젝트는 열리고 심볼이 검색된다 — W-8 의 약속")
    func aMissingEditorStillLeavesASearchableIndex() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        let engine = CodeNavigatorEngine(editorExecutableOverridePath: absentEditorPath())

        // 편집기 실패는 열기 실패가 아니다. 던지면 앱이 인덱스를 통째로 버린다.
        try await engine.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)

        #expect(await engine.project.currentProject() != nil)
        #expect(await engine.project.definitions(named: "Application").isEmpty == false)

        // 실패는 사라지지 않는다 — 편집기 상태가 그것을 들고 있고 W-8 이 그걸 읽는다.
        guard case .startupFailed = await engine.editor.state() else {
            Issue.record("편집기 실패가 상태에 남지 않았다: \(await engine.editor.state())")
            return
        }
        await engine.shutDown()
    }

    /// Switching projects after the editor died.
    ///
    /// The index moves first and the editor is asked to follow. A crashed session cannot follow,
    /// and the old code did two wrong things with that: it skipped the editor entirely, so the
    /// session never came back for the rest of the application's life, and any refusal it did
    /// raise threw — discarding a switch the index had already completed.
    @Test("편집기가 죽은 뒤 다른 프로젝트로 바꾸면 전환도 되고 편집기도 돌아온다")
    func switchingProjectsAfterACrashRestoresTheEditor() async throws {
        let first = TemporaryProjectFixture()
        first.write("src/First.kt", contents: "class First")
        let second = TemporaryProjectFixture()
        second.write("src/Second.kt", contents: "class Second")

        let engine = CodeNavigatorEngine()
        try await engine.start(projectRoot: first.rootURL, columns: 80, rows: 24)
        let identifier = try #require(await engine.editor.processIdentifierForTesting())

        // 사용자 몰래 죽는다 — 크래시가 실제로 하는 일이다.
        kill(identifier, SIGKILL)
        while kill(identifier, 0) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }

        try await engine.openProject(at: second.rootURL)

        #expect(await engine.project.currentProject()?.rootPath.lastPathComponent
                == second.rootURL.lastPathComponent)
        #expect(await engine.project.definitions(named: "Second").isEmpty == false)
        // 편집기가 돌아와야 한다. 안 돌아오면 사용자는 앱을 다시 켜는 것 말고 할 수 있는 게 없다.
        #expect(await engine.editor.state() == .connected)
        await engine.shutDown()
    }

    @Test("편집기 실패 후 프로젝트를 다시 열면 편집기를 다시 띄운다")
    func reopeningAProjectRetriesTheEditor() async throws {
        let realEditor = try NeovimExecutableLocator().locate()
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        let editorPath = absentEditorPath()
        defer { try? FileManager.default.removeItem(atPath: editorPath) }

        let engine = CodeNavigatorEngine(editorExecutableOverridePath: editorPath)
        try await engine.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        guard case .startupFailed = await engine.editor.state() else {
            Issue.record("전제가 성립하지 않았다 — 첫 기동이 실패했어야 한다")
            return
        }

        // 사용자가 문제를 고쳤다. 다시 열기가 편집기를 다시 시도하지 않으면 nvim 은
        // 앱이 살아 있는 동안 영영 뜨지 않는다 — 자식 0개인 채로.
        try await installEditor(at: editorPath, realEditor: realEditor)
        try await engine.openProject(at: fixture.rootURL)

        #expect(await engine.editor.state() == .connected)
        await engine.shutDown()
    }
}
