import CodeNavigatorContract
import Foundation
import Observation

/// 터미널 패널의 상태.
///
/// 세션은 붙을 때 주입된다 — 모델이 Core 를 직접 알면 화면 상태를 재는 데 진짜 셸이 필요해지고,
/// 그런 테스트는 느리거나 흔들린다.
@MainActor
@Observable
public final class TerminalModel {

    public enum State: Sendable, Hashable {
        case idle
        /// 무엇을 돌리는 중인지. 화면이 "실행 중" 만 말하면 사용자는 무엇이 도는지 모른다.
        case running(name: String)
        case failed(String)
    }

    public private(set) var state: State = .idle
    /// 그릴 준비가 된 프레임. 스냅샷을 뷰에 주면 매 렌더마다 변환이 다시 돌고, 셸 출력처럼
    /// 잦은 갱신에서는 그 비용이 그대로 드러난다.
    public private(set) var gridFrame: GridFrame?
    /// 마지막으로 돌린 설정. 다시 실행할 때 쓴다.
    public private(set) var lastConfiguration: RunConfiguration?
    /// 디버그로 돌렸으면 그 포트. 붙을 때 이 값을 쓴다.
    public private(set) var lastDebugPort: UInt16?

    private var session: (any TerminalSession)?
    private var gridTask: Task<Void, Never>?
    private var gridSize: (columns: Int, rows: Int) = (80, 12)

    public init() {}

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// Runs one configuration. `debugPort` 가 있으면 설정이 정한 방식으로 에이전트를 붙인다.
    public func run(
        _ configuration: RunConfiguration,
        projectRoot: String,
        session: any TerminalSession,
        debugPort: UInt16? = nil
    ) async {
        // 앞의 것을 먼저 끝낸다. 안 끝내면 서버가 포트를 잡은 채 남고, 다음 실행이
        // "포트 사용 중" 으로 실패한다 — 사용자는 원인을 못 찾는다.
        await stop()

        self.session = session
        lastConfiguration = configuration
        // **요청한 포트가 아니라 실제로 열릴 포트를 기억한다.** Gradle 은 5005 로 고정이라,
        // 요청값을 들고 있으면 엉뚱한 데로 붙으러 간다.
        lastDebugPort = nil

        // 에이전트를 명령에 넣을지 환경변수에 넣을지는 설정이 안다. 여기서 다시 추측하면
        // Gradle 런처가 포트를 가로채는 결함이 그대로 돌아온다.
        let inherited = ProcessInfo.processInfo.environment
        let launch: (command: String, environment: [String: String], port: UInt16?)
        if let debugPort {
            let resolved = configuration.debugLaunch(port: debugPort, inheriting: inherited)
            launch = (resolved.command, resolved.environment, resolved.port)
        } else {
            launch = (configuration.command, configuration.mergedEnvironment(inheriting: inherited), nil)
        }
        lastDebugPort = launch.port
        let directory = configuration.resolvedWorkingDirectory(projectRoot: projectRoot)

        do {
            try await session.start(
                command: launch.command,
                workingDirectory: directory,
                environment: launch.environment,
                columns: gridSize.columns,
                rows: gridSize.rows
            )
            state = .running(name: configuration.name)
            startStreamingGrid(from: session)
        } catch {
            // 못 띄운 것을 조용히 넘기지 않는다. 터미널이 빈 채로 있으면 사용자는 명령이
            // 아무것도 출력하지 않은 것으로 읽는다.
            state = .failed("실행하지 못했습니다: \(error)")
        }
    }

    /// 명령 없이 셸만 띄운다 — 사용자가 아무거나 칠 수 있는 상태.
    public func openShell(projectRoot: String, session: any TerminalSession) async {
        await run(
            RunConfiguration(name: "셸", command: "", workingDirectory: "", environment: [:]),
            projectRoot: projectRoot,
            session: session
        )
    }

    private func startStreamingGrid(from session: any TerminalSession) {
        gridTask?.cancel()
        gridTask = Task { [weak self] in
            for await snapshot in await session.gridUpdates() {
                guard let self else { return }
                let frame = GridFrameBuilder.build(from: snapshot)
                await MainActor.run { self.gridFrame = frame }
            }
        }
    }

    public func send(keys: String) async {
        await session?.send(keys: keys)
    }

    public func resize(columns: Int, rows: Int) async {
        // 레이아웃이 끝나기 전의 보고는 버린다. 그리드 뷰는 첫 패스에서 1×1 을 보고하는데,
        // 그 값이 pty 로 가면 libvterm 이 화면을 한 칸으로 줄이면서 **이미 찍힌 줄을 잘라
        // 버린다**. 곧이어 진짜 크기가 와도 잘린 글자는 돌아오지 않는다 — 실제로 서버 기동
        // 로그가 12글자만 남았다.
        //
        // 편집기에서는 같은 보고가 눈에 안 띈다. 버퍼가 원본을 들고 있어서 다시 그리면
        // 되기 때문이다. 터미널의 스크롤백은 그 사본이 없다.
        guard columns >= Metrics.minimumColumns, rows >= Metrics.minimumRows else { return }
        gridSize = (columns, rows)
        await session?.resize(columns: columns, rows: rows)
    }

    private enum Metrics {
        /// 이보다 좁은 터미널은 어차피 못 읽는다. 값 자체보다 "레이아웃 전 보고를 거른다"
        /// 는 뜻이 중요하다 — 실측된 값은 1×1 이었다.
        static let minimumColumns = 20
        static let minimumRows = 3
    }

    public func stop() async {
        gridTask?.cancel()
        gridTask = nil
        await session?.stop()
        session = nil
        // 화면도 비운다. 남겨 두면 끝난 프로세스의 마지막 출력이 계속 떠 있어서, 사용자는
        // 아직 도는 줄 안다.
        gridFrame = nil
        if case .failed = state { return }
        state = .idle
    }
}

