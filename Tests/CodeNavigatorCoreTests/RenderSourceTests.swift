import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-013 AC-1·AC-5·AC-6, INV-6 (렌더가 읽는 원문의 출처와 경계)
///
/// 렌더는 "방금 쓴 것이 어떻게 보이나"를 보려고 여는 경우가 대부분이라 **버퍼가 디스크를 이긴다**.
/// 그래서 이 스위트의 핵심은 두 가지다 — 버퍼가 실제로 이기는가, 그리고 **어느 쪽인지 말해주는가**.
/// 둘 다 "항상 `.savedFile` 을 돌려주는" 구현으로도 통과하는 테스트를 쓰기 쉬운 자리다.
@Suite("RenderSource — 렌더 원문", .serialized)
struct RenderSourceTests {

    private func startEngine(_ fixture: TemporaryProjectFixture) async throws -> CodeNavigatorEngine {
        let engine = CodeNavigatorEngine()
        try await engine.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        return engine
    }

    // 디스크 경로.

    @Test("편집기가 들고 있지 않은 파일은 디스크에서 읽고 출처를 savedFile 로 말한다")
    func readsFromDiskWhenEditorDoesNotHoldTheFile() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("docs/README.md", contents: "# 제목\n본문\n")
        let engine = try await startEngine(fixture)
        defer { Task { await engine.shutDown() } }

        let source = try await engine.renderSource(atRelativePath: "docs/README.md")

        #expect(source.text == "# 제목\n본문\n")
        #expect(source.origin == .savedFile)
        #expect(source.path == "docs/README.md")
    }

    @Test("빈 파일은 성공이다 — 에러를 만들지 않는다")
    func emptyFileIsSuccess() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("docs/Empty.md", contents: "")
        let engine = try await startEngine(fixture)
        defer { Task { await engine.shutDown() } }

        let source = try await engine.renderSource(atRelativePath: "docs/Empty.md")

        #expect(source.text.isEmpty)
        #expect(source.origin == .savedFile)
    }

    // 버퍼 우선 — 이 스위트의 존재 이유.

    @Test("편집기가 들고 있으면 저장하지 않은 내용이 보이고 출처가 editorBuffer 다")
    func unsavedBufferWinsOverDisk() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("docs/Notes.md", contents: "디스크에 있는 줄\n")
        let engine = try await startEngine(fixture)
        defer { Task { await engine.shutDown() } }

        try await engine.editor.openFile(atRelativePath: "docs/Notes.md", line: 1, recordJump: false)
        try await engine.editor.sendKeys("O버퍼에만 있는 줄<Esc>")
        try await Task.sleep(for: .milliseconds(400))

        let source = try await engine.renderSource(atRelativePath: "docs/Notes.md")

        // 디스크에는 없는 줄이다 — 저장하지 않았다.
        #expect(source.text.contains("버퍼에만 있는 줄"), "저장 안 한 변경이 렌더에 반영되지 않았다")
        #expect(source.origin == .editorBuffer, "버퍼에서 읽고도 출처를 savedFile 로 말한다")

        // 디스크는 여전히 원래 내용이어야 한다 — 렌더는 읽기만 한다(INV-3).
        let onDisk = try String(
            contentsOf: fixture.rootURL.appendingPathComponent("docs/Notes.md"), encoding: .utf8
        )
        #expect(onDisk == "디스크에 있는 줄\n")
    }

    @Test("같은 세션에서도 열지 않은 파일은 디스크에서 읽는다 — 출처가 실제로 갈린다")
    func originDistinguishesOpenFileFromOthers() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("docs/Open.md", contents: "열린 파일\n")
        fixture.write("docs/Closed.md", contents: "안 열린 파일\n")
        let engine = try await startEngine(fixture)
        defer { Task { await engine.shutDown() } }

        try await engine.editor.openFile(atRelativePath: "docs/Open.md", line: 1, recordJump: false)
        try await Task.sleep(for: .milliseconds(400))

        let opened = try await engine.renderSource(atRelativePath: "docs/Open.md")
        let closed = try await engine.renderSource(atRelativePath: "docs/Closed.md")

        #expect(opened.origin == .editorBuffer)
        #expect(closed.origin == .savedFile)
        #expect(closed.text == "안 열린 파일\n")
    }

    // 상한 — 인덱싱 상한(1MiB)과 렌더 상한(2MB) 사이가 함정 구간이다.

    @Test("1MiB 를 넘고 2MB 이하인 파일은 성공한다 — 인덱싱 상한을 빌려 쓰면 여기서 걸린다")
    func fileBetweenIndexingLimitAndRenderLimitSucceeds() async throws {
        let fixture = TemporaryProjectFixture()
        let byteCount = 1_500_000
        fixture.write("docs/Big.md", contents: String(repeating: "a", count: byteCount))
        let engine = try await startEngine(fixture)
        defer { Task { await engine.shutDown() } }

        let source = try await engine.renderSource(atRelativePath: "docs/Big.md")

        #expect(source.text.utf8.count == byteCount)
    }

    @Test("2MB 를 넘으면 잘라내지 않고 tooLarge 로 실패한다")
    func fileOverRenderLimitFailsAsTooLarge() async throws {
        let fixture = TemporaryProjectFixture()
        let byteCount = RenderSource.maximumByteSize + 1_000
        fixture.write("docs/Huge.md", contents: String(repeating: "a", count: byteCount))
        let engine = try await startEngine(fixture)
        defer { Task { await engine.shutDown() } }

        await #expect(throws: NavigatorError.self) {
            _ = try await engine.renderSource(atRelativePath: "docs/Huge.md")
        }
    }

    // 경계와 실패.

    @Test("프로젝트 밖을 가리키면 잘못된 경로로 거부된다 (INV-6)")
    func pathOutsideProjectIsRejected() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("docs/README.md", contents: "본문\n")
        let engine = try await startEngine(fixture)
        defer { Task { await engine.shutDown() } }

        await #expect(throws: NavigatorError.invalidPath("../escape.md")) {
            _ = try await engine.renderSource(atRelativePath: "../escape.md")
        }
    }

    @Test("없는 파일은 파일 없음으로 실패한다")
    func missingFileFailsAsNotFound() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("docs/README.md", contents: "본문\n")
        let engine = try await startEngine(fixture)
        defer { Task { await engine.shutDown() } }

        await #expect(throws: NavigatorError.fileNotFound(path: "docs/Nope.md")) {
            _ = try await engine.renderSource(atRelativePath: "docs/Nope.md")
        }
    }

    @Test("UTF-8 로 읽을 수 없는 파일은 깨진 글자 대신 실패한다")
    func undecodableFileFails() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("docs/README.md", contents: "본문\n")
        let binaryURL = fixture.rootURL.appendingPathComponent("docs/Blob.md")
        try Data([0xFF, 0xFE, 0x00, 0x01, 0xFF]).write(to: binaryURL)
        let engine = try await startEngine(fixture)
        defer { Task { await engine.shutDown() } }

        await #expect(throws: NavigatorError.fileNotDecodable(path: "docs/Blob.md")) {
            _ = try await engine.renderSource(atRelativePath: "docs/Blob.md")
        }
    }
}
