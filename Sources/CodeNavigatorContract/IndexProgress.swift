/// How far a full index or rescan has got. `total` is 0 while the file list is still being built.
public struct IndexProgress: Sendable, Hashable, Codable {
    public let completed: Int
    public let total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }

    public var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}
