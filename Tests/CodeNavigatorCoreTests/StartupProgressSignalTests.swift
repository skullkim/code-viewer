import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// A start-up that takes twenty seconds must not look like a frozen application. The interface
/// needs to know "this is in progress" *while* it is in progress — not only after it fails.
@Suite("기동 진행 신호 — 20초 침묵을 막을 재료가 계약에 있는가", .serialized)
struct StartupProgressSignalTests {

    @Test("느린 기동 중에 connecting 상태가 먼저 흘러나온다")
    func connectingIsPublishedBeforeTheWait() async throws {
        let fixture = TemporaryProjectFixture()
        // 버전은 답하지만 --embed 로는 침묵하는 가짜 편집기 — 기동이 예산을 다 쓴다.
        let editor = fixture.write("mute-nvim", contents: """
        #!/bin/sh
        case "$1" in
          --version) echo "NVIM v0.12.5"; exit 0 ;;
        esac
        sleep 120
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: editor.path)

        let session = NeovimEditorSession(
            executableLocator: NeovimExecutableLocator(wellKnownPaths: []),
            executableOverridePath: editor.path
        )

        // 기동 전에 구독한다 — 프론트가 하는 것과 같은 순서.
        let states = await session.stateUpdates()

        let collector = Task { () -> [EditorSessionState] in
            var seen: [EditorSessionState] = []
            for await state in states {
                seen.append(state)
                if case .startupFailed = state { break }
            }
            return seen
        }

        _ = try? await session.startForTesting(
            projectRoot: fixture.rootURL, columns: 80, rows: 24, startupTimeout: .milliseconds(500)
        )
        let observed = await collector.value

        // 실패보다 먼저 "진행 중"이 나와야 한다. 이것이 없으면 화면은 침묵할 수밖에 없다.
        let connectingIndex = observed.firstIndex { $0 == .connecting }
        let failedIndex = observed.firstIndex { if case .startupFailed = $0 { return true }; return false }
        #expect(connectingIndex != nil, "관측된 상태: \(observed)")
        if let connectingIndex, let failedIndex {
            #expect(connectingIndex < failedIndex, "진행 중이 실패보다 먼저 와야 한다: \(observed)")
        }
    }

    @Test("성공 기동에서도 connecting 을 거쳐 connected 로 간다")
    func successfulStartupAlsoPassesThroughConnecting() async throws {
        let fixture = TemporaryProjectFixture()
        let session = NeovimEditorSession()
        let states = await session.stateUpdates()

        let collector = Task { () -> [EditorSessionState] in
            var seen: [EditorSessionState] = []
            for await state in states {
                seen.append(state)
                if state == .connected { break }
            }
            return seen
        }

        try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        let observed = await collector.value
        await session.shutDown()

        #expect(observed.contains(.connecting), "관측된 상태: \(observed)")
        #expect(observed.last == .connected)
    }
}
