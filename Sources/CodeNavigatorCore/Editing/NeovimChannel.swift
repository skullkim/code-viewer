import CodeNavigatorContract
import Foundation

/// The msgpack-RPC channel to an embedded Neovim process.
///
/// Owns the process, the framing, and the correlation of requests to responses. Everything above
/// it (grid state, editor session) talks in terms of method calls and notifications.
///
/// Neovim is started with `--embed` and **without** `--clean`: the user's own configuration must
/// load untouched (INV-4). Note that `--embed` blocks Neovim's start-up until a UI attaches, so
/// user configuration has not run until `nvim_ui_attach` has been called (ADR-0006).
actor NeovimChannel {
    /// Raised when a request cannot be answered.
    struct RequestFailure: Error {
        let method: String
        let reason: String
    }

    private let process = Process()
    private let standardInputPipe = Pipe()
    private let standardOutputPipe = Pipe()
    private let byteStream = NeovimByteStream()

    private var nextRequestIdentifier: UInt32 = 1
    private var pendingRequests: [UInt32: CheckedContinuation<MessagePackValue, any Error>] = [:]
    private var notificationContinuations: [UUID: AsyncStream<NeovimNotification>.Continuation] = [:]
    private var terminationHandlers: [UUID: @Sendable (Int32) -> Void] = [:]
    private var isRunning = false
    private var readerTask: Task<Void, Never>?

    /// Ordinary requests time out rather than hanging the interface forever if Neovim stops
    /// answering. Measured: a request on a live session answers in well under 50ms even at load
    /// 25 on 12 cores, so five seconds is far past "slow" and firmly in "wedged".
    static let defaultRequestTimeout: Duration = .seconds(5)

    /// Start-up gets a longer budget than ordinary requests.
    ///
    /// Measured on an idle and a heavily loaded machine (load 25.7, 30 samples): spawn → attach →
    /// handshake completes in 0.013–0.046s, so the ordinary five seconds is already ~100× the
    /// observed worst case. A field failure at five seconds was reported and could not be
    /// reproduced across 30 attempts, which means the real tail is longer than anything measurable
    /// here — cold disk, a contended volume, a machine paging.
    ///
    /// Raising this costs nothing in the case people actually hit: **a missing editor is detected
    /// before spawning** (the executable search is a file-existence check), so "not installed"
    /// still fails instantly. The only case that waits longer is one that was going to fail
    /// anyway, and waiting there is better than telling a user their working editor is missing.
    static let startupTimeout: Duration = .seconds(20)

    /// How long the editor is given to leave on its own before it is killed outright.
    ///
    /// Long enough that an ordinary exit (measured at 0.02–0.04s) always wins the race, short
    /// enough that a user closing a project does not accumulate editors.
    private static let terminationGracePeriod: TimeInterval = 0.5

    /// Stops the editor process for good, escalating if it will not leave.
    ///
    /// SIGTERM is not sufficient, which took measuring to believe. An abandoned session's editor
    /// was sent SIGTERM and was still in state `S` **twenty seconds later** — every one of them,
    /// every run. What actually stops an embedded Neovim is its stdin reaching EOF; the signal is
    /// the polite request, and when the channel teardown does not produce that EOF the request is
    /// simply declined. Without the escalation the editor runs until the machine reboots, which is
    /// exactly the orphan D-2 is about.
    ///
    /// The delayed kill re-checks the pid rather than holding the process object, so it costs
    /// nothing in the normal case: by then the process is gone and `kill` finds nothing.
    private static func stopProcess(_ process: Process) {
        guard process.isRunning else { return }
        let processIdentifier = process.processIdentifier
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + terminationGracePeriod) {
            // 죽었으면 kill(pid, 0) 이 실패하므로 아무 일도 일어나지 않는다.
            if kill(processIdentifier, 0) == 0 {
                kill(processIdentifier, SIGKILL)
            }
        }
    }

    init() {}

    /// Last resort: an owner that disappears without saying goodbye still must not leave an
    /// editor running.
    ///
    /// `shutDown()` is the intended path and every deliberate teardown uses it. This covers the
    /// one nobody writes down — a session that simply goes out of scope, which is what a retry
    /// looks like when the interface builds a fresh session instead of reusing the old one. The
    /// process outlives its owner otherwise, invisible to everything that could stop it.
    deinit {
        standardOutputPipe.fileHandleForReading.readabilityHandler = nil
        try? standardInputPipe.fileHandleForWriting.close()
        Self.stopProcess(process)
    }

    // MARK: - Lifecycle

    /// - Parameter workingDirectory: where the editor starts. Passing this rather than letting the
    ///   child inherit matters: the application's own directory is whatever the user happened to
    ///   launch from, and anchoring an editor's relative paths and directory-sensitive start-up to
    ///   that is a behaviour that changes with how the app was started. It also hands the editor a
    ///   directory outside the open project, which is the opposite of what INV-6 asks for.
    func start(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) throws {
        // Writing to a dead process's stdin raises SIGPIPE, whose default action terminates the
        // whole application. Ignoring it turns that into an ordinary EPIPE we can report — this
        // single line is what keeps a Neovim crash from taking the app down with it.
        signal(SIGPIPE, SIG_IGN)

        process.executableURL = executableURL
        process.arguments = ["--embed"] + arguments
        if let environment {
            process.environment = environment
        }
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        process.standardInput = standardInputPipe
        process.standardOutput = standardOutputPipe
        process.standardError = FileHandle.nullDevice

        let stream = byteStream
        standardOutputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stream.append(Array(data))
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { await self?.handleTermination(status: status) }
        }

        do {
            try process.run()
        } catch {
            throw NavigatorError.editorUnavailable(reason: "Neovim을 시작할 수 없습니다: \(error.localizedDescription)")
        }
        isRunning = true
        startReading()
    }

    private func startReading() {
        // `weak self` is load-bearing, not hygiene. A strong capture here makes the channel keep
        // itself alive through its own reader task: the task runs as long as the stream is open,
        // the stream stays open as long as the process runs, and the process runs because nothing
        // ever deallocates the channel to stop it. An owner that drops the session then leaks an
        // editor that no code can reach — and `deinit` never fires to catch it.
        readerTask = Task { [byteStream, weak self] in
            for await event in byteStream.events {
                guard let self else { return }
                switch event {
                case .value(let value):
                    await self.dispatch(value)
                case .corrupted(let byte):
                    await self.failEverything(
                        reason: "편집기 채널이 손상됐습니다 (형식 바이트 0x\(String(byte, radix: 16)))"
                    )
                }
            }
        }
    }

    func terminate() {
        guard isRunning else { return }
        isRunning = false
        standardOutputPipe.fileHandleForReading.readabilityHandler = nil

        // Close the channel before signalling. This is the half that actually works: an embedded
        // Neovim leaves when its stdin reaches EOF, which is also how it notices its parent died.
        // SIGTERM is only the polite request, and it is declined more often than it looks — see
        // `stopProcess`, which is why the kill escalates.
        try? standardInputPipe.fileHandleForWriting.close()

        Self.stopProcess(process)
        byteStream.finish()
        readerTask?.cancel()
        for continuation in notificationContinuations.values {
            continuation.finish()
        }
        notificationContinuations.removeAll()
    }

    var isAlive: Bool { isRunning && process.isRunning }

    /// The child's pid, or `nil` when there is no child.
    ///
    /// Foundation answers `0` for a `Process` that was never launched, and `0` is not a harmless
    /// placeholder: `kill(0, …)` signals **the entire process group**. A caller that treats the
    /// answer as a pid and sends a signal to it would take down every process in the group,
    /// including the test runner and anything else the machine is sharing. Returning `nil` makes
    /// that mistake impossible to make by accident.
    var processIdentifier: Int32? {
        let identifier = process.processIdentifier
        return identifier > 0 ? identifier : nil
    }

    // MARK: - Requests and notifications

    @discardableResult
    func request(
        _ method: String,
        _ parameters: [MessagePackValue] = [],
        timeout: Duration = NeovimChannel.defaultRequestTimeout
    ) async throws -> MessagePackValue {
        guard isRunning else {
            throw NavigatorError.editorNotRunning
        }

        let identifier = nextRequestIdentifier
        nextRequestIdentifier &+= 1

        let frame = MessagePackEncoder.encode(
            .array([
                .unsignedInteger(UInt64(NeovimChannelMessage.requestKind)),
                .unsignedInteger(UInt64(identifier)),
                .string(method),
                .array(parameters),
            ])
        )

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.failRequest(
                identifier: identifier,
                reason: "응답이 없습니다 (\(timeout))"
            , method: method)
        }
        defer { timeoutTask.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[identifier] = continuation
            do {
                try standardInputPipe.fileHandleForWriting.write(contentsOf: Data(frame))
            } catch {
                pendingRequests.removeValue(forKey: identifier)?.resume(
                    throwing: NavigatorError.editorRequestFailed(
                        method: method,
                        reason: "쓰기 실패 — 편집기가 종료된 것으로 보입니다"
                    )
                )
            }
        }
    }

    /// Notifications from Neovim, primarily `redraw`. Each subscriber gets its own stream.
    func notifications() -> AsyncStream<NeovimNotification> {
        let identifier = UUID()
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            notificationContinuations[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeNotificationContinuation(identifier) }
            }
        }
    }

    func onTermination(_ handler: @escaping @Sendable (Int32) -> Void) {
        terminationHandlers[UUID()] = handler
    }

    // MARK: - Dispatch

    private func dispatch(_ value: MessagePackValue) {
        guard let message = NeovimChannelMessage(value: value) else { return }

        switch message {
        case .response(let identifier, let error, let result):
            guard let continuation = pendingRequests.removeValue(forKey: identifier) else { return }
            if case .nilValue = error {
                continuation.resume(returning: result)
            } else {
                continuation.resume(
                    throwing: RequestFailure(method: "", reason: Self.describe(error))
                )
            }

        case .notification(let method, let parameters):
            let notification = NeovimNotification(method: method, parameters: parameters)
            for continuation in notificationContinuations.values {
                continuation.yield(notification)
            }
        }
    }

    private func removeNotificationContinuation(_ identifier: UUID) {
        notificationContinuations.removeValue(forKey: identifier)
    }

    private func failRequest(identifier: UInt32, reason: String, method: String) {
        pendingRequests.removeValue(forKey: identifier)?.resume(
            throwing: NavigatorError.editorRequestFailed(method: method, reason: reason)
        )
    }

    private func handleTermination(status: Int32) {
        isRunning = false
        failEverything(reason: "편집기 프로세스가 종료됐습니다 (상태 \(status))")
        for handler in terminationHandlers.values {
            handler(status)
        }
    }

    /// Fails every in-flight request at once, so no caller is left awaiting a process that is
    /// never going to answer.
    private func failEverything(reason: String) {
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: NavigatorError.editorUnavailable(reason: reason))
        }
    }

    private static func describe(_ value: MessagePackValue) -> String {
        switch value {
        case .string(let text):
            return text
        case .array(let items):
            return items.compactMap { $0.stringValue }.joined(separator: " ")
        default:
            return "\(value)"
        }
    }
}

/// One notification from Neovim: a method name and its parameters.
struct NeovimNotification: Sendable {
    let method: String
    let parameters: [MessagePackValue]
}
