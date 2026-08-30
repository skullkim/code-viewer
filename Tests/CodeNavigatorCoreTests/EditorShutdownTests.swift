import Testing
import Foundation

import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: 열린 결함 D-2 (앱 종료 후 `nvim --embed` 고아 프로세스)
///
/// 실측 근거: `PPID=1` 인 nvim 이 최대 6시간 살아 있었고 5개가 75MB 를 잡았다. 그리고 그 상태의
/// nvim 은 **SIGTERM 을 무시한다** — `terminate()` 한 번으로 죽는다고 가정할 수 없다.
///
/// `shutDown()` 이 "요청을 보냈다"가 아니라 **"자식이 실제로 사라졌다"** 까지 책임지는지 고정한다.
@Suite("EditorSession — 종료가 자식 프로세스를 실제로 정리한다", .serialized)
struct EditorShutdownTests {

    /// 프로세스가 살아 있는지 신호 0 으로 묻는다(죽이지 않고 존재만 확인).
    private func isAlive(_ processIdentifier: Int32) -> Bool {
        kill(processIdentifier, 0) == 0
    }

    private func waitUntilGone(_ processIdentifier: Int32, within budget: Duration) async -> Duration? {
        let step = Duration.milliseconds(20)
        var waited = Duration.zero
        while waited < budget {
            if !isAlive(processIdentifier) {
                return waited
            }
            try? await Task.sleep(for: step)
            waited += step
        }
        return nil
    }

    @Test("shutDown() 이 돌아온 뒤 자식 nvim 이 실제로 사라진다")
    func shutDownActuallyReapsTheChildProcess() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class App\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)

        let processIdentifier = try #require(await session.processIdentifierForTesting())
        // 양성 대조: 지금은 살아 있어야 한다. 그래야 "사라졌다"가 의미를 갖는다.
        #expect(isAlive(processIdentifier))

        await session.shutDown()

        let elapsed = await waitUntilGone(processIdentifier, within: .seconds(5))
        #expect(elapsed != nil, "shutDown() 뒤에도 자식 nvim 이 살아 있다 — 고아가 된다")
        if let elapsed {
            print("[종료] shutDown 후 자식이 사라지기까지 \(elapsed)")
        }
    }

    @Test("파일을 열어 작업 중이던 세션도 종료되면 자식이 사라진다")
    func shutDownReapsChildEvenAfterEditing() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class App\n")
        let session = NeovimEditorSession()
        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)

        try await session.openFile(atRelativePath: "src/App.kt", line: 1, recordJump: false)
        try await session.sendKeys("ofun added() {}<Esc>")
        try await Task.sleep(for: .milliseconds(300))

        let processIdentifier = try #require(await session.processIdentifierForTesting())
        #expect(isAlive(processIdentifier))

        // 저장하지 않은 변경이 있는 상태다 — nvim 이 물어보느라 안 죽는 경우가 여기서 드러난다.
        await session.shutDown()

        let elapsed = await waitUntilGone(processIdentifier, within: .seconds(5))
        #expect(elapsed != nil, "더티 버퍼가 있으면 종료되지 않는다 — 사용자가 앱을 끄면 고아가 남는다")
        if let elapsed {
            print("[종료] 더티 상태에서 자식이 사라지기까지 \(elapsed)")
        }
    }
}
