/// A decoded MessagePack value — the wire vocabulary of the Neovim RPC channel (ADR-0006).
///
/// Signed and unsigned integers are separate cases because MessagePack encodes them separately.
/// The wire format has no "signed non-negative" encoding, so a non-negative `.integer` comes back
/// as `.unsignedInteger` with the same numeric value; read both through ``integerValue``.
public enum MessagePackValue: Sendable, Hashable {
    case nilValue
    case boolean(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case double(Double)
    case string(String)
    case binary([UInt8])
    case array([MessagePackValue])
    case map([MessagePackKeyValuePair])
    case extended(type: Int8, bytes: [UInt8])

    /// The numeric value of either integer case, or nil for any other case (or a value too
    /// large for `Int`). Lets RPC parsing read a number without caring how it was encoded.
    public var integerValue: Int? {
        switch self {
        case .integer(let value): return Int(exactly: value)
        case .unsignedInteger(let value): return Int(exactly: value)
        default: return nil
        }
    }

    public var booleanValue: Bool? {
        guard case .boolean(let value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [MessagePackValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var mapValue: [MessagePackKeyValuePair]? {
        guard case .map(let value) = self else { return nil }
        return value
    }
}
