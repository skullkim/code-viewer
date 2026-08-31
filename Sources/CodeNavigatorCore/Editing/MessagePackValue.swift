import Foundation

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

    /// Text, whether it arrived as msgpack `str` or as `bin` holding UTF-8.
    ///
    /// Neovim sends `str` for buffer lines today — measured across fixstr, str8 and str16, with
    /// valid and invalid UTF-8. But `bin` is a legitimate encoding for the same payload, and a
    /// reader that only accepts one of them turns a protocol detail into missing content.
    ///
    /// Separate from `stringValue`, which stays strict: somewhere that genuinely needs to know a
    /// value *was* a string should not be quietly handed decoded bytes.
    public var textValue: String? {
        switch self {
        case .string(let value):
            return value
        case .binary(let bytes):
            return String(data: Data(bytes), encoding: .utf8)
        default:
            return nil
        }
    }

    /// Every element as text, or `nil` if any one of them cannot be read.
    ///
    /// **All-or-nothing on purpose.** `compactMap` would drop the unreadable ones and return a
    /// shorter array, which is indistinguishable from a buffer that really is that short — and an
    /// empty result is indistinguishable from an empty buffer. Three situations, one value, and
    /// the interface says "이 파일에는 내용이 없습니다" for all three.
    public var textArrayValue: [String]? {
        guard case .array(let items) = self else {
            return nil
        }
        var lines: [String] = []
        lines.reserveCapacity(items.count)
        for item in items {
            guard let text = item.textValue else {
                return nil
            }
            lines.append(text)
        }
        return lines
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
