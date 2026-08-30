import Testing
import Foundation
@testable import CodeNavigatorCore

/// ADR-0008 chose one Neovim process with a tabpage per project because it costs 15.5MB for four
/// projects where a process each costs 60.1MB. That decision bought memory; what it did **not**
/// establish is whether INV-5's isolation actually holds in that shape. Isolation maintained by
/// discipline rather than by the runtime is a silent bug waiting to happen, so this measures which
/// parts are really isolated before the factory is built on top of it.
@Suite("탭페이지 격리 실측 (ADR-0008 모델 B)", .serialized)
struct TabPageIsolationSpikeTests {

    @Test("탭페이지가 무엇을 격리하고 무엇을 격리하지 않는지 잰다")
    func measureWhatTabPagesActuallyIsolate() async throws {
        let projectA = TemporaryProjectFixture()
        projectA.write("a.txt", contents: "alpha")
        let projectB = TemporaryProjectFixture()
        projectB.write("b.txt", contents: "bravo")

        let channel = NeovimChannel()
        try await channel.start(
            executableURL: try NeovimExecutableLocator().locate(),
            workingDirectory: projectA.rootURL
        )
        // UI 를 붙이지 않는다. 여기서 재는 것은 그리드가 아니라 탭페이지의 상태 격리이고,
        // nvim_command/nvim_eval 은 부착 없이도 답한다.

        func eval(_ expression: String) async throws -> String {
            let value = try await channel.request("nvim_eval", [.string(expression)])
            return value.stringValue ?? "\(value)"
        }
        func command(_ text: String) async throws {
            _ = try await channel.request("nvim_command", [.string(text)])
        }

        // 탭 A: 프로젝트 A 로 tcd 하고 파일을 연다.
        try await command("tcd \(projectA.rootURL.path)")
        try await command("edit \(projectA.rootURL.appendingPathComponent("a.txt").path)")
        try await command("let @x = 'from-tab-A'")
        let cwdA = try await eval("getcwd()")

        // 탭 B: 새 탭페이지, 프로젝트 B 로 tcd.
        try await command("tabnew")
        try await command("tcd \(projectB.rootURL.path)")
        try await command("edit \(projectB.rootURL.appendingPathComponent("b.txt").path)")
        let cwdB = try await eval("getcwd()")

        // 이제 탭 B 에서 물어본다 — 무엇이 보이는가.
        let registerInB = try await eval("@x")
        let bufferNamesInB = try await eval("join(map(filter(range(1, bufnr('$')), 'buflisted(v:val)'), 'fnamemodify(bufname(v:val), \":t\")'), ',')")
        let windowBuffersInB = try await eval("join(map(tabpagebuflist(), 'fnamemodify(bufname(v:val), \":t\")'), ',')")

        print("""

        ═══ 탭페이지 격리 실측 ═══
          작업 디렉토리   격리됨=\(cwdA != cwdB)
          레지스터 @x     탭B에서 '\(registerInB)'  → 격리됨=\(registerInB != "from-tab-A")
          버퍼 목록       탭B에서 [\(bufferNamesInB)]  → 격리됨=\(!bufferNamesInB.contains("a.txt"))
          탭B의 창 버퍼   [\(windowBuffersInB)]
        ═════════════════════════

        """)

        // 격리된다 — `tcd` 는 탭페이지 지역이다. 프로젝트별 상대 경로가 이것 위에 선다.
        #expect(cwdA != cwdB, "작업 디렉토리가 탭 사이에 격리되지 않는다")

        // 격리되는 창 단위. 탭 B 의 창은 자기 프로젝트 파일만 보여 준다.
        #expect(windowBuffersInB.contains("b.txt"))
        #expect(windowBuffersInB.contains("a.txt") == false)

        // 🔴 격리되지 **않는다**. 이 둘은 결함이 아니라 Neovim 의 사실이고, 여기 적어 두는
        // 이유는 ADR-0009 가 이 사실 위에 서 있기 때문이다. 언젠가 이 단언이 실패하면
        // 그건 런타임이 바뀌었다는 뜻이고, 그때 ADR 을 다시 읽어야 한다.
        #expect(registerInB == "from-tab-A", "레지스터가 전역이 아니게 됐다 — ADR-0009 재검토")
        #expect(bufferNamesInB.contains("a.txt"), "버퍼 목록이 전역이 아니게 됐다 — ADR-0009 재검토")

        await channel.terminate()
    }
}
