/// Fans one source of values out to any number of `AsyncStream` subscribers.
///
/// Several parts of the interface watch the same thing — grid frames, session state, editor
/// status — and each needs its own stream. Without this, every one of them would repeat the same
/// continuation bookkeeping, and each copy would be a chance to leak a subscriber.
///
/// The latest value is replayed to a new subscriber so a view that attaches late is never blank.
struct EventBroadcaster<Value: Sendable> {
    private var continuations: [Int: AsyncStream<Value>.Continuation] = [:]
    private var nextIdentifier = 0
    private var latestValue: Value?

    init(initialValue: Value? = nil) {
        self.latestValue = initialValue
    }

    var latest: Value? { latestValue }

    mutating func subscribe(onCancel: @escaping @Sendable (Int) -> Void) -> AsyncStream<Value> {
        let identifier = nextIdentifier
        nextIdentifier += 1

        let replayValue = latestValue
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
