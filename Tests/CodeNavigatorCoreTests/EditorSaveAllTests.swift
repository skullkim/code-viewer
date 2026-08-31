import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: W-13 "저장 후 닫기" — 탭의 **모든** 저장 안 한 파일을 쓰고, 무엇이 실패했는지 말한다
///
/// `:w` 는 현재 버퍼만 쓰고 `:wa` 는 탭페이지 경계를 모른다(둘 다 `EditorSaveScopeTests` 에서 실측).
/// 그래서 범위는 **버퍼 경로가 프로젝트 루트 안인지**로 가른다 — 창·탭페이지 구성과 무관하다.
@Suite("저장 전체 — W-13 계약", .serialized)
struct EditorSaveAllTests {

    private func startSession(_ fixture: TemporaryProjectFixture) async throws -> NeovimEditorSession {
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        return session
    }

    private func read(_ fixture: TemporaryProjectFixture, _ relativePath: String) -> String {
        (try? String(
            contentsOf: fixture.rootURL.appendingPathComponent(relativePath), encoding: .utf8
        )) ?? ""
    }

    private func makeDirty(
        _ session: NeovimEditorSession,
        _ relativePath: String,
        marker: String
    ) async throws {
        try await session.openFile(atRelativePath: relativePath, line: 1, recordJump: false)
        try await session.sendKeys("O\(marker)<Esc>")
        try await Task.sleep(for: .milliseconds(250))
    }

    @Test("저장 안 한 파일이 없으면 빈 목록이고 완료다")
    func noDirtyFilesIsComplete() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/A.kt", contents: "A 원본\n")
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/A.kt", line: 1, recordJump: false)
        try await Task.sleep(for: .milliseconds(300))

        #expect(try await session.dirtyFiles(inProjectRoot: fixture.rootURL).isEmpty)

        let outcome = try await session.saveAll(inProjectRoot: fixture.rootURL)
        // "저장할 게 없었다" 를 실패로 답하면 안 된다.
        #expect(outcome.isComplete)
        #expect(outcome.savedPaths.isEmpty)
    }

    @Test("더티 파일이 프로젝트 상대 경로로 나온다")
    func dirtyFilesAreProjectRelative() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/A.kt", contents: "A 원본\n")
        fixture.write("docs/B.md", contents: "B 원본\n")
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await makeDirty(session, "src/A.kt", marker: "A 수정")
        try await makeDirty(session, "docs/B.md", marker: "B 수정")

        let dirty = try await session.dirtyFiles(inProjectRoot: fixture.rootURL).sorted()

        #expect(dirty == ["docs/B.md", "src/A.kt"])
    }

    // 이 스위트의 존재 이유 — 하나만 저장되고 나머지가 사라지는 것을 막는다.

    @Test("여러 더티 버퍼를 전부 디스크에 쓴다")
    func savesEveryDirtyBuffer() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/A.kt", contents: "A 원본\n")
        fixture.write("src/B.kt", contents: "B 원본\n")
        fixture.write("docs/C.md", contents: "C 원본\n")
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await makeDirty(session, "src/A.kt", marker: "A 수정")
        try await makeDirty(session, "src/B.kt", marker: "B 수정")
        try await makeDirty(session, "docs/C.md", marker: "C 수정")

        let outcome = try await session.saveAll(inProjectRoot: fixture.rootURL)

        #expect(outcome.isComplete)
        #expect(outcome.savedPaths.sorted() == ["docs/C.md", "src/A.kt", "src/B.kt"])
        // 계약이 뭐라 하든 디스크가 진실이다.
        #expect(read(fixture, "src/A.kt").contains("A 수정"))
        #expect(read(fixture, "src/B.kt").contains("B 수정"))
        #expect(read(fixture, "docs/C.md").contains("C 수정"))
        #expect(try await session.dirtyFiles(inProjectRoot: fixture.rootURL).isEmpty)
    }

    @Test("쓸 수 없는 파일은 사유와 함께 실패로 남고 나머지는 저장된다")
    func unwritableFileIsReportedWhileOthersSave() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/A.kt", contents: "A 원본\n")
        fixture.write("src/Locked.kt", contents: "잠긴 원본\n")
        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await makeDirty(session, "src/A.kt", marker: "A 수정")
        try await makeDirty(session, "src/Locked.kt", marker: "잠긴 수정")
        try await session.sendKeys(":setlocal readonly<CR>")
        try await Task.sleep(for: .milliseconds(250))

        let outcome = try await session.saveAll(inProjectRoot: fixture.rootURL)

        // 하나가 실패해도 나머지는 저장돼야 한다 — 첫 실패에서 멈추면 데이터가 남는다.
        #expect(outcome.savedPaths.contains("src/A.kt"))
        #expect(read(fixture, "src/A.kt").contains("A 수정"))

        #expect(outcome.isComplete == false)
        let failure = try #require(outcome.failures.first { $0.path == "src/Locked.kt" })
        // 사유를 뭉개지 않는다 — 사용자가 할 수 있는 일이 사유마다 다르다.
        #expect(!failure.reason.isEmpty)
    }

    // 범위 — 다른 프로젝트·프로젝트 밖 버퍼를 건드리면 W-13 이 막으려던 것보다 나쁜 일이 된다.

    @Test("프로젝트 밖 버퍼는 목록에도 없고 저장되지도 않는다")
    func buffersOutsideTheProjectAreLeftAlone() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/A.kt", contents: "A 원본\n")
        let outside = TemporaryProjectFixture()
        let outsideURL = outside.write("Notes.md", contents: "바깥 원본\n")

        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await makeDirty(session, "src/A.kt", marker: "A 수정")
        // 사용자가 프로젝트 밖 파일을 직접 열었다. 탭을 닫는 것이 이걸 저장할 근거는 아니다.
        try await session.sendKeys(":e \(outsideURL.path)<CR>")
        try await Task.sleep(for: .milliseconds(300))
        try await session.sendKeys("O바깥 수정<Esc>")
        try await Task.sleep(for: .milliseconds(250))

        let dirty = try await session.dirtyFiles(inProjectRoot: fixture.rootURL)
        #expect(dirty == ["src/A.kt"], "프로젝트 밖 버퍼가 목록에 들어왔다")

        let outcome = try await session.saveAll(inProjectRoot: fixture.rootURL)
        #expect(outcome.savedPaths == ["src/A.kt"])

        let outsideOnDisk = (try? String(contentsOf: outsideURL, encoding: .utf8)) ?? ""
        #expect(!outsideOnDisk.contains("바깥 수정"), "프로젝트 밖 파일을 승인 없이 저장했다")
    }

    @Test("이름이 접두로 겹치는 이웃 디렉토리를 자식으로 오인하지 않는다")
    func siblingDirectoryWithSharedPrefixIsNotIncluded() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/A.kt", contents: "A 원본\n")

        // 루트가 `/…/repo` 일 때 `/…/repo-backup` 은 자식이 아니다. 구분자 없이 접두 비교하면
        // 자식으로 잡히고, 다른 트리의 파일을 저장하게 된다.
        let siblingURL = fixture.rootURL.deletingLastPathComponent()
            .appendingPathComponent(fixture.rootURL.lastPathComponent + "-backup")
        try FileManager.default.createDirectory(at: siblingURL, withIntermediateDirectories: true)
        let siblingFile = siblingURL.appendingPathComponent("Sibling.kt")
        try "이웃 원본\n".write(to: siblingFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: siblingURL) }

        let session = try await startSession(fixture)
        defer { Task { await session.shutDown() } }

        try await makeDirty(session, "src/A.kt", marker: "A 수정")
        try await session.sendKeys(":e \(siblingFile.path)<CR>")
        try await Task.sleep(for: .milliseconds(300))
        try await session.sendKeys("O이웃 수정<Esc>")
        try await Task.sleep(for: .milliseconds(250))

        #expect(try await session.dirtyFiles(inProjectRoot: fixture.rootURL) == ["src/A.kt"])

        _ = try await session.saveAll(inProjectRoot: fixture.rootURL)
        let siblingOnDisk = (try? String(contentsOf: siblingFile, encoding: .utf8)) ?? ""
        #expect(!siblingOnDisk.contains("이웃 수정"), "이웃 디렉토리를 자식으로 오인해 저장했다")
    }
}
