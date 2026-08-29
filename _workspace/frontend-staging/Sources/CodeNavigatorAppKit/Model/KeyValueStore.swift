import Foundation

/// The small slice of persistence the shell needs.
///
/// A protocol rather than `UserDefaults` directly, so restoration logic can be tested
/// without touching the user's real preferences — and so a test can hand it damaged data
/// on purpose.
public protocol KeyValueStore: AnyObject, Sendable {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
}

extension UserDefaults: @unchecked @retroactive Sendable {}

extension UserDefaults: KeyValueStore {
    public func data(forKey key: String) -> Data? {
        object(forKey: key) as? Data
    }

    public func setData(_ data: Data?, forKey key: String) {
        set(data, forKey: key)
    }
}

/// An in-memory store for tests.
public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    public init() {}

    public func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public func setData(_ data: Data?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = data
    }
}
