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

    /// Requests time out rather than hanging the interface forever if Neovim stops answering.
    static let defaultRequestTimeout: Duration = .seconds(5)

    init() {}

    // MARK: - Lifecycle

    func start(executableURL: URL, arguments: [String] = [], environment: [String: String]? = nil) throws {
        // Writing to a dead process's stdin raises SIGPIPE, whose default action terminates the
        // whole application. Ignoring it turns that into an ordinary EPIPE we can report — this
        // single line is what keeps a Neovim crash from taking the app down with it.
        signal(SIGPIPE, SIG_IGN)

        process.executableURL = executableURL
        process.arguments = ["--embed"] + arguments
        if let environment {
            process.environment = environment
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
        readerTask = Task { [byteStream] in
            for await event in byteStream.events {
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
        if process.isRunning {
            process.terminate()
        }
        byteStream.finish()
        readerTask?.cancel()
        for continuation in notificationContinuations.values {
            continuation.finish()
        }
        notificationContinuations.removeAll()
    }

    var isAlive: Bool { isRunning && process.isRunning }

    var processIdentifier: Int32 { process.processIdentifier }

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
