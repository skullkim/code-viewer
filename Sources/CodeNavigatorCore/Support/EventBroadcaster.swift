/// Fans one source of values out to any number of `AsyncStream` subscribers.
///
/// Several parts of the interface watch the same thing — grid frames, session state, editor
/// status — and each needs its own stream. Without this, every one of them would repeat the same
/// continuation bookkeeping, and each copy would be a chance to leak a subscriber.
///
/// By default the latest value is replayed to a new subscriber, so a view that attaches late is
/// never blank. That is right for **state** — a grid frame, a session status, an index progress.
///
/// It is wrong for **events**. Replaying a `gd` keypress would send a late subscriber jumping to
/// a definition the user never asked for, at a moment they did not choose. Which of the two a
/// broadcaster carries is a property of the thing, not of the value, so it is declared.
struct EventBroadcaster<Value: Sendable> {

    /// Whether a new subscriber hears what it missed.
    enum ReplayPolicy: Sendable {
        /// Replay the most recent value on subscribe. For state.
        case replayLatest
        /// Deliver only what arrives after subscribing. For events.
        case eventsOnly
    }

    private var continuations: [Int: AsyncStream<Value>.Continuation] = [:]
    private var nextIdentifier = 0
    private var latestValue: Value?
    private let replayPolicy: ReplayPolicy

    init(initialValue: Value? = nil, replayPolicy: ReplayPolicy = .replayLatest) {
        self.latestValue = initialValue
        self.replayPolicy = replayPolicy
    }

    var latest: Value? { latestValue }

    mutating func subscribe(onCancel: @escaping @Sendable (Int) -> Void) -> AsyncStream<Value> {
        let identifier = nextIdentifier
        nextIdentifier += 1

        let replayValue = replayPolicy == .replayLatest ? latestValue : nil
        var registered: AsyncStream<Value>.Continuation?
        let stream = AsyncStream(Value.self, bufferingPolicy: .unbounded) { continuation in
            registered = continuation
            if let replayValue {
                continuation.yield(replayValue)
            }
            continuation.onTermination = { _ in onCancel(identifier) }
        }
        continuations[identifier] = registered
        return stream
    }

    mutating func unsubscribe(_ identifier: Int) {
        continuations.removeValue(forKey: identifier)
    }

    mutating func send(_ value: Value) {
        latestValue = value
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }

    mutating func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
