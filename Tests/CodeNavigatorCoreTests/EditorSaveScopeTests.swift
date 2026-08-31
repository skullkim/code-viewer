import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: W-13 "저장 후 닫기" 의 전제 — 저장이 **어디까지** 미치는가
///
/// `:w` 는 현재 버퍼 하나만 쓴다. 더티 버퍼가 여럿인 탭에서 "저장 후 닫기" 를 누르면 하나만
/// 저장되고 나머지가 조용히 사라진다. 그 전에 `:wa` 의 실제 범위를 재 둔다 — 특히 **탭페이지
/// 경계를 아는지**. 모르면 다른 프로젝트 파일까지 쓰게 되고, 그건 더 나쁜 손실이다.
@Suite("저장 범위 — 실측", .serialized)
struct EditorSaveScopeTests {

    private func read(_ fixture: TemporaryProjectFixture, _ relativePath: String) -> String {
        (try? String(
            contentsOf: fixture.rootURL.appendingPathComponent(relativePath), encoding: .utf8
        )) ?? ""
    }

    @Test("`:w` 는 현재 버퍼만 쓴다 — W-13 이 이걸로는 안 된다는 증거")
    func writeOnlySavesTheCurrentBuffer() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/A.kt", contents: "A 원본\n")
        fixture.write("src/B.kt", contents: "B 원본\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await session.shutDown() } }

        try await session.openFile(atRelativePath: "src/A.kt", line: 1, recordJump: false)
        try await session.sendKeys("OA 수정<Esc>")
        try await session.openFile(atRelativePath: "src/B.kt", line: 1, recordJump: false)
        try await session.sendKeys("OB 수정<Esc>")
        try await Task.sleep(for: .milliseconds(400))

        try await session.save()
        try await Task.sleep(for: .milliseconds(400))

        // 현재 버퍼(B)만 디스크에 반영된다. A 의 수정은 아직 버퍼에만 있다.
        #expect(read(fixture, "src/B.kt").contains("B 수정"))
        #expect(!read(fixture, "src/A.kt").contains("A 수정"), "`:w` 가 다른 버퍼까지 썼다면 전제가 바뀐다")
    }

    @Test("`:wa` 는 탭페이지 경계를 모른다 — 다른 탭의 더티 버퍼까지 쓴다")
    func writeAllIgnoresTabpageBoundaries() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/A.kt", contents: "A 원본\n")
        fixture.write("src/B.kt", contents: "B 원본\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        defer { Task { await session.shutDown() } }

        // A 를 1번 탭페이지에서 수정
        try await session.openFile(atRelativePath: "src/A.kt", line: 1, recordJump: false)
        try await session.sendKeys("OA 수정<Esc>")
        try await Task.sleep(for: .milliseconds(300))

        // B 를 **새 탭페이지**에서 수정 — 모델 B 가 프로젝트를 가르는 방식이다
        try await session.sendKeys(":tabnew<CR>")
        try await Task.sleep(for: .milliseconds(300))
        try await session.openFile(atRelativePath: "src/B.kt", line: 1, recordJump: false)
        try await session.sendKeys("OB 수정<Esc>")
        try await Task.sleep(for: .milliseconds(400))

        try await session.sendKeys(":wa<CR>")
        try await Task.sleep(for: .milliseconds(600))

        // 둘 다 써졌다면 `:wa` 로는 탭 범위 저장을 만들 수 없다는 뜻이다.
        let savedA = read(fixture, "src/A.kt").contains("A 수정")
        let savedB = read(fixture, "src/B.kt").contains("B 수정")
        #expect(savedB, "현재 탭페이지의 버퍼는 당연히 써져야 한다")
        #expect(savedA, "다른 탭페이지의 버퍼도 써졌다 — `:wa` 는 탭 경계를 모른다")
    }
}
