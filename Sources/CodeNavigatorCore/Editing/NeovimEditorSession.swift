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
    private static let dirtyNotification = "code_navigator_dirty"
    /// `gd` / `gr`, pressed inside the editor (REQ-015).
    private static let navigationNotification = "code_navigator_navigate"
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

    /// Neovim's tabpage handle and project root for each open project.
    ///
    /// The handles stay here rather than in the contract: they are msgpack values that mean
    /// nothing outside this process, so handing one to the application would give it a token it
    /// can neither read nor check. It already has a tab identity, so that is the key.
    ///
    /// The root is kept alongside because relative paths mean different files in different tabs,
    /// and `projectRoot` below follows whichever tab is active.
    private struct ProjectTabPage {
        let handle: MessagePackValue
        let root: URL
    }

    private var projectTabPages: [ProjectTabIdentifier: ProjectTabPage] = [:]

    /// The last status published, so a mode change can be re-published without another round trip
    /// to Neovim. Mode arrives on the redraw stream while the rest of the status arrives from
    /// autocommands; without this the two never meet and the mode indicator lags or sticks.
    /// 마지막으로 nvim 에 심은 디버그 색. 같은 값을 다시 심지 않기 위한 것이다.
    private var installedDebugPalette: EditorDebugPalette?
    private var installedGitPalette: GitMarkerPalette?

    private var lastPublishedStatus: EditorStatus?
    private var lastKnownMode: EditorMode = .normal
    private var startupTimeoutOverride: Duration?

    /// A full environment for the editor process, for tests that need to describe a machine with
    /// a particular user configuration.
    ///
    /// Set through the process environment instead, and the fixture leaks: this suite starts many
    /// editors and they run at the same time, so an `XDG_CONFIG_HOME` meant for one test is read
    /// by every editor another suite happens to start while it runs.
    private var environmentOverrideForTesting: [String: String]?
    private var effectiveStartupTimeout: Duration { startupTimeoutOverride ?? NeovimChannel.startupTimeout }

    private var stateBroadcaster = EventBroadcaster<EditorSessionState>(initialValue: .notStarted)
    private var gridBroadcaster = EventBroadcaster<EditorGridSnapshot>()
    private var statusBroadcaster = EventBroadcaster<EditorStatus>()
    private var savedFileBroadcaster = EventBroadcaster<SavedFile>()
    private var dirtyChangeBroadcaster = EventBroadcaster<String>()

    /// `gd` / `gr` presses. **Events, not state** — a late subscriber must not be handed the
    /// last keypress and jump somewhere the user did not ask for just now (§3.4).
    private var navigationRequestBroadcaster =
        EventBroadcaster<EditorNavigationRequest>(replayPolicy: .eventsOnly)

    /// What this session decided about each navigation key, in the order it decided (REQ-015 AC-6).
    private var keyMappingOutcomes: [EditorKeyMappingOutcome] = []

    /// The palette last applied, so a restart can restore it without the application asking again.
    private var appliedSyntaxPalette: EditorSyntaxPalette?
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

    /// Starts with the user's configuration coming from a fixture directory.
    ///
    /// The whole current environment is carried over and only `XDG_CONFIG_HOME` replaced, so the
    /// editor still finds its executable, its state directory, and everything else the suite has
    /// already arranged.
    func startWithUserConfigurationForTesting(
        configurationHome: URL, projectRoot: URL, columns: Int, rows: Int
    ) async throws {
        var environment = ProcessInfo.processInfo.environment
        environment["XDG_CONFIG_HOME"] = configurationHome.path
        environmentOverrideForTesting = environment
        defer { environmentOverrideForTesting = nil }
        try await start(projectRoot: projectRoot, columns: columns, rows: rows)
    }

    /// Lets a test use a short start-up budget instead of waiting out the real one.
    func startForTesting(
        projectRoot: URL, columns: Int, rows: Int, startupTimeout: Duration
    ) async throws {
        startupTimeoutOverride = startupTimeout
        defer { startupTimeoutOverride = nil }
        try await start(projectRoot: projectRoot, columns: columns, rows: rows)
    }

    public func start(projectRoot: URL, columns: Int, rows: Int) async throws {
        // Start-up timings are carried into the failure message. A timeout here has resisted
        // reproduction — CPU load, configuration weight, grid size, file loading and redraw
        // volume were each measured and ruled out — so the next occurrence in the field has to
        // be the thing that teaches us. An error that says only "no response" teaches nothing.
        let startedAt = Date()
        var stageTimings: [String] = []
        func recordStage(_ name: String) {
            stageTimings.append(String(format: "%@ %.2fs", name, Date().timeIntervalSince(startedAt)))
        }

        self.projectRoot = projectRoot
        gridSize = (max(columns, 1), max(rows, 1))
        updateState(.connecting)

        let executableURL: URL
        do {
            executableURL = try executableLocator.locate(overridePath: executableOverridePath)
        } catch {
            let reason = (error as? NavigatorError)?.errorDescription ?? "\(error)"
            updateState(.startupFailed(
                makeStartupFailure(kind: .notInstalled, reason: reason, foundVersion: nil)
            ))
            throw error
        }

        recordStage("탐색")

        // Check the version before attaching. A too-old Neovim would otherwise fail later with
        // an obscure RPC error, which is exactly the silent failure REQ-NF-005 forbids.
        let installedVersion = executableLocator.version(of: executableURL)
        if let installedVersion, installedVersion < NeovimVersion.minimumSupported {
            // 동적 값 뒤에 굴절하는 조사를 두지 않는다. 버전은 숫자로 끝나고 숫자의 받침은
            // 읽어야 정해진다 — 0.9.5 는 "오"라 `가`, 0.10.0 은 "영"이라 `이`다. 조사 유틸도
            // 이건 못 맞춘다(값의 도메인이 한글이 아니다). `입니다`는 받침에 안 갈린다.
            let reason = "설치된 Neovim 버전은 \(installedVersion)입니다. \(NeovimVersion.minimumSupported) 이상이 필요합니다."
            updateState(.startupFailed(
                makeStartupFailure(
                    kind: .versionTooOld, reason: reason, foundVersion: installedVersion.description
                )
            ))
            throw NavigatorError.editorUnavailable(reason: reason)
        }

        let channel = NeovimChannel()
        self.channel = channel
        do {
            // No `--clean`: the user's configuration must load exactly as it would in a terminal.
            try await channel.start(
                executableURL: executableURL,
                arguments: ["--cmd", "cd \(shellQuoted(projectRoot.path))"],
                environment: environmentOverrideForTesting,
                workingDirectory: projectRoot
            )
        } catch {
            let reason = (error as? NavigatorError)?.errorDescription ?? "\(error)"
            updateState(.startupFailed(
                makeStartupFailure(kind: .launchFailed, reason: reason, foundVersion: nil)
            ))
            throw error
        }

        recordStage("기동")
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
            recordStage("부착")
            try await installNotificationHooks(on: channel)
            recordStage("핸드셰이크")

            // Everything below runs **after** the user's configuration has loaded, which
            // `nvim_ui_attach` above is what triggers (ADR-0006). Running any of it earlier would
            // read an editor that has not yet been configured: the user's `gd` would look absent
            // and get overwritten (REQ-015 AC-6), and their `set mouse=` would land on top of
            // ours (REQ-017).
            await installSessionInteractionOptions(on: channel)
            await installNavigationKeyMappings(on: channel)
            await installHighlightBehaviour(on: channel)
            recordStage("상호작용")
        } catch {
            await channel.terminate()
            self.channel = nil
            isUserInterfaceAttached = false
            // The process is alive but never finished the handshake. Saying "not installed" here
            // sends the user to reinstall an editor that is running in front of them.
            let reason = (error as? NavigatorError)?.errorDescription ?? "\(error)"
            let progress = stageTimings.isEmpty ? "없음" : stageTimings.joined(separator: " · ")
            updateState(.startupFailed(
                makeStartupFailure(
                    kind: .unresponsive,
                    reason: "Neovim이 제한 시간 안에 응답하지 않았습니다: \(reason) [단계별 경과: \(progress)]",
                    foundVersion: installedVersion?.description
                )
            ))
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

    /// Starts on `projectRoot` reusing the grid size the interface already agreed.
    ///
    /// A retry has no new size to offer — the window has not changed — and inventing a default
    /// here would resize the user's editor as a side effect of reconnecting.
    public func startReusingAgreedGridSize(projectRoot: URL) async throws {
        if channel != nil {
            await shutDown()
        }
        try await start(projectRoot: projectRoot, columns: gridSize.columns, rows: gridSize.rows)
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

    // MARK: - Project tabs (REQ-012)

    /// Opens a tabpage for a project and points it at that project's root.
    ///
    /// The first project reuses the tabpage Neovim already started with. Creating one for it would
    /// leave an empty tabpage behind forever, and the user would see a tab in the editor that
    /// belongs to no project.
    func openProjectTab(_ identifier: ProjectTabIdentifier, root: URL) async throws {
        let channel = try requireChannel()
        if projectTabPages.isEmpty == false {
            try await channel.request("nvim_command", [.string("tabnew")])
        }
        // `tcd`, not `cd`: tab-local is the whole point. A global `cd` would move every project's
        // working directory at once, which is measurably the one thing tabpages do isolate
        // (ADR-0009).
        try await channel.request("nvim_command", [.string("tcd \(shellQuoted(root.path))")])
        let handle = try await channel.request("nvim_get_current_tabpage", [])
        projectTabPages[identifier] = ProjectTabPage(handle: handle, root: root)

        // Relative paths are resolved against the tab the user is in. Leaving this at the first
        // project's root meant `src/App.kt` in the second tab opened the **first** project's file
        // — no error, just the wrong file, and then saving it reindexed the wrong project.
        projectRoot = root
    }

    func activateProjectTab(_ identifier: ProjectTabIdentifier) async throws {
        let channel = try requireChannel()
        guard let page = projectTabPages[identifier] else {
            throw NavigatorError.noProjectOpen
        }
        try await channel.request("nvim_set_current_tabpage", [page.handle])
        projectRoot = page.root
    }

    /// Closes a project's tabpage.
    ///
    /// The last one is a special case: `tabclose` refuses on the final tabpage with `E784`, and
    /// restarting the process instead would charge the user the start-up cost for closing a
    /// project. So the session stays and the tabpage is emptied rather than removed.
    func closeProjectTab(_ identifier: ProjectTabIdentifier) async throws {
        let channel = try requireChannel()
        guard let page = projectTabPages[identifier] else {
            return
        }
        try await channel.request("nvim_set_current_tabpage", [page.handle])
        if projectTabPages.count == 1 {
            try await channel.request("nvim_command", [.string("enew!")])
        } else {
            try await channel.request("nvim_command", [.string("tabclose")])
        }
        projectTabPages[identifier] = nil
        // 남은 탭이 있으면 그쪽 루트를 따른다 — 닫힌 프로젝트의 루트로 상대 경로를 풀면 안 된다.
        projectRoot = projectTabPages.values.first?.root ?? projectRoot
    }

    // MARK: - Navigation

    public func openFile(atRelativePath relativePath: String, line: Int?, recordJump: Bool) async throws {
        let channel = try requireChannel()
        guard let projectRoot else {
            throw NavigatorError.noProjectOpen
        }
        guard !relativePath.split(separator: "/").contains("..") else {
            throw NavigatorError.pathOutsideProject(relativePath)
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

    // MARK: - 저장과 더티 상태

    /// Fires whenever a buffer's modified flag changes, carrying that buffer's absolute path.
    ///
    /// Deliberately **not** a count. Counting per project would require the session to know which
    /// projects are open, and that belongs to the workspace — a session that had to be told would
    /// make the tab list owned in two places. The workspace recounts the affected tab when this
    /// fires; the path is included so it can recount one tab instead of all of them.
    ///
    /// Both directions are reported. A tab's dot has to be turned off as well as on, and only the
    /// buffer knows when a write cleared it.
    public func dirtyStateChanges() async -> AsyncStream<String> {
        dirtyChangeBroadcaster.subscribe { [weak self] identifier in
            Task { await self?.unsubscribeDirtyChange(identifier) }
        }
    }

    private func unsubscribeDirtyChange(_ identifier: Int) {
        dirtyChangeBroadcaster.unsubscribe(identifier)
    }

    /// The unsaved files of one project, as project-relative paths.
    ///
    /// Scope is decided by **where the file is**, not by which window or tabpage shows it: in the
    /// one-process model a buffer is global, and a project's buffer may be hidden or live in
    /// another tabpage. Path containment catches those; window enumeration does not.
    ///
    /// A dirty buffer that belongs to **no** project root (the user ran `:e ~/notes.md`) is not
    /// listed. Closing this tab is not a reason to write a file the tab never owned.
    public func dirtyFiles(inProjectRoot root: URL) async throws -> [String] {
        try await dirtyBuffers(inProjectRoot: root).map(\.relativePath).sorted()
    }

    /// Writes every unsaved file of this project, and reports each one.
    ///
    /// `:wa` is not used: measured, it ignores tabpage boundaries and would write **another
    /// project's** unsaved work when the user asked to close this one — worse than the loss the
    /// confirmation sheet exists to prevent. Buffers are written individually instead, which is
    /// also what makes per-file reporting possible.
    ///
    /// One refusal does not stop the rest. Stopping at the first failure would leave files
    /// unsaved that could have been written.
    public func saveAll(inProjectRoot root: URL) async throws -> SaveAllOutcome {
        let channel = try requireChannel()
        let buffers = try await dirtyBuffers(inProjectRoot: root)
        guard !buffers.isEmpty else {
            return SaveAllOutcome(savedPaths: [], failures: [])
        }

        let script = """
        local handles = ...
        local saved, failed = {}, {}
        for _, handle in ipairs(handles) do
          local ok, message = pcall(function()
            vim.api.nvim_buf_call(handle, function() vim.cmd('write') end)
          end)
          if ok then
            table.insert(saved, handle)
          else
            table.insert(failed, { buffer = handle, reason = tostring(message) })
          end
        end
        return { saved = saved, failed = failed }
        """
        let response = try await channel.request("nvim_exec_lua", [
            .string(script),
            .array([.array(buffers.map { .integer(Int64($0.handle)) })]),
        ])

        let relativePathsByHandle = Dictionary(
            uniqueKeysWithValues: buffers.map { ($0.handle, $0.relativePath) }
        )
        var savedPaths: [String] = []
        var failures: [SaveFailure] = []

        for field in response.mapValue ?? [] {
            switch field.key.stringValue {
            case "saved":
                savedPaths = (field.value.arrayValue ?? []).compactMap {
                    $0.integerValue.flatMap { relativePathsByHandle[$0] }
                }
            case "failed":
                failures = (field.value.arrayValue ?? []).compactMap { entry in
                    var handle: Int?
                    var reason = ""
                    for pair in entry.mapValue ?? [] {
                        switch pair.key.stringValue {
                        case "buffer": handle = pair.value.integerValue
                        case "reason": reason = pair.value.stringValue ?? ""
                        default: break
                        }
                    }
                    guard let handle, let path = relativePathsByHandle[handle] else { return nil }
                    return SaveFailure(path: path, reason: reason)
                }
            default:
                break
            }
        }

        return SaveAllOutcome(savedPaths: savedPaths.sorted(), failures: failures)
    }

    private struct DirtyBuffer {
        let handle: Int
        let relativePath: String
    }

    private func dirtyBuffers(inProjectRoot root: URL) async throws -> [DirtyBuffer] {
        let channel = try requireChannel()
        let script = """
        local result = {}
        for _, handle in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(handle) and vim.bo[handle].modified then
            local name = vim.api.nvim_buf_get_name(handle)
            if name ~= '' then
              table.insert(result, { buffer = handle, path = name })
            end
          end
        end
        return result
        """
        let response = try await channel.request("nvim_exec_lua", [.string(script), .array([])])

        return (response.arrayValue ?? []).compactMap { entry in
            var handle: Int?
            var absolutePath: String?
            for pair in entry.mapValue ?? [] {
                switch pair.key.stringValue {
                case "buffer": handle = pair.value.integerValue
                case "path": absolutePath = pair.value.stringValue
                default: break
                }
            }
            guard
                let handle,
                let absolutePath,
                let relativePath = Self.projectRelativePath(of: absolutePath, inProjectRoot: root)
            else {
                return nil
            }
            return DirtyBuffer(handle: handle, relativePath: relativePath)
        }
    }

    /// The path relative to the root, or nil when the file is not inside it.
    ///
    /// Both sides go through `realpath` first, because Neovim reports the name a buffer was
    /// opened with and that can differ from the canonical path by a symlink. The root gets a
    /// trailing separator before the prefix test so a sibling whose name merely starts the same
    /// way (`/repo-backup` next to `/repo`) is not mistaken for a child — writing files from
    /// another tree is exactly the failure this scope check exists to prevent.
    private static func projectRelativePath(of absolutePath: String, inProjectRoot root: URL) -> String? {
        guard
            let file = canonicalPath(of: absolutePath),
            let rootPath = canonicalPath(of: root.path)
        else {
            return nil
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard file.hasPrefix(prefix) else {
            return nil
        }
        return String(file.dropFirst(prefix.count))
    }

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

    /// 디버거의 거터 표시를 다시 놓는다 (REQ-016).
    ///
    /// 설치와 갱신을 나눈다. 사인 정의와 색은 한 번만 있으면 되고, 놓는 일은 브레이크포인트가
    /// 바뀔 때마다 일어난다 — 매번 다시 정의하면 nvim 이 매번 다시 그린다.
    public func showGitMarkers(
        _ markers: EditorGitMarkers, palette: GitMarkerPalette
    ) async throws {
        guard let channel else { throw NavigatorError.editorNotRunning }

        // 설치는 팔레트가 바뀔 때만. 매번 다시 심으면 저장할 때마다 하이라이트가 다시
        // 정의되고, 그 비용이 저장 지연으로 보인다.
        if installedGitPalette != palette {
            _ = try? await channel.request("nvim_exec_lua", [
                .string(NeovimGitMarkerScript.installScript(palette: palette)), .array([]),
            ])
            installedGitPalette = palette
        }

        _ = try? await channel.request("nvim_exec_lua", [
            .string(NeovimGitMarkerScript.refreshScript()),
            .array([.map([
                MessagePackKeyValuePair(key: .string("path"), value: .string(markers.absolutePath)),
                MessagePackKeyValuePair(
                    key: .string("added"), value: .array(markers.added.map { .integer(Int64($0)) })
                ),
                MessagePackKeyValuePair(
                    key: .string("modified"), value: .array(markers.modified.map { .integer(Int64($0)) })
                ),
                MessagePackKeyValuePair(
                    key: .string("deleted"), value: .array(markers.deleted.map { .integer(Int64($0)) })
                ),
            ])]),
        ])
    }

    public func showDebugMarkers(
        _ markers: EditorDebugMarkers, palette: EditorDebugPalette
    ) async throws {
        guard let channel else { throw NavigatorError.editorNotRunning }

        if installedDebugPalette != palette {
            _ = try? await channel.request("nvim_exec_lua", [
                .string(NeovimDebugMarkerScript.installScript(palette: palette)), .array([]),
            ])
            installedDebugPalette = palette
        }

        // nvim 은 버퍼를 절대 경로로 안다. 상대 경로로 물으면 `bufnr` 이 -1 을 주고,
        // 그러면 표시가 조용히 안 놓인다.
        let absolutePath = projectRoot.map { root in
            markers.path.hasPrefix("/") ? markers.path : root.appendingPathComponent(markers.path).path
        } ?? markers.path

        _ = try? await channel.request("nvim_exec_lua", [
            .string(NeovimDebugMarkerScript.refreshScript()),
            .array([.map([
                MessagePackKeyValuePair(key: .string("path"), value: .string(absolutePath)),
                MessagePackKeyValuePair(
                    key: .string("breakpointLines"),
                    value: .array(markers.breakpointLines.map { .integer(Int64($0)) })
                ),
                MessagePackKeyValuePair(
                    key: .string("stoppedLine"),
                    // 케이스 이름이 `nilValue` 다. `.nil` 은 Swift 예약어라 못 쓴다.
                    value: markers.stoppedLine.map { MessagePackValue.integer(Int64($0)) } ?? .nilValue
                ),
            ])]),
        ])
    }

    /// 그 자리가 거터인지, 거터라면 어느 줄인지 (REQ-016).
    ///
    /// 화면 행 → 버퍼 줄은 `screenpos` 로 역추적한다. 산수(`line('w0') + row`)로 하면
    /// 줄바꿈과 접힘에서 어긋나고, 어긋난 것은 예외가 아니라 **다른 줄에 걸리는 것**으로만
    /// 드러난다. 텍스트 시작 열도 `screenpos` 가 알려 주므로 거터 폭을 우리가 셀 필요가 없다.
    public func gutterLine(atRow row: Int, column: Int) async throws -> Int? {
        guard let channel else { return nil }
        let script = """
        local arguments = ...
        local screenRow = arguments.row + 1      -- Lua 는 1-based
        local screenColumn = arguments.column + 1

        local last = vim.fn.line('$')
        local line = vim.fn.line('w0')
        while line <= last do
          local position = vim.fn.screenpos(0, line, 1)
          if position.row == 0 then
            -- 접혀 있거나 화면 밖이다. 다음 줄로.
          elseif position.row == screenRow then
            -- 텍스트가 시작하는 열보다 왼쪽이면 거터다.
            if screenColumn < position.col then
              return line
            end
            return nil
          elseif position.row > screenRow then
            return nil
          end
          line = line + 1
        end
        return nil
        """
        let value = try? await channel.request("nvim_exec_lua", [
            .string(script),
            .array([.map([
                MessagePackKeyValuePair(key: .string("row"), value: .integer(Int64(row))),
                MessagePackKeyValuePair(key: .string("column"), value: .integer(Int64(column))),
            ])]),
        ])
        guard let line = value?.integerValue else { return nil }
        return Int(line)
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
        try await channel.request(
            "nvim_ui_attach",
            [
                .integer(Int64(gridSize.columns)),
                .integer(Int64(gridSize.rows)),
                .map([
                    MessagePackKeyValuePair(key: .string("ext_linegrid"), value: .boolean(true)),
                    MessagePackKeyValuePair(key: .string("rgb"), value: .boolean(true)),
                ]),
            ],
            timeout: effectiveStartupTimeout
        )
        isUserInterfaceAttached = true
    }

    /// Asks Neovim to tell us when a file is written and when the buffer state changes, instead of
    /// polling. The save signal is what re-indexes an in-app edit without waiting for the file
    /// watcher (REQ-009 AC-5).
    private func installNotificationHooks(on channel: NeovimChannel) async throws {
        // The application draws the tab bar. Left on, Neovim draws a second one and every grid row
        // shifts by one — and only once a second tabpage exists, so a single-tab check never sees
        // it. This is a rendering contract, not a change to the user's editing preferences (INV-4).
        _ = try? await channel.request("nvim_command", [.string("set showtabline=0")])

        let apiInfo = try await channel.request(
            "nvim_get_api_info", [], timeout: effectiveStartupTimeout
        )
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
        vim.api.nvim_create_autocmd({'BufModifiedSet'}, {
          callback = function(arguments)
            local path = vim.api.nvim_buf_get_name(arguments.buf)
            if path ~= '' then
              vim.rpcnotify(channelIdentifier, '\(Self.dirtyNotification)', { path = path })
            end
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

    // MARK: - Session interaction (REQ-015, REQ-016, REQ-017)

    /// Options this application needs regardless of how the user configured their terminal editor.
    ///
    /// `mouse=a` is here because REQ-017 is not a conditional requirement. Measured, the default
    /// is `nvi` and clicking and dragging both work — but with `mouse=` set, **clicking still
    /// moves the cursor while dragging silently stops selecting**. Half-working is the worst
    /// shape for this to fail in, and a user who turned the mouse off in their terminal was
    /// making a decision about a terminal, not about a window they drag-select in.
    ///
    /// Like `showtabline=0`, this is a rendering-and-interaction contract for the embedded
    /// session, not an edit to the user's configuration (INV-7).
    ///
    /// `number` is here because the gutter is part of the designed screen (prototype `styles.css`
    /// draws a 46px column), not a Neovim preference. It shipped off, and nobody noticed until a
    /// person looked at the running application — the tests were green because none of them asked
    /// whether the gutter was on screen.
    private func installSessionInteractionOptions(on channel: NeovimChannel) async {
        _ = try? await channel.request("nvim_command", [.string("set mouse=a")])
        _ = try? await channel.request("nvim_command", [.string("set number")])
        // `CursorLineNr` only applies while `cursorline` is on — without it every number is
        // `LineNr` and the current line does not stand out. `cursorlineopt=number` takes the
        // emphasised number **without** the full-width background band: the prototype marks the
        // current line by its number alone, and §4.1.1 leaves `CursorLine` to the user.
        _ = try? await channel.request("nvim_command", [.string("set cursorline")])
        _ = try? await channel.request("nvim_command", [.string("set cursorlineopt=number")])
    }

    /// Installs `gd` and `gr` — except where the user's own configuration already holds them.
    ///
    /// Order matters and is not obvious: the ownership question is asked **now**, after the
    /// user's configuration has run. Asked before, every key looks free.
    private func installNavigationKeyMappings(on channel: NeovimChannel) async {
        keyMappingOutcomes = []

        guard let channelIdentifier = await requestChannelIdentifier(from: channel) else { return }
        let editorRuntimePath = await runLua(NeovimNavigationKeyScript.runtimePathScript, on: channel) ?? ""

        for (keys, request) in Self.navigationKeyAssignments {
            guard let owner = await keyMappingOwner(
                forKeys: keys, editorRuntimePath: editorRuntimePath, on: channel
            ) else {
                continue
            }

            guard NeovimKeyMappingClassifier.shouldInstall(for: owner) else {
                keyMappingOutcomes.append(
                    EditorKeyMappingOutcome(
                        keys: keys,
                        request: request,
                        resolution: NeovimKeyMappingClassifier.resolution(for: owner),
                        userScriptPath: NeovimKeyMappingClassifier.userScriptPath(for: owner)
                    )
                )
                continue
            }

            // `gr` is a prefix of Neovim's own `gr*` family, and leaving those in place costs a
            // full `timeoutlen` before plain `gr` fires — measured at 1,032ms.
            let shadowed = await prefixKeysShadowing(
                keys: keys, editorRuntimePath: editorRuntimePath, on: channel
            )

            // The user's own longer key changes the answer. Deleting it breaks AC-6; keeping it
            // and mapping anyway makes *their* key wait a second on every press. Neither is ours
            // to choose, so we take the third option and install nothing — recorded, not silent.
            if !shadowed.user.isEmpty {
                keyMappingOutcomes.append(
                    EditorKeyMappingOutcome(
                        keys: keys,
                        request: request,
                        resolution: .withheldToKeepUserPrefixKeys,
                        userScriptPath: shadowed.userScriptPath,
                        conflictingKeys: shadowed.user
                    )
                )
                continue
            }

            for candidate in shadowed.editorDefaults {
                _ = await runLua(
                    NeovimNavigationKeyScript.deleteEditorDefaultScript(keys: candidate), on: channel
                )
            }

            let installed = await runLua(
                NeovimNavigationKeyScript.installMappingScript(
                    keys: keys,
                    request: request.rawValue,
                    notificationName: Self.navigationNotification
                ),
                arguments: [.integer(Int64(channelIdentifier))],
                on: channel
            )
            // A mapping that failed to install is left out of the outcomes rather than recorded
            // as installed. The list is the evidence; a wrong entry is worse than a missing one.
            guard installed != nil else { continue }

            keyMappingOutcomes.append(
                EditorKeyMappingOutcome(
                    keys: keys,
                    request: request,
                    resolution: NeovimKeyMappingClassifier.resolution(for: owner)
                )
            )
        }
    }

    /// Asks Neovim who holds a key and judges the answer.
    private func keyMappingOwner(
        forKeys keys: String, editorRuntimePath: String, on channel: NeovimChannel
    ) async -> NeovimKeyMappingOwner? {
        guard let answer = await runLua(
            NeovimNavigationKeyScript.mappingReportScript(keys: keys), on: channel
        ) else {
            return nil
        }
        guard let report = Self.makeKeyMappingReport(fromLuaAnswer: answer) else { return nil }
        return NeovimKeyMappingClassifier.owner(of: report, editorRuntimePath: editorRuntimePath)
    }

    /// The longer keys that would make `keys` ambiguous, split by who owns them.
    ///
    /// The split is the whole point: the editor's own can be removed, the user's cannot, and
    /// which of the two is present decides whether we map this key at all.
    private func prefixKeysShadowing(
        keys: String, editorRuntimePath: String, on channel: NeovimChannel
    ) async -> (editorDefaults: [String], user: [String], userScriptPath: String?) {
        var editorDefaults: [String] = []
        var user: [String] = []
        var userScriptPath: String?

        for candidate in NeovimNavigationKeyScript.editorDefaultPrefixedKeys
        where candidate.hasPrefix(keys) && candidate != keys {
            let owner = await keyMappingOwner(
                forKeys: candidate, editorRuntimePath: editorRuntimePath, on: channel
            )
            switch owner {
            case .editorDefault:
                editorDefaults.append(candidate)
            case .user(let scriptPath):
                user.append(candidate)
                userScriptPath = userScriptPath ?? scriptPath
            case .nobody, .none:
                continue
            }
        }

        return (editorDefaults, user, userScriptPath)
    }

    /// The languages the application ships a parser **and** a highlight query for.
    ///
    /// Kotlin and TypeScript are absent, and both were measured rather than assumed. Kotlin's
    /// grammar publishes no `highlights.scm`; TypeScript's is 35 lines of type rules that return
    /// no captures at all for ordinary statements. Starting tree-sitter for either turns the regex
    /// syntax off and supplies nothing, which trades imperfect colour for none.
    static let treeSitterLanguages = ["java"]

    /// Where the bundled parsers live, or nil when running somewhere they were not bundled.
    ///
    /// Returning nil rather than a guessed path matters: a wrong runtime path makes Neovim fail
    /// to find a parser, and that failure looks exactly like "this language has no highlighting"
    /// — the state we are trying to leave.
    static func bundledTreeSitterRuntimePath() -> String? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("treesitter"),
            // Running from the build directory rather than the assembled `.app`, which is how
            // the tests and `swift run` see the world.
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // Editing
                .deletingLastPathComponent()   // CodeNavigatorCore
                .deletingLastPathComponent()   // Sources
                .deletingLastPathComponent()   // repository root
                .appendingPathComponent("Resources/treesitter"),
        ]
        return candidates
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("parser").path) }?
            .path
    }

    /// Installs the allow-list and the same-symbol highlight, and restores any palette the
    /// application already gave us (a restart must not come back colourless).
    private func installHighlightBehaviour(on channel: NeovimChannel) async {
        let allowedFileTypes = NeovimSyntaxAllowList.highlightedFileTypes.sorted()

        // Before the allow-list, because the allow-list turns regex syntax off for languages we
        // do not support and tree-sitter is what supplies the colour for the ones we do.
        if let runtimePath = Self.bundledTreeSitterRuntimePath() {
            _ = await runLua(
                NeovimHighlightScript.installTreeSitterScript(
                    runtimePath: runtimePath,
                    languages: Self.treeSitterLanguages
                ),
                on: channel
            )
        }

        _ = await runLua(
            NeovimHighlightScript.installAllowListScript(allowedFileTypes: allowedFileTypes),
            on: channel
        )
        _ = await runLua(
            NeovimHighlightScript.installSameSymbolHighlightScript(allowedFileTypes: allowedFileTypes),
            on: channel
        )

        if let palette = appliedSyntaxPalette {
            _ = await runLua(
                NeovimHighlightScript.applyPaletteScript(notificationName: "applied"),
                arguments: [Self.makePaletteValue(from: palette)],
                on: channel
            )
        }
    }

    public func applySyntaxPalette(_ palette: EditorSyntaxPalette) async throws {
        let channel = try requireChannel()
        appliedSyntaxPalette = palette
        _ = try await channel.request("nvim_exec_lua", [
            .string(NeovimHighlightScript.applyPaletteScript(notificationName: "applied")),
            .array([Self.makePaletteValue(from: palette)]),
        ])
    }

    public func navigationRequests() async -> AsyncStream<EditorNavigationRequest> {
        navigationRequestBroadcaster.subscribe { [weak self] identifier in
            Task { await self?.removeNavigationRequestSubscriber(identifier) }
        }
    }

    private func removeNavigationRequestSubscriber(_ identifier: Int) {
        navigationRequestBroadcaster.unsubscribe(identifier)
    }

    public func navigationKeyMappingOutcomes() async -> [EditorKeyMappingOutcome] {
        keyMappingOutcomes
    }

    /// Which key means which request. One place, so the two never drift apart.
    private static let navigationKeyAssignments: [(keys: String, request: EditorNavigationRequest)] = [
        ("gd", .goToDefinition),
        ("gr", .findReferences),
    ]

    /// Parses `present|scriptIdentifier|scriptPath`.
    ///
    /// Split with `maxSplits` so a path containing `|` survives — an odd file name should not
    /// quietly turn a user's mapping into an unowned one.
    private static func makeKeyMappingReport(fromLuaAnswer answer: String) -> NeovimKeyMappingReport? {
        let parts = answer.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        let scriptPath = String(parts[2])
        return NeovimKeyMappingReport(
            isPresent: parts[0] == "true",
            scriptIdentifier: Int(parts[1]) ?? 0,
            scriptPath: scriptPath.isEmpty ? nil : scriptPath
        )
    }

    private static func makePaletteValue(from palette: EditorSyntaxPalette) -> MessagePackValue {
        // `function` is a Lua keyword, so the field it lands in cannot share the contract's name.
        .map([
            MessagePackKeyValuePair(key: .string("keyword"), value: packed(palette.keyword)),
            MessagePackKeyValuePair(key: .string("type"), value: packed(palette.type)),
            MessagePackKeyValuePair(key: .string("functionName"), value: packed(palette.function)),
            MessagePackKeyValuePair(key: .string("string"), value: packed(palette.string)),
            MessagePackKeyValuePair(key: .string("number"), value: packed(palette.number)),
            MessagePackKeyValuePair(key: .string("comment"), value: packed(palette.comment)),
            MessagePackKeyValuePair(
                key: .string("keywordIsBold"), value: .boolean(palette.keywordIsBold)
            ),
            MessagePackKeyValuePair(
                key: .string("normalForeground"), value: packed(palette.normalForeground)
            ),
            MessagePackKeyValuePair(
                key: .string("normalBackground"), value: packed(palette.normalBackground)
            ),
            MessagePackKeyValuePair(
                key: .string("sameSymbolBackground"), value: packed(palette.sameSymbolBackground)
            ),
            MessagePackKeyValuePair(
                key: .string("selectionBackground"), value: packed(palette.selectionBackground)
            ),
            MessagePackKeyValuePair(
                key: .string("annotation"), value: packed(palette.annotation)
            ),
            MessagePackKeyValuePair(
                key: .string("lineNumber"), value: packed(palette.lineNumberForeground)
            ),
            MessagePackKeyValuePair(
                key: .string("currentLineNumber"),
                value: packed(palette.currentLineNumberForeground)
            ),
            MessagePackKeyValuePair(
                key: .string("statusLineForeground"), value: packed(palette.statusLineForeground)
            ),
            MessagePackKeyValuePair(
                key: .string("statusLineBackground"), value: packed(palette.statusLineBackground)
            ),
            MessagePackKeyValuePair(
                key: .string("endOfBuffer"), value: packed(palette.endOfBufferForeground)
            ),
            MessagePackKeyValuePair(
                key: .string("nonText"), value: packed(palette.nonTextForeground)
            ),
            MessagePackKeyValuePair(
                key: .string("signColumnBackground"), value: packed(palette.signColumnBackground)
            ),
        ])
    }

    private static func packed(_ colour: EditorColor) -> MessagePackValue {
        .integer(Int64(colour.red) << 16 | Int64(colour.green) << 8 | Int64(colour.blue))
    }

    // MARK: - Small RPC helpers

    private func requestChannelIdentifier(from channel: NeovimChannel) async -> Int? {
        guard let info = try? await channel.request("nvim_get_api_info", []) else { return nil }
        return info.arrayValue?.first?.integerValue.map { Int($0) }
    }

    /// Runs a Lua chunk and returns the string it produced, or `nil` if the call failed.
    ///
    /// These call sites are all derived behaviour — highlighting, convenience keys — and INV-8
    /// says their failure must not stop the user editing. What it must not do is *lie*: a
    /// failure returns `nil` and the caller leaves the corresponding evidence out.
    @discardableResult
    private func runLua(
        _ script: String, arguments: [MessagePackValue] = [], on channel: NeovimChannel
    ) async -> String? {
        guard let value = try? await channel.request(
            "nvim_exec_lua", [.string(script), .array(arguments)]
        ) else {
            return nil
        }
        return value.stringValue
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
        case Self.dirtyNotification:
            if let fields = notification.parameters.first?.mapValue,
               let path = fields.first(where: { $0.key.stringValue == "path" })?.value.stringValue {
                dirtyChangeBroadcaster.send(path)
            }
        case Self.navigationNotification:
            if let fields = notification.parameters.first?.mapValue,
               let rawRequest = fields
                   .first(where: { $0.key.stringValue == "request" })?.value.stringValue,
               let request = EditorNavigationRequest(rawValue: rawRequest) {
                navigationRequestBroadcaster.send(request)
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

        // A start-up that already failed keeps its diagnosis. The process then exiting is a
        // consequence of that failure, not news about it, and `disconnected` would replace a
        // specific answer — which stage timed out, which version was found — with "the session
        // ended, restart it". That sends the user to restart something that was never up, and it
        // is the same collapse D-10 was about: a precise failure flattened into a generic one.
        if case .startupFailed = stateBroadcaster.latest {
            return
        }
        updateState(.disconnected(reason: "편집 세션이 종료됐습니다 (상태 \(status)). 재기동할 수 있습니다."))
    }

    /// The current buffer's line under the cursor, so a test can assert that input actually
    /// reached the buffer rather than merely that a notification arrived. Not part of the contract.
    func currentLineForTesting() async throws -> String? {
        guard let channel else { return nil }
        return try await channel.request("nvim_get_current_line", []).stringValue
    }


    /// The lines of the loaded buffer holding this file, or nil when the editor is not holding it.
    ///
    /// Paths are compared after `realpath`: Neovim reports the name it was opened with, which can
    /// differ from the canonical path by a symlink (`/var` vs `/private/var` on macOS) while
    /// naming the same file. Comparing the strings as given would answer "not open" for a file
    /// that is open.
    func bufferLines(forFileAt canonicalPath: String) async throws -> [String]? {
        guard let channel, isUserInterfaceAttached else {
            return nil
        }

        // Buffer handles arrive as msgpack ext values; they are passed straight back as arguments
        // rather than unwrapped, so the codec round-trip is the only thing that has to be right.
        let buffers = try await channel.request("nvim_list_bufs", []).arrayValue ?? []

        for buffer in buffers {
            let isLoaded = try await channel.request("nvim_buf_is_loaded", [buffer]).booleanValue ?? false
            guard isLoaded else {
                continue
            }

            let name = try await channel.request("nvim_buf_get_name", [buffer]).stringValue ?? ""
            guard !name.isEmpty, Self.canonicalPath(of: name) == canonicalPath else {
                continue
            }

            let lines = try await channel.request("nvim_buf_get_lines", [
                buffer, .integer(0), .integer(-1), .boolean(false),
            ])
            // A failure to read the reply is reported, never returned as "no lines". `nil` here
            // means the editor is not holding this file and the caller falls back to disk; an
            // empty array means the file is genuinely empty. Neither is true when the reply could
            // not be decoded, and the render view says "내용이 없습니다" for whatever it is given.
            guard let text = lines.textArrayValue else {
                throw NavigatorError.editorRequestFailed(
                    method: "nvim_buf_get_lines",
                    reason: "버퍼 줄을 텍스트로 읽지 못했습니다"
                )
            }
            return text
        }

        return nil
    }

    private static func canonicalPath(of path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Buffer and register access for tests that must check the editor's real state rather than
    /// what the engine reports about it. Not part of the contract.
    func bufferLinesForTesting() async throws -> [String] {
        let channel = try requireChannel()
        let value = try await channel.request("nvim_buf_get_lines", [
            .integer(0), .integer(0), .integer(-1), .boolean(false),
        ])
        guard let text = value.textArrayValue else {
            throw NavigatorError.editorRequestFailed(
                method: "nvim_buf_get_lines",
                reason: "버퍼 줄을 텍스트로 읽지 못했습니다"
            )
        }
        return text
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

    /// Tabpage state read straight from Neovim, for tests that must check the editor rather than
    /// what this type believes about it.
    /// Asks Neovim to evaluate an expression, for tests that must check the editor's own view of
    /// itself rather than what this type believes. Not part of the contract.
    func evaluateForTesting(_ expression: String) async throws -> String {
        let channel = try requireChannel()
        let value = try await channel.request("nvim_eval", [.string(expression)])
        return value.stringValue ?? ""
    }

    /// Runs a Lua chunk and returns whatever it stringifies, for spikes and tests that need to
    /// ask Neovim something an expression cannot express. Returns the string Lua produced, so an
    /// answer of `"0"` stays distinguishable from "the call produced nothing" — `nvim_eval` folds
    /// both into an empty string here, which is exactly the ambiguity these measurements cannot
    /// afford. Not part of the contract.
    func executeLuaForTesting(_ script: String) async throws -> String {
        let channel = try requireChannel()
        let value = try await channel.request("nvim_exec_lua", [.string(script), .array([])])
        guard let text = value.stringValue else {
            throw NavigatorError.editorUnavailable(reason: "Lua 가 문자열을 돌려주지 않았습니다: \(value)")
        }
        return text
    }

    func currentWorkingDirectoryForTesting() async throws -> String {
        let channel = try requireChannel()
        let value = try await channel.request("nvim_eval", [.string("getcwd()")])
        return value.stringValue ?? ""
    }

    func tabPageCountForTesting() async throws -> Int {
        let channel = try requireChannel()
        let value = try await channel.request("nvim_list_tabpages", [])
        return value.arrayValue?.count ?? 0
    }

    func showTabLineSettingForTesting() async throws -> Int {
        let channel = try requireChannel()
        let value = try await channel.request("nvim_eval", [.string("&showtabline")])
        guard let integer = value.integerValue else { return -1 }
        return Int(integer)
    }

    // MARK: - Helpers

    private func makeStartupFailure(
        kind: EditorStartupFailureKind,
        reason: String,
        foundVersion: String?
    ) -> EditorStartupFailure {
        EditorStartupFailure(
            kind: kind,
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
