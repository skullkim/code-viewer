/// One top-level menu and its rows.
public struct MenuDescriptor: Sendable, Hashable {
    public let title: String
    public let items: [MenuItemDescriptor]

    public init(title: String, items: [MenuItemDescriptor]) {
        self.title = title
        self.items = items
    }
}
