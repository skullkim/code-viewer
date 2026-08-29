/// One entry of a MessagePack map.
///
/// Maps are kept as an ordered list of pairs rather than a Swift `Dictionary`: MessagePack keys
/// can be any value, and Neovim's redraw events rely on the order in which it sent them.
public struct MessagePackKeyValuePair: Sendable, Hashable {
    public let key: MessagePackValue
    public let value: MessagePackValue

    public init(key: MessagePackValue, value: MessagePackValue) {
        self.key = key
        self.value = value
    }
}
