/// Encodes a ``MessagePackValue`` to bytes, always choosing the shortest form the value fits in
/// — which is also what Neovim sends, so encoder and decoder stay symmetric in practice.
public enum MessagePackEncoder {

    public static func encode(_ value: MessagePackValue) -> [UInt8] {
        var bytes: [UInt8] = []
        append(value, to: &bytes)
        return bytes
    }

    private static func append(_ value: MessagePackValue, to bytes: inout [UInt8]) {
        switch value {
        case .nilValue:
            bytes.append(MessagePackFormatByte.nilValue)

        case .boolean(let boolean):
            bytes.append(boolean ? MessagePackFormatByte.booleanTrue : MessagePackFormatByte.booleanFalse)

        case .integer(let integer):
            appendInteger(integer, to: &bytes)

        case .unsignedInteger(let unsignedInteger):
            appendUnsignedInteger(unsignedInteger, to: &bytes)

        case .double(let double):
            bytes.append(MessagePackFormatByte.float64)
            appendBigEndian(double.bitPattern, to: &bytes)

        case .string(let text):
            appendString(text, to: &bytes)

        case .binary(let payload):
            appendBinary(payload, to: &bytes)

        case .array(let items):
            appendArray(items, to: &bytes)

        case .map(let pairs):
            appendMap(pairs, to: &bytes)

        case .extended(let type, let payload):
            appendExtended(type: type, payload: payload, to: &bytes)
        }
    }

    /// Non-negative values take the unsigned encodings: MessagePack has no signed positive form,
    /// so `.integer(5)` and `.unsignedInteger(5)` produce the same single byte.
    private static func appendInteger(_ value: Int64, to bytes: inout [UInt8]) {
        if value >= 0 {
            appendUnsignedInteger(UInt64(value), to: &bytes)
            return
        }
        if value >= MessagePackFormatByte.negativeFixedIntegerMinimum {
            bytes.append(UInt8(bitPattern: Int8(value)))
            return
        }
        if value >= Int64(Int8.min) {
            bytes.append(MessagePackFormatByte.integer8)
            bytes.append(UInt8(bitPattern: Int8(value)))
            return
        }
        if value >= Int64(Int16.min) {
            bytes.append(MessagePackFormatByte.integer16)
            appendBigEndian(UInt16(bitPattern: Int16(value)), to: &bytes)
            return
        }
        if value >= Int64(Int32.min) {
            bytes.append(MessagePackFormatByte.integer32)
            appendBigEndian(UInt32(bitPattern: Int32(value)), to: &bytes)
            return
        }
        bytes.append(MessagePackFormatByte.integer64)
        appendBigEndian(UInt64(bitPattern: value), to: &bytes)
    }

    private static func appendUnsignedInteger(_ value: UInt64, to bytes: inout [UInt8]) {
        if value <= MessagePackFormatByte.positiveFixedIntegerMaximum {
            bytes.append(UInt8(value))
            return
        }
        if value <= UInt64(UInt8.max) {
            bytes.append(MessagePackFormatByte.unsignedInteger8)
            bytes.append(UInt8(value))
            return
        }
        if value <= UInt64(UInt16.max) {
            bytes.append(MessagePackFormatByte.unsignedInteger16)
            appendBigEndian(UInt16(value), to: &bytes)
            return
        }
        if value <= UInt64(UInt32.max) {
            bytes.append(MessagePackFormatByte.unsignedInteger32)
            appendBigEndian(UInt32(value), to: &bytes)
            return
        }
        bytes.append(MessagePackFormatByte.unsignedInteger64)
        appendBigEndian(value, to: &bytes)
    }

    private static func appendString(_ text: String, to bytes: inout [UInt8]) {
        let utf8Bytes = Array(text.utf8)

        if utf8Bytes.count <= MessagePackFormatByte.fixedStringMaximumLength {
            bytes.append(MessagePackFormatByte.fixedStringPrefix | UInt8(utf8Bytes.count))
        } else if utf8Bytes.count <= Int(UInt8.max) {
            bytes.append(MessagePackFormatByte.string8)
            bytes.append(UInt8(utf8Bytes.count))
        } else if utf8Bytes.count <= Int(UInt16.max) {
            bytes.append(MessagePackFormatByte.string16)
            appendBigEndian(UInt16(utf8Bytes.count), to: &bytes)
        } else {
            bytes.append(MessagePackFormatByte.string32)
            appendBigEndian(UInt32(utf8Bytes.count), to: &bytes)
        }

        bytes.append(contentsOf: utf8Bytes)
    }

    private static func appendBinary(_ payload: [UInt8], to bytes: inout [UInt8]) {
        if payload.count <= Int(UInt8.max) {
            bytes.append(MessagePackFormatByte.binary8)
            bytes.append(UInt8(payload.count))
        } else if payload.count <= Int(UInt16.max) {
            bytes.append(MessagePackFormatByte.binary16)
            appendBigEndian(UInt16(payload.count), to: &bytes)
        } else {
            bytes.append(MessagePackFormatByte.binary32)
            appendBigEndian(UInt32(payload.count), to: &bytes)
        }

        bytes.append(contentsOf: payload)
    }

    private static func appendArray(_ items: [MessagePackValue], to bytes: inout [UInt8]) {
        if items.count <= MessagePackFormatByte.fixedArrayMaximumCount {
            bytes.append(MessagePackFormatByte.fixedArrayPrefix | UInt8(items.count))
        } else if items.count <= Int(UInt16.max) {
            bytes.append(MessagePackFormatByte.array16)
            appendBigEndian(UInt16(items.count), to: &bytes)
        } else {
            bytes.append(MessagePackFormatByte.array32)
            appendBigEndian(UInt32(items.count), to: &bytes)
        }

        for item in items {
            append(item, to: &bytes)
        }
    }

    private static func appendMap(_ pairs: [MessagePackKeyValuePair], to bytes: inout [UInt8]) {
        if pairs.count <= MessagePackFormatByte.fixedMapMaximumCount {
            bytes.append(MessagePackFormatByte.fixedMapPrefix | UInt8(pairs.count))
        } else if pairs.count <= Int(UInt16.max) {
            bytes.append(MessagePackFormatByte.map16)
            appendBigEndian(UInt16(pairs.count), to: &bytes)
        } else {
            bytes.append(MessagePackFormatByte.map32)
            appendBigEndian(UInt32(pairs.count), to: &bytes)
        }

        for pair in pairs {
            append(pair.key, to: &bytes)
            append(pair.value, to: &bytes)
        }
    }

    private static func appendExtended(type: Int8, payload: [UInt8], to bytes: inout [UInt8]) {
        // The five fixed sizes have dedicated format bytes; everything else carries a length.
        switch payload.count {
        case 1: bytes.append(MessagePackFormatByte.fixedExtended1)
        case 2: bytes.append(MessagePackFormatByte.fixedExtended2)
        case 4: bytes.append(MessagePackFormatByte.fixedExtended4)
        case 8: bytes.append(MessagePackFormatByte.fixedExtended8)
        case 16: bytes.append(MessagePackFormatByte.fixedExtended16)
        case ...Int(UInt8.max):
            bytes.append(MessagePackFormatByte.extended8)
            bytes.append(UInt8(payload.count))
        case ...Int(UInt16.max):
            bytes.append(MessagePackFormatByte.extended16)
            appendBigEndian(UInt16(payload.count), to: &bytes)
        default:
            bytes.append(MessagePackFormatByte.extended32)
            appendBigEndian(UInt32(payload.count), to: &bytes)
        }

        bytes.append(UInt8(bitPattern: type))
        bytes.append(contentsOf: payload)
    }

    /// MessagePack is big-endian for every multi-byte number.
    private static func appendBigEndian<Number: FixedWidthInteger>(
        _ number: Number,
        to bytes: inout [UInt8]
    ) {
        withUnsafeBytes(of: number.bigEndian) { rawBytes in
            bytes.append(contentsOf: rawBytes)
        }
    }
}
