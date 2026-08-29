/// One decoded message from the Neovim channel.
///
/// msgpack-rpc puts a small integer first to say which of the three shapes follows.
enum NeovimChannelMessage {
    case response(requestIdentifier: UInt32, error: MessagePackValue, result: MessagePackValue)
    case notification(method: String, parameters: [MessagePackValue])

    static let requestKind = 0
    static let responseKind = 1
    static let notificationKind = 2

    /// Reads a decoded value as a channel message, or `nil` when it is neither shape we handle.
    /// Requests *from* Neovim are not used by this application and are ignored rather than
    /// answered, which keeps the channel from stalling on a message we have no handler for.
    init?(value: MessagePackValue) {
        guard let items = value.arrayValue, let kind = items.first?.integerValue else {
            return nil
        }

        switch kind {
        case Self.responseKind where items.count == 4:
            guard let identifier = items[1].integerValue else { return nil }
            self = .response(
                requestIdentifier: UInt32(identifier),
                error: items[2],
                result: items[3]
            )

        case Self.notificationKind where items.count == 3:
            guard let method = items[1].stringValue, let parameters = items[2].arrayValue else {
                return nil
            }
            self = .notification(method: method, parameters: parameters)

        default:
            return nil
        }
    }
}
