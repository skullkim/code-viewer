import CodeNavigatorContract
import Foundation

/// The embedded Neovim editing session (REQ-004, REQ-005, REQ-010).
///
/// Neovim owns the buffers, the undo history, the dirty state, and every write to disk. This type
/// starts it, attaches a UI, forwards key input, and turns redraw events into renderable frames.
/// It contains no code that writes to project files (INV-3) and never touches the user's
/// configuration (INV-4).
public actor NeovimEditorSession: EditorSession {
    /// Neovim tells us about saves and cursor movement over these notification names.
    private static let savedNotification = "code_navigator_saved"
    private static let statusNotification = "code_navigator_status"
    /// How long a jump target stays highlighted. Long enough for the eye to catch the line,
    /// short enough that it does not linger as if it were a selection.
    private static let jumpHighlightMilliseconds = 700

    private let executableLocator: NeovimExecutableLocator
    private let executableOverridePath: String?

    private var channel: NeovimChannel?
    private var gridState = NeovimGridState()
    private var projectRoot: URL?
    private var gridSize = (columns: 80, rows: 24)
    private var currentInputMode: InputMode = .vim
    private var isUserInterfaceAttached = false

    /// Keys that arrived before the UI attached. Neovim ignores input until then (ADR-0006), so
    /// dropping them would silently lose the user's first keystrokes.
    private var queuedKeys: [String] = []

    /// The last status published, so a mode change can be re-published without another round trip
    /// to Neovim. Mode arrives on the redraw stream while the rest of the status arrives from
    /// autocommands; without this the two never meet and the mode indicator lags or sticks.
    private var lastPublishedStatus: EditorStatus?
    private var lastKnownMode: EditorMode = .normal

    private var stateBroadcaster = EventBroadcaster<EditorSessionState>(initialValue: .notStarted)
    private var gridBroadcaster = EventBroadcaster<EditorGridSnapshot>()
    private var statusBroadcaster = EventBroadcaster<EditorStatus>()
    private var savedFileBroadcaster = EventBroadcaster<SavedFile>()
    private var notificationTask: Task<Void, Never>?

    /// Creates a session. Pass `executableOverridePath` to use a specific Neovim build; by
    /// default the usual install locations are searched.
    public init(executableOverridePath: String? = nil) {
        self.executableLocator = NeovimExecutableLocator()
        self.executableOverridePath = executableOverridePath
    }

    /// Lets tests describe a machine where Neovim is missing, which the public initializer
    /// deliberately cannot express.
    init(executableLocator: NeovimExecutableLocator, executableOverridePath: String? = nil) {
        self.executableLocator = executableLocator
        self.executableOverridePath = executableOverridePath
    }

    // MARK: - Lifecycle

    public func start(projectRoot: URL, columns: Int, rows: Int) async throws {
        self.projectRoot = projectRoot
        gridSize = (max(columns, 1), max(rows, 1))
        updateState(.connecting)

        let executableURL: URL
        do {
            executableURL = try executableLocator.locate(overridePath: executableOverridePath)
        } catch {
            let reason = (error as? NavigatorError)?.errorDescription ?? "\(error)"
            updateState(.startupFailed(makeStartupFailure(reason: reason, foundVersion: nil)))
            throw error
        }

        // Check the version before attaching. A too-old Neovim would otherwise fail later with
        // an obscure RPC error, which is exactly the silent failure REQ-NF-005 forbids.
        let installedVersion = executableLocator.version(of: executableURL)
        if let installedVersion, installedVersion < NeovimVersion.minimumSupported {
            let reason = "Neovim \(installedVersion)이 설치돼 있지만 \(NeovimVersion.minimumSupported) 이상이 필요합니다."
            updateState(.startupFailed(
                makeStartupFailure(reason: reason, foundVersion: installedVersion.description)
            ))
            throw NavigatorError.editorUnavailable(reason: reason)
        }

        let channel = NeovimChannel()
        self.channel = channel
        do {
            // No `--clean`: the user's configuration must load exactly as it would in a terminal.
            try await channel.start(
                executableURL: executableURL,
                arguments: ["--cmd", "cd \(shellQuoted(projectRoot.path))"]
            )
        } catch {
            let reason = (error as? NavigatorError)?.errorDescription ?? "\(error)"
            updateState(.startupFailed(makeStartupFailure(reason: reason, foundVersion: nil)))
            throw error
        }

        await startConsumingNotifications(from: channel)
        await channel.onTermination { [weak self] status in
            Task { await self?.handleProcessExit(status: status) }
        }

        // Everything past this point runs against a process that is already alive. A failure here
        // used to rethrow and leave it running, owned by nobody: invisible to the application,
        // unreachable by `shutDown`, and outliving the app itself. Whatever this call spawned,
        // this call takes back down.
        do {
            try await attachUserInterface(to: channel)
            try await installNotificationHooks(on: channel)
        } catch {
            await channel.terminate()
            self.channel = nil
            isUserInterfaceAttached = false
            let reason = (error as? NavigatorError)?.errorDescription ?? "\(error)"
            updateState(.startupFailed(makeStartupFailure(reason: reason, foundVersion: nil)))
            throw error
        }

        updateState(.connected)
        await flushQueuedKeys()
        await refreshStatus()
    }

    /// Points the editor at a different project (REQ-001 AC-2).
    ///
    /// Open buffers are deliberately left alone. Discarding them would throw away unsaved edits,
    /// and Neovim owns that decision, not us (INV-3). What changes is where the editor resolves
    /// paths from and what its working directory is, so newly opened files come from the new
    /// project and any Vim command that uses the working directory follows.
    func changeProjectRoot(to newRoot: URL) async throws {
        let channel = try requireChannel()
        projectRoot = newRoot
        try await channel.request("nvim_set_current_dir", [.string(newRoot.path)])
        await refreshStatus()
    }

    public func restart() async throws {
        guard let projectRoot else {
            throw NavigatorError.noProjectOpen
        }
        await shutDown()
        try await start(projectRoot: projectRoot, columns: gridSize.columns, rows: gridSize.rows)
    }

    public func shutDown() async {
        notificationTask?.cancel()
        notificationTask = nil
        await channel?.terminate()
        channel = nil
        isUserInterfaceAttached = false
        gridState = NeovimGridState()
        lastPublishedStatus = nil
        lastKnownMode = .normal
        updateState(.notStarted)
    }

    public func state() async -> EditorSessionState {
        stateBroadcaster.latest ?? .notStarted
    }

    // MARK: - Streams

    public func stateUpdates() async -> AsyncStream<EditorSessionState> {
        stateBroadcaster.subscribe { [weak self] identifier in
            Task { await self?.unsubscribeState(identifier) }
        }
    }

    public func gridUpdates() async -> AsyncStream<EditorGridSnapshot> {
        gridBroadcaster.subscribe { [weak self] identifier in
            Task { await self?.unsubscribeGrid(identifier) }
        }
    }

    public func statusUpdates() async -> AsyncStream<EditorStatus> {
        statusBroadcaster.subscribe { [weak self] identifier in
            Task { await self?.unsubscribeStatus(identifier) }
        }
    }

    public func savedFiles() async -> AsyncStream<SavedFile> {
        savedFileBroadcaster.subscribe { [weak self] identifier in
            Task { await self?.unsubscribeSavedPath(identifier) }
        }
    }

    private func unsubscribeState(_ identifier: Int) { stateBroadcaster.unsubscribe(identifier) }
    private func unsubscribeGrid(_ identifier: Int) { gridBroadcaster.unsubscribe(identifier) }
    private func unsubscribeStatus(_ identifier: Int) { statusBroadcaster.unsubscribe(identifier) }
    private func unsubscribeSavedPath(_ identifier: Int) { savedFileBroadcaster.unsubscribe(identifier) }

    // MARK: - Input

    public func resizeGrid(columns: Int, rows: Int) async throws {
        gridSize = (max(columns, 1), max(rows, 1))
        guard let channel, isUserInterfaceAttached else { return }
        try await channel.request("nvim_ui_try_resize", [
            .integer(Int64(gridSize.columns)), .integer(Int64(gridSize.rows)),
        ])
    }

    public func sendKeys(_ keys: String) async throws {
        guard !keys.isEmpty else { return }
        guard let channel, isUserInterfaceAttached else {
            queuedKeys.append(keys)
            return
        }
        try await channel.request("nvim_input", [.string(keys)])
    }

    public func sendMouse(_ event: EditorMouseEvent) async throws {
        guard let channel, isUserInterfaceAttached else { return }
        // Grid 0 tells Neovim to resolve the window itself from the coordinates, which is what we
        // want: the engine tracks one global grid and should not be routing clicks to windows.
        try await channel.request("nvim_input_mouse", [
            .string(event.button.rawValue),
            .string(Self.neovimAction(for: event.action)),
            .string(event.modifiers),
            .integer(0),
            .integer(Int64(event.row)),
            .integer(Int64(event.column)),
        ])
    }

    /// Neovim spells wheel directions as the action, not the button.
    private static func neovimAction(for action: EditorMouseEvent.Action) -> String {
        switch action {
        case .press: return "press"
        case .drag: return "drag"
        case .release: return "release"
        case .wheelUp: return "up"
        case .wheelDown: return "down"
        case .wheelLeft: return "left"
        case .wheelRight: return "right"
        }
    }

    public func setInputMode(_ mode: InputMode) async throws {
        guard mode != currentInputMode else { return }
        let channel = try requireChannel()
        let script = mode == .standard ? NeovimStandardMode.enterScript : NeovimStandardMode.exitScript
        try await channel.request("nvim_exec_lua", [.string(script), .array([])])
        currentInputMode = mode
        await refreshStatus()
    }

    public func inputMode() async -> InputMode {
        currentInputMode
    }

    // MARK: - Navigation

    public func openFile(atRelativePath relativePath: String, line: Int?, recordJump: Bool) async throws {
        let channel = try requireChannel()
        guard let projectRoot else {
            throw NavigatorError.noProjectOpen
        }
        guard !relativePath.split(separator: "/").contains("..") else {
            throw NavigatorError.invalidPath(relativePath)
        }

        // Mark the current spot first so the Vim jump motions come back here (REQ-005 AC-4).
        if recordJump {
            try await channel.request("nvim_command", [.string("normal! m'")])
        }

        let absolutePath = projectRoot.appendingPathComponent(relativePath).path
        try await channel.request("nvim_command", [.string("edit \(shellQuoted(absolutePath))")])

        if let line, line > 0 {
            try await channel.request("nvim_win_set_cursor", [
                .integer(0), .array([.integer(Int64(line)), .integer(0)]),
            ])
            // Put the target line in the middle of the window so its context is visible.
            try await channel.request("nvim_command", [.string("normal! zz")])
            await highlightJumpTarget(line: line, on: channel)
        }
        await refreshStatus()
    }

    public func jumpBack() async throws {
        try await runModeIndependently("execute \"normal! \\<C-o>\"")
    }

    public func jumpForward() async throws {
        // The count is load-bearing: `<C-i>` is a tab, and `:normal!` strips leading whitespace
        // from its argument, so the bare form fails with "E471: Argument required".
        try await runModeIndependently("execute \"normal! 1\\<C-i>\"")
    }

    // MARK: - Editing commands
    //
    // Each of these runs as an ex command or through `:normal!`, both of which execute
    // independently of the mode the user is in. Sending the equivalent keystrokes instead would
    // mean the same command doing different things in Vim and standard mode — `u` reverses a
    // change in normal mode and types the letter "u" in insert mode, and `:w` sent as keys does
    // not write at all from insert mode. A save that silently does not save is the worst of them,
    // because it looks like it worked.

    public func save() async throws {
        try await runModeIndependently("write")
    }

    public func undo() async throws {
        try await runModeIndependently("undo")
    }

    public func redo() async throws {
        try await runModeIndependently("redo")
    }

    public func copySelection() async throws {
        try await runOnSelection(operator: "y")
    }

    public func cutSelection() async throws {
        try await runOnSelection(operator: "d")
    }

    public func paste() async throws {
        try await runModeIndependently("normal! \"+p")
    }

    /// Selects the whole buffer.
    ///
    /// `stopinsert` comes first because `:normal!` returns to the mode it was called from: run
    /// from insert mode it makes the selection and then throws it away, leaving the user in
    /// insert with nothing selected (measured). Leaving normal mode first makes the selection
    /// stick, which is what "select all" has to mean in either input mode.
    public func selectAll() async throws {
        try await runModeIndependently(
            "stopinsert | normal! ggVG",
            resumingTypingInStandardMode: false
        )
    }

    /// Applies a clipboard operator to the selection the user is holding right now.
    ///
    /// Does nothing when nothing is selected. An earlier version restored the previous selection
    /// with `gv` in that case, which is worse than useless: after the user released a selection
    /// and moved elsewhere, a cut would resurrect the old range and delete it — text disappearing
    /// somewhere the cursor is not. Copy and cut act on what is selected, and when that is
    /// nothing they do nothing.
    private func runOnSelection(operator operatorKey: String) async throws {
        guard try await isSelectionActive() else { return }
        try await runModeIndependently("normal! \"+\(operatorKey)")
    }

    /// True while the editor is in a visual or select mode, which is the only time a selection
    /// the user can see actually exists.
    private func isSelectionActive() async throws -> Bool {
        guard let mode = try await currentNeovimMode() else { return false }
        return mode.hasPrefix("v") || mode.hasPrefix("V") || mode.hasPrefix("\u{16}")
            || mode.hasPrefix("s") || mode.hasPrefix("S")
    }

    /// Runs an ex command and refreshes the status, surfacing Neovim's own error message.
    ///
    /// Standard mode promises one thing above all: typing inserts characters (REQ-010 AC-5).
    /// `:normal!` returns to the mode it was called from, and these commands are called from
    /// normal mode, so without this the editor is left in normal mode afterwards — the user cuts
    /// a selection, types `hello`, and the letters are read as commands instead of appearing.
    /// The promise has to be restored by whoever breaks it.
    ///
    /// `selectAll` is the one command that opts out: it exists to leave a selection standing, and
    /// resuming insert would throw that selection away the moment it was made.
    private func runModeIndependently(
        _ command: String,
        resumingTypingInStandardMode: Bool = true
    ) async throws {
        let channel = try requireChannel()
        do {
            try await channel.request("nvim_command", [.string(command)])
            if resumingTypingInStandardMode, currentInputMode == .standard {
                try await channel.request("nvim_command", [.string("startinsert")])
            }
        } catch {
            throw NavigatorError.editorRequestFailed(
                method: command,
                reason: (error as? NeovimChannel.RequestFailure)?.reason ?? "\(error)"
            )
        }
        await refreshStatus()
    }

    public func wordUnderCursor() async throws -> String? {
        let channel = try requireChannel()
        let value = try await channel.request("nvim_eval", [.string("expand('<cword>')")])
        guard let word = value.stringValue, !word.isEmpty else { return nil }
        return word
    }

    /// Briefly highlights the line jumped to, so the eye can find it after the view scrolls.
    ///
    /// Neovim draws it, not the application: the highlight is buffer state, and duplicating it in
    /// the view would mean two things deciding what is emphasised. The extmark clears itself, so
    /// a crash or a second jump cannot leave a stale band on screen.
    private func highlightJumpTarget(line: Int, on channel: NeovimChannel) async {
        let script = """
        local line, clearAfterMilliseconds = ...
        local buffer = vim.api.nvim_get_current_buf()
        local namespace = vim.api.nvim_create_namespace('code_navigator_jump')
        vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
        vim.api.nvim_buf_set_extmark(buffer, namespace, line - 1, 0, {
          line_hl_group = 'Visual',
        })
        vim.defer_fn(function()
          if vim.api.nvim_buf_is_valid(buffer) then
            vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
          end
        end, clearAfterMilliseconds)
        return true
        """
        _ = try? await channel.request("nvim_exec_lua", [
            .string(script),
            .array([.integer(Int64(line)), .integer(Int64(Self.jumpHighlightMilliseconds))]),
        ])
    }

    /// How many jump highlights are currently drawn. Lets a test assert the highlight exists and
    /// then clears, rather than trusting that the Lua ran.
    func jumpHighlightCountForTesting() async throws -> Int {
        let channel = try requireChannel()
        let script = """
        local buffer = vim.api.nvim_get_current_buf()
        local namespace = vim.api.nvim_create_namespace('code_navigator_jump')
        return #vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {})
        """
        let value = try await channel.request("nvim_exec_lua", [.string(script), .array([])])
        return value.integerValue ?? 0
    }

    // MARK: - Start-up steps

    private func attachUserInterface(to channel: NeovimChannel) async throws {
        // `--embed` holds Neovim's start-up until a UI attaches, so this call is what makes the
        // user's configuration run and what makes key input start being processed (ADR-0006).
        try await channel.request("nvim_ui_attach", [
            .integer(Int64(gridSize.columns)),
            .integer(Int64(gridSize.rows)),
            .map([
                MessagePackKeyValuePair(key: .string("ext_linegrid"), value: .boolean(true)),
                MessagePackKeyValuePair(key: .string("rgb"), value: .boolean(true)),
            ]),
        ])
        isUserInterfaceAttached = true
    }

    /// Asks Neovim to tell us when a file is written and when the buffer state changes, instead of
    /// polling. The save signal is what re-indexes an in-app edit without waiting for the file
    /// watcher (REQ-009 AC-5).
    private func installNotificationHooks(on channel: NeovimChannel) async throws {
        let apiInfo = try await channel.request("nvim_get_api_info", [])
        guard let channelIdentifier = apiInfo.arrayValue?.first?.integerValue else {
            throw NavigatorError.editorUnavailable(reason: "채널 식별자를 얻지 못했습니다")
        }

        let script = """
        local channelIdentifier = ...
        local function reportStatus()
          local buffer = vim.api.nvim_get_current_buf()
          local cursor = vim.api.nvim_win_get_cursor(0)
          vim.rpcnotify(channelIdentifier, '\(Self.statusNotification)', {
            path = vim.api.nvim_buf_get_name(buffer),
            modified = vim.api.nvim_get_option_value('modified', { buf = buffer }),
            line = cursor[1],
            column = cursor[2] + 1,
          })
        end
        vim.api.nvim_create_autocmd({'BufWritePost'}, {
          callback = function(arguments)
            local savedPath = vim.api.nvim_buf_get_name(arguments.buf)
            vim.rpcnotify(channelIdentifier, '\(Self.savedNotification)', {
              path = savedPath,
              lineCount = vim.api.nvim_buf_line_count(arguments.buf),
              byteSize = math.max(vim.fn.getfsize(savedPath), 0),
            })
            reportStatus()
          end
        })
        vim.api.nvim_create_autocmd(
          {'BufEnter', 'TextChanged', 'TextChangedI', 'CursorMoved', 'CursorMovedI', 'ModeChanged'},
          { callback = reportStatus }
        )
        """
        try await channel.request("nvim_exec_lua", [
            .string(script), .array([.integer(Int64(channelIdentifier))]),
        ])
    }

    private func flushQueuedKeys() async {
        let keys = queuedKeys
        queuedKeys.removeAll()
        for chunk in keys {
            try? await sendKeys(chunk)
        }
    }

    // MARK: - Notification handling

    private func startConsumingNotifications(from channel: NeovimChannel) async {
        let notifications = await channel.notifications()
        notificationTask = Task { [weak self] in
            for await notification in notifications {
                await self?.handle(notification)
            }
        }
    }

    private func handle(_ notification: NeovimNotification) {
        switch notification.method {
        case "redraw":
            handleRedraw(notification.parameters)
        case Self.savedNotification:
            if let saved = Self.makeSavedFile(from: notification.parameters) {
                savedFileBroadcaster.send(saved)
            }
        case Self.statusNotification:
            if let fields = notification.parameters.first?.mapValue {
                let status = makeStatus(fromFields: fields)
                lastPublishedStatus = status
                statusBroadcaster.send(status)
            }
        default:
            break
        }
    }

    /// A redraw notification carries a batch of events. `flush` marks the end of a frame, which is
    /// the only point the screen is consistent and therefore the only point worth publishing.
    private func handleRedraw(_ events: [MessagePackValue]) {
        var didFlush = false
        for event in events {
            guard let parts = event.arrayValue, let name = parts.first?.stringValue else { continue }
            if name == "flush" {
                didFlush = true
                continue
            }
            // Each event carries one or more argument tuples for the same event name.
            for argumentTuple in parts.dropFirst() {
                guard let arguments = argumentTuple.arrayValue else { continue }
                gridState.apply(eventName: name, arguments: arguments)
            }
        }
        if didFlush {
            let snapshot = gridState.makeSnapshot()
            gridBroadcaster.send(snapshot)

            // Mode lives on the redraw stream, everything else on the autocommand stream. A mode
            // change with no accompanying buffer event would otherwise never reach the interface,
            // which is how a visual selection can leave the indicator saying "normal".
            if snapshot.mode != lastKnownMode {
                lastKnownMode = snapshot.mode
                publishStatusWithCurrentMode()
            }
        }
    }

    /// Re-publishes the last status with the current mode, for mode changes that carry no other
    /// state. Cheap on purpose: mode changes on every keystroke in insert mode.
    private func publishStatusWithCurrentMode() {
        guard let previous = lastPublishedStatus else { return }
        let updated = EditorStatus(
            filePath: previous.filePath,
            isDirty: previous.isDirty,
            cursorLine: previous.cursorLine,
            cursorColumn: previous.cursorColumn,
            mode: lastKnownMode,
            inputMode: currentInputMode
        )
        lastPublishedStatus = updated
        statusBroadcaster.send(updated)
    }

    /// Reads the save notification, whose payload Neovim fills in at write time.
    private static func makeSavedFile(from parameters: [MessagePackValue]) -> SavedFile? {
        guard let fields = parameters.first?.mapValue else { return nil }
        var path = ""
        var lineCount = 0
        var byteSize = 0

        for field in fields {
            switch field.key.stringValue {
            case "path": path = field.value.stringValue ?? ""
            case "lineCount": lineCount = field.value.integerValue ?? 0
            case "byteSize": byteSize = field.value.integerValue ?? 0
            default: break
            }
        }
        guard !path.isEmpty else { return nil }
        return SavedFile(path: path, lineCount: lineCount, byteSize: byteSize)
    }

    private func makeStatus(fromFields fields: [MessagePackKeyValuePair]) -> EditorStatus {
        var path: String?
        var isDirty = false
        var line = 1
        var column = 1

        for field in fields {
            switch field.key.stringValue {
            case "path":
                let value = field.value.stringValue ?? ""
                path = value.isEmpty ? nil : value
            case "modified":
                isDirty = field.value.booleanValue ?? false
            case "line":
                line = field.value.integerValue ?? 1
            case "column":
                column = field.value.integerValue ?? 1
            default:
                break
            }
        }

        return EditorStatus(
            filePath: path,
            isDirty: isDirty,
            cursorLine: line,
            cursorColumn: column,
            mode: lastKnownMode,
            inputMode: currentInputMode
        )
    }

    /// Pulls the current buffer state once, for the moments no autocommand fires — right after
    /// start-up, and immediately after a navigation the interface needs reflected at once.
    private func refreshStatus() async {
        guard let channel, isUserInterfaceAttached else { return }
        let script = """
        local buffer = vim.api.nvim_get_current_buf()
        local cursor = vim.api.nvim_win_get_cursor(0)
        return {
          path = vim.api.nvim_buf_get_name(buffer),
          modified = vim.api.nvim_get_option_value('modified', { buf = buffer }),
          line = cursor[1],
          column = cursor[2] + 1,
        }
        """
        guard let value = try? await channel.request("nvim_exec_lua", [.string(script), .array([])]),
              let fields = value.mapValue
        else {
            return
        }
        let status = makeStatus(fromFields: fields)
        lastPublishedStatus = status
        statusBroadcaster.send(status)
    }

    private func handleProcessExit(status: Int32) {
        isUserInterfaceAttached = false
        updateState(.disconnected(reason: "편집 세션이 종료됐습니다 (상태 \(status)). 재기동할 수 있습니다."))
    }

    /// The current buffer's line under the cursor, so a test can assert that input actually
    /// reached the buffer rather than merely that a notification arrived. Not part of the contract.
    func currentLineForTesting() async throws -> String? {
        guard let channel else { return nil }
        return try await channel.request("nvim_get_current_line", []).stringValue
    }


    /// Buffer and register access for tests that must check the editor's real state rather than
    /// what the engine reports about it. Not part of the contract.
    func bufferLinesForTesting() async throws -> [String] {
        let channel = try requireChannel()
        let value = try await channel.request("nvim_buf_get_lines", [
            .integer(0), .integer(0), .integer(-1), .boolean(false),
        ])
        return value.arrayValue?.compactMap(\.stringValue) ?? []
    }

    func replaceBufferForTesting(with lines: [String]) async throws {
        let channel = try requireChannel()
        try await channel.request("nvim_buf_set_lines", [
            .integer(0), .integer(0), .integer(-1), .boolean(false),
            .array(lines.map { .string($0) }),
        ])
    }

    func isDirtyForTesting() async throws -> Bool {
        let channel = try requireChannel()
        let value = try await channel.request("nvim_get_option_value", [
            .string("modified"), .map([]),
        ])
        return value.booleanValue ?? false
    }

    func cursorLineForTesting() async throws -> Int {
        let channel = try requireChannel()
        let value = try await channel.request("nvim_win_get_cursor", [.integer(0)])
        return value.arrayValue?.first?.integerValue ?? -1
    }

    func clipboardRegisterForTesting() async throws -> String {
        let channel = try requireChannel()
        return (try await channel.request("nvim_eval", [.string("getreg('+')")])).stringValue ?? ""
    }

    func setClipboardRegisterForTesting(_ text: String) async throws {
        let channel = try requireChannel()
        try await channel.request("nvim_call_function", [
            .string("setreg"), .array([.string("+"), .string(text)]),
        ])
    }

    func clearClipboardRegisterForTesting() async throws {
        try await setClipboardRegisterForTesting("")
    }

    /// How many lines the current visual selection spans.
    func selectedLineCountForTesting() async throws -> Int {
        let channel = try requireChannel()
        let value = try await channel.request(
            "nvim_eval", [.string("abs(line('v') - line('.')) + 1")]
        )
        return value.integerValue ?? 0
    }

    /// Neovim's own short mode code — `n`, `i`, `v`, `V`, `s`, `niI` and so on.
    ///
    /// Deliberately not the contract's `EditorMode`: that one is the *display* mode, coarse on
    /// purpose and derived from redraw events, while this is what Neovim reports about itself
    /// right now. Selection commands need the precise answer, and a test diagnosing a mode
    /// problem needs to compare the two.
    ///
    /// Named without a `ForTesting` suffix because production depends on it: `isSelectionActive`
    /// calls it on every copy and cut. A suffix promising "tests only" would invite the next
    /// person to delete it, and cut would silently stop working.
    func currentNeovimMode() async throws -> String? {
        let channel = try requireChannel()
        let value = try await channel.request("nvim_get_mode", [])
        guard let fields = value.mapValue else { return nil }
        for field in fields where field.key.stringValue == "mode" {
            return field.value.stringValue
        }
        return nil
    }

    /// Internal mode bookkeeping, so a test can see where mode propagation stopped rather than
    /// inferring it from the published status. Not part of the contract.
    func modeBookkeepingForTesting() async -> (lastKnown: EditorMode, published: EditorMode?) {
        (lastKnownMode, lastPublishedStatus?.mode)
    }

    /// The embedded process id, so a test can simulate a crash. Not part of the contract.
    func processIdentifierForTesting() async -> Int32? {
        guard let channel else { return nil }
        return await channel.processIdentifier
    }

    // MARK: - Helpers

    private func makeStartupFailure(reason: String, foundVersion: String?) -> EditorStartupFailure {
        EditorStartupFailure(
            reason: reason,
            searchedPaths: executableOverridePath.map { [$0] } ?? executableLocator.candidatePaths(),
            requiredVersion: NeovimVersion.minimumSupported.description,
            foundVersion: foundVersion
        )
    }

    private func updateState(_ newState: EditorSessionState) {
        stateBroadcaster.send(newState)
    }

    private func requireChannel() throws -> NeovimChannel {
        guard let channel else {
            throw NavigatorError.editorNotRunning
        }
        return channel
    }

    /// Escapes a path for a Neovim ex command, where spaces separate arguments.
    private func shellQuoted(_ path: String) -> String {
        path.replacingOccurrences(of: " ", with: "\\ ")
    }
}
