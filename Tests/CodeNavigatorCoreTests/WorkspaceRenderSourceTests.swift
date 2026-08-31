import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-013 — 렌더가 **어느 사본**을 그리는가 (살아 있는 경로에서)
///
/// 리더가 디스크 기준을 뒤집고 버퍼 우선으로 판정한 이유는 *"미리보기는 방금 쓴 것이 어떻게
/// 보이는지 보려고 여는 것이라, 저장된 사본을 그리면 틀린 화면"* 이었다. 그 판정을 지키는 검사가
/// 살아 있는 경로(`ProjectWorkspaceEngine`)에 없었다 — 있던 것은 앱이 쓰지 않는 타입 위에 있었다.
///
/// **실제 Neovim 이 필요하다.** 편집기를 띄우지 않으면 버퍼가 없어 항상 디스크로 떨어지고,
/// 그러면 "버퍼가 이긴다" 를 영원히 통과시킨다.
@Suite("워크스페이스 렌더 원문 — 버퍼 우선", .serialized)
struct WorkspaceRenderSourceTests {

    private func makeWorkspace() -> ProjectWorkspaceEngine {
        // 오버라이드 없이 = 진짜 nvim.
        ProjectWorkspaceEngine(columns: 80, rows: 24)
    }

    /// 절대 경로로 연다 — 탭↔에디터 루트 배선과 무관하게 "그 파일을 편집기가 들고 있다" 를 만든다.
    ///
    /// 고정 대기를 쓰지 않는다. `sendKeys` 는 편집기가 아직 붙기 전이면 키를 **큐에 담아 두고**
    /// 돌아오므로, 부하가 걸린 풀런에서는 그 키가 렌더를 읽은 **뒤에** 소화될 수 있다. 그러면
    /// 버퍼에 수정이 없는 채로 읽어 "버퍼가 이긴다" 가 이유 없이 실패한다 — 기다림의 길이가
    /// 아니라 순서의 문제이므로, 대기를 늘리는 대신 **상태를 확인**한다.
    private func openInEditorAndModify(
        _ workspace: ProjectWorkspaceEngine,
        fileURL: URL,
        marker: String
    ) async throws {
        let session = await workspace.editorSession
        try await session.sendKeys(":e \(fileURL.path)<CR>")
        try await waitUntil("편집기가 \(fileURL.lastPathComponent) 를 든다") {
            (try? await session.bufferLines(forFileAt: fileURL.path)) != nil
        }

        try await session.sendKeys("O\(marker)<Esc>")
        try await waitUntil("버퍼에 '\(marker)' 가 들어간다") {
            let lines = (try? await session.bufferLines(forFileAt: fileURL.path)) ?? nil
            return lines?.contains { $0.contains(marker) } ?? false
        }
    }

    /// 조건이 참이 될 때까지 기다린다. 되지 않으면 **무엇을 기다렸는지** 말하고 실패한다 —
    /// 조용히 넘어가면 뒤의 단언이 엉뚱한 이유로 실패해 원인을 찾는 데 시간을 쓴다.
    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(10),
        _ condition: () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("기다린 조건이 끝내 성립하지 않았다: \(description)")
    }

    @Test("저장하지 않은 버퍼가 디스크를 이기고, 다른 탭은 영향받지 않는다")
    func unsavedBufferWinsAndOtherTabsAreUnaffected() async throws {
        let alpha = TemporaryProjectFixture()
        alpha.write("README.md", contents: "# alpha 디스크\n")
        let beta = TemporaryProjectFixture()
        beta.write("README.md", contents: "# beta 디스크\n")

        let workspace = makeWorkspace()
        defer { Task { await workspace.shutDown() } }

        let first = try await workspace.openProject(at: alpha.rootURL)
        let second = try await workspace.openProject(at: beta.rootURL)

        try await openInEditorAndModify(
            workspace,
            fileURL: beta.rootURL.appendingPathComponent("README.md"),
            marker: "beta 버퍼에만"
        )

        let fromBeta = try await workspace.renderSource(atRelativePath: "README.md", in: second.tab.id)
        let fromAlpha = try await workspace.renderSource(atRelativePath: "README.md", in: first.tab.id)

        // 편집기가 들고 있는 쪽은 저장 안 한 내용이 보여야 한다.
        #expect(fromBeta.text.contains("beta 버퍼에만"), "저장 안 한 변경이 렌더에 안 보인다")
        #expect(fromBeta.origin == .editorBuffer, "버퍼에서 읽고도 출처를 savedFile 로 말한다")

        // 두 탭 다 README.md 를 갖는다. 탭을 잘못 풀면 여기서 alpha 가 beta 내용을 보여준다.
        #expect(fromAlpha.text == "# alpha 디스크\n")
        #expect(fromAlpha.origin == .savedFile)

        // 렌더는 읽기만 한다 — 디스크는 그대로여야 한다 (INV-3).
        let betaOnDisk = try String(
            contentsOf: beta.rootURL.appendingPathComponent("README.md"), encoding: .utf8
        )
        #expect(betaOnDisk == "# beta 디스크\n")
    }

    @Test("편집기가 들고 있지 않은 파일은 디스크에서 읽고 출처가 savedFile 이다")
    func untouchedFileComesFromDisk() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("docs/Guide.md", contents: "# 안내\n")
        let workspace = makeWorkspace()
        defer { Task { await workspace.shutDown() } }

        let opened = try await workspace.openProject(at: fixture.rootURL)
        let source = try await workspace.renderSource(atRelativePath: "docs/Guide.md", in: opened.tab.id)

        #expect(source.text == "# 안내\n")
        #expect(source.origin == .savedFile)
    }

    @Test("빈 파일은 성공이다 — 에러를 만들지 않는다")
    func emptyFileIsSuccess() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("docs/Empty.md", contents: "")
        let workspace = makeWorkspace()
        defer { Task { await workspace.shutDown() } }

        let opened = try await workspace.openProject(at: fixture.rootURL)
        let source = try await workspace.renderSource(atRelativePath: "docs/Empty.md", in: opened.tab.id)

        #expect(source.text.isEmpty)
    }

    @Test("없는 파일은 파일 없음으로 실패한다")
    func missingFileFailsAsNotFound() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("docs/Guide.md", contents: "# 안내\n")
        let workspace = makeWorkspace()
        defer { Task { await workspace.shutDown() } }

        let opened = try await workspace.openProject(at: fixture.rootURL)

        await #expect(throws: NavigatorError.fileNotFound(path: "docs/Nope.md")) {
            _ = try await workspace.renderSource(atRelativePath: "docs/Nope.md", in: opened.tab.id)
        }
    }

    @Test("UTF-8 로 읽을 수 없는 파일은 깨진 글자 대신 실패한다")
    func undecodableFileFails() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("docs/Guide.md", contents: "# 안내\n")
        let binaryURL = fixture.rootURL.appendingPathComponent("docs/Blob.md")
        try Data([0xFF, 0xFE, 0x00, 0x01, 0xFF]).write(to: binaryURL)

        let workspace = makeWorkspace()
        defer { Task { await workspace.shutDown() } }

        let opened = try await workspace.openProject(at: fixture.rootURL)

        await #expect(throws: NavigatorError.fileNotDecodable(path: "docs/Blob.md")) {
            _ = try await workspace.renderSource(atRelativePath: "docs/Blob.md", in: opened.tab.id)
        }
    }
}
