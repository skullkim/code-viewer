import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Start-up can fail for reasons that send the user somewhere completely different. Reporting
/// them as one thing is how a running editor got described as "not installed", telling the user
/// to reinstall software already in front of them.
@Suite("기동 실패 종류 — 사용자를 다른 곳으로 보낸다", .serialized)
struct EditorStartupFailureKindTests {

    private func startupFailure(from session: NeovimEditorSession) async -> EditorStartupFailure? {
        guard case .startupFailed(let failure) = await session.state() else { return nil }
        return failure
    }

    @Test("실행 파일이 없으면 notInstalled")
    func reportsNotInstalled() async throws {
        let fixture = TemporaryProjectFixture()
        // 알려진 경로를 비워도 로케이터는 PATH 를 먼저 본다 — 실제 nvim 이 거기 있으므로
        // 지정 경로까지 없는 곳으로 줘야 "설치돼 있지 않은 머신"이 재현된다.
        let session = NeovimEditorSession(
            executableLocator: NeovimExecutableLocator(wellKnownPaths: []),
            executableOverridePath: "/nonexistent/nvim"
        )
        await #expect(throws: (any Error).self) {
            try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        }

        let failure = try #require(await startupFailure(from: session))
        #expect(failure.kind == .notInstalled)
        #expect(failure.foundVersion == nil)
        #expect(failure.searchedPaths.isEmpty == false)
    }

    @Test("실행할 수 없는 파일이면 notInstalled — 있지만 못 쓴다")
    func reportsUnusableExecutableAsNotInstalled() async throws {
        let fixture = TemporaryProjectFixture()
        // 존재하지만 실행 불가한 파일을 지정한다.
        let fake = fixture.write("fake-nvim", contents: "not an executable")
        let session = NeovimEditorSession(
            executableLocator: NeovimExecutableLocator(wellKnownPaths: []),
            executableOverridePath: fake.path
        )
        await #expect(throws: (any Error).self) {
            try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        }

        let failure = try #require(await startupFailure(from: session))
        #expect(failure.kind == .notInstalled)
    }

    @Test("버전이 낮으면 versionTooOld 이고 실측 버전을 싣는다")
    func reportsVersionTooOldWithTheFoundVersion() async throws {
        let fixture = TemporaryProjectFixture()
        // 항상 낡은 버전을 보고하는 가짜 nvim.
        let fake = fixture.write("old-nvim", contents: "#!/bin/sh\necho 'NVIM v0.4.2'\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let session = NeovimEditorSession(
            executableLocator: NeovimExecutableLocator(wellKnownPaths: []),
            executableOverridePath: fake.path
        )
        await #expect(throws: (any Error).self) {
            try await session.start(projectRoot: fixture.rootURL, columns: 80, rows: 24)
        }

        let failure = try #require(await startupFailure(from: session))
        #expect(failure.kind == .versionTooOld)
        #expect(failure.foundVersion == "0.4.2")
        #expect(failure.requiredVersion == "0.9.0")
    }

    @Test("응답이 없으면 unresponsive — notInstalled 로 뭉개지 않는다")
    func reportsUnresponsiveWhenTheHandshakeNeverCompletes() async throws {
        let fixture = TemporaryProjectFixture()
        // 버전은 제대로 답하지만 --embed 로는 아무 응답도 하지 않는 가짜 nvim.
        // 실행 파일은 있고 프로세스도 뜬다 — "없다"고 말하면 거짓말이 되는 상황이다.
        let fake = fixture.write("mute-nvim", contents: """
        #!/bin/sh
        case "$1" in
          --version) echo "NVIM v0.12.5"; exit 0 ;;
        esac
        sleep 120
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let session = NeovimEditorSession(
            executableLocator: NeovimExecutableLocator(wellKnownPaths: []),
            executableOverridePath: fake.path
        )
        // 기동 예산 전체를 기다리지 않도록 짧은 예산으로 확인한다.
        await #expect(throws: (any Error).self) {
            try await session.startForTesting(
                projectRoot: fixture.rootURL, columns: 80, rows: 24,
                startupTimeout: .milliseconds(400)
            )
        }

        let failure = try #require(await startupFailure(from: session))
        #expect(failure.kind == .unresponsive, "종류=\(failure.kind) 사유=\(failure.reason)")
        // 버전은 읽혔으므로 실려 있어야 한다 — "없다"가 아니라는 증거다.
        #expect(failure.foundVersion == "0.12.5")
    }

    @Test("네 종류가 모두 서로 다른 안내로 갈린다")
    func everyKindIsDistinguishable() {
        #expect(Set(EditorStartupFailureKind.allCases).count == 4)
    }
}

@Suite("기동 실패가 스스로 진단 정보를 싣는다", .serialized)
struct StartupFailureDiagnosticsTests {

    @Test("응답 없음 실패에 단계별 경과 시간이 실린다")
    func unresponsiveFailureCarriesStageTimings() async throws {
        let fixture = TemporaryProjectFixture()
        let fake = fixture.write("mute-nvim", contents: """
        #!/bin/sh
        case "$1" in
          --version) echo "NVIM v0.12.5"; exit 0 ;;
        esac
        sleep 120
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let session = NeovimEditorSession(
            executableLocator: NeovimExecutableLocator(wellKnownPaths: []),
            executableOverridePath: fake.path
        )
        _ = try? await session.startForTesting(
            projectRoot: fixture.rootURL, columns: 80, rows: 24, startupTimeout: .milliseconds(300)
        )

        guard case .startupFailed(let failure) = await session.state() else {
            Issue.record("기동 실패 상태여야 한다")
            return
        }
        // 재현되지 않는 실패라, 다음 발생이 데이터가 되어야 한다.
        #expect(failure.reason.contains("단계별 경과"), "사유: \(failure.reason)")
        #expect(failure.reason.contains("탐색"), "탐색 단계가 빠졌다: \(failure.reason)")
        #expect(failure.reason.contains("기동"), "기동 단계가 빠졌다: \(failure.reason)")
    }
}
