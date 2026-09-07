import CodeNavigatorContract
import Foundation

/// 앱 안의 진짜 터미널.
///
/// **VT100 파서와 PTY 를 직접 쓰지 않는다.** 우리는 이미 Neovim 을 번들하고 있고, Neovim 의
/// `:terminal` 은 libvterm 기반의 완전한 터미널 에뮬레이터다 — 색, 커서 모양, 스크롤백,
/// 창 크기 변경까지 다 된다. 그걸 직접 쓰면 그 하나하나가 우리 결함이 된다.
///
/// UI 프로토콜도 이미 다룬다. 그리드 렌더러·키 입력·마우스가 그대로 재사용되므로 화면 쪽에
/// 새로 쓸 것이 거의 없다.
///
/// **편집기와 다른 프로세스다.** 같은 인스턴스를 쓰면 터미널 버퍼가 편집기 자리를 차지하고,
/// 탭 전환이 서로를 밀어낸다.
public actor NeovimTerminalSession: TerminalSession {

    /// 터미널 nvim 은 `--clean` 으로 띄운다.
    ///
    /// 편집기는 INV-4 때문에 사용자 설정을 읽지만 터미널은 다르다 — 사용자 플러그인이 키를
    /// 가로채면 셸에 글자가 안 들어가고, 그 증상은 "터미널이 고장났다" 로 보인다. 여기서는
    /// 예측 가능한 쪽이 낫다.
    static let cleanArguments = ["--clean"]

    private let executableLocator = NeovimExecutableLocator()
    private var channel: NeovimChannel?
    private var gridState = NeovimGridState()
    private var gridBroadcaster = EventBroadcaster<EditorGridSnapshot>()
    private var notificationTask: Task<Void, Never>?
    private var gridSize: (columns: Int, rows: Int) = (80, 12)
    public private(set) var isRunning = false

    public init() {}

    public func gridUpdates() async -> AsyncStream<EditorGridSnapshot> {
        gridBroadcaster.subscribe { [weak self] identifier in
            Task { await self?.unsubscribe(identifier) }
        }
    }

    private func unsubscribe(_ identifier: Int) {
        gridBroadcaster.unsubscribe(identifier)
    }

    /// Starts a shell running `command` in `workingDirectory` with `environment`.
    ///
    /// - Parameter command: 비우면 그냥 셸을 띄운다 — 사용자가 아무거나 칠 수 있는 상태.
    public func start(
        command: String,
        workingDirectory: String,
        environment: [String: String],
        columns: Int,
        rows: Int
    ) async throws {
        await stop()

        gridSize = (max(columns, 1), max(rows, 1))
        let executableURL = try executableLocator.locate()
        let channel = NeovimChannel()

        // 환경은 **nvim 프로세스에** 준다. `:terminal` 이 띄우는 셸이 그것을 물려받는다 —
        // Lua 로 넘기면 값에 든 따옴표·공백·줄바꿈을 우리가 이스케이프해야 하고, 그건
        // 사용자가 적은 환경변수 하나로 명령이 깨지는 길이다.
        try await channel.start(
            executableURL: executableURL,
            arguments: Self.cleanArguments,
            environment: environment,
            workingDirectory: URL(fileURLWithPath: workingDirectory)
        )
        self.channel = channel

        let notifications = await channel.notifications()
        notificationTask = Task { [weak self] in
            for await notification in notifications {
                await self?.handle(notification)
            }
        }

        try await channel.request(
            "nvim_ui_attach",
            [
                .integer(Int64(gridSize.columns)),
                .integer(Int64(gridSize.rows)),
                .map([
                    MessagePackKeyValuePair(key: .string("ext_linegrid"), value: .boolean(true)),
                    MessagePackKeyValuePair(key: .string("rgb"), value: .boolean(true)),
                ]),
            ]
        )

        // 화면을 터미널만 남긴다. 상태줄과 탭줄은 앱이 이미 그리고 있어서, 켜 두면 같은
        // 정보가 두 번 나오고 터미널이 그만큼 좁아진다.
        // `noshowmode` 와 `cmdheight=0` 은 맨 아랫줄을 되찾는다. 12줄짜리 패널에서 한 줄은
        // 8%다. `-- TERMINAL --` 은 우리 머리줄이 이미 "실행 중 — 서버" 로 말하고 있어서,
        // 그대로 두면 같은 사실이 두 번 나오면서 자리만 먹는다.
        for option in [
            "laststatus=0", "showtabline=0", "noruler", "noshowcmd", "noshowmode",
            "cmdheight=0", "signcolumn=no", "nonumber",
        ] {
            _ = try? await channel.request("nvim_command", [.string("set \(option)")])
        }

        // 명령을 Lua 인자로 넘긴다. 문자열에 박아 넣으면 따옴표 하나에 깨진다.
        let script = """
        local arguments = ...
        local command = arguments.command
        if command == nil or command == '' then
          vim.cmd('terminal')
        else
          vim.fn.termopen(command)
        end
        -- 터미널은 입력 모드로 시작한다. 사용자가 누른 첫 글자가 셸에 가야지, nvim 의
        -- 노멀 모드 명령으로 먹히면 안 된다.
        vim.cmd('startinsert')
        return 'started'
        """
        _ = try await channel.request("nvim_exec_lua", [
            .string(script),
            .array([.map([
                MessagePackKeyValuePair(key: .string("command"), value: .string(command)),
            ])]),
        ])
        isRunning = true
    }

    public func send(keys: String) async {
        guard let channel else { return }
        _ = try? await channel.request("nvim_input", [.string(keys)])
    }

    public func resize(columns: Int, rows: Int) async {
        guard let channel, columns > 0, rows > 0 else { return }
        gridSize = (columns, rows)
        _ = try? await channel.request(
            "nvim_ui_try_resize", [.integer(Int64(columns)), .integer(Int64(rows))]
        )
    }

    public func stop() async {
        notificationTask?.cancel()
        notificationTask = nil
        guard let channel else { return }
        self.channel = nil
        isRunning = false
        // 셸을 먼저 끝낸다. nvim 만 죽이면 자식 프로세스가 남아 서버가 계속 포트를 잡는다 —
        // 그러면 다음 실행이 "포트 사용 중" 으로 실패하고, 사용자는 원인을 못 찾는다.
        _ = try? await channel.request("nvim_command", [.string("silent! bdelete!")])
        await channel.terminate()
    }

    /// `flush` 가 올 때만 그린다. 매 이벤트마다 스냅샷을 만들면 반쯤 그려진 화면이 보이고,
    /// 셸 출력처럼 빠른 갱신에서는 그게 깜빡임으로 나타난다.
    private func handle(_ notification: NeovimNotification) {
        guard notification.method == "redraw" else { return }
        var didFlush = false
        for event in notification.parameters {
            guard let parts = event.arrayValue, let name = parts.first?.stringValue else { continue }
            if name == "flush" {
                didFlush = true
                continue
            }
            for argumentTuple in parts.dropFirst() {
                guard let arguments = argumentTuple.arrayValue else { continue }
                gridState.apply(eventName: name, arguments: arguments)
            }
        }
        if didFlush {
            gridBroadcaster.send(gridState.makeSnapshot())
        }
    }
}
