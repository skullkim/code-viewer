/// Results for one file, in the order the engine returned them.
public struct FileGroup<Item: Sendable>: Sendable {
    public let path: String
    public let items: [Item]

    public var count: Int { items.count }

    public init(path: String, items: [Item]) {
        self.path = path
        self.items = items
    }
}

/// Groups a flat result list by file for the reference and full-text panels.
///
/// The engine returns results already sorted by path and then line. Grouping preserves
/// that order rather than imposing its own, so the panel can never disagree with the
/// engine about which result comes first.
public enum FileGrouping {
    public static func group<Item: Sendable>(_ items: [Item], by path: (Item) -> String) -> [FileGroup<Item>] {
        var order: [String] = []
        var itemsByPath: [String: [Item]] = [:]

        for item in items {
            let key = path(item)
            if itemsByPath[key] == nil {
                order.append(key)
            }
            itemsByPath[key, default: []].append(item)
        }

        return order.map { FileGroup(path: $0, items: itemsByPath[$0] ?? []) }
    }
}
