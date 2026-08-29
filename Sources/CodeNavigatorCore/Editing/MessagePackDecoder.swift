/// Decodes MessagePack frames out of a byte buffer, one value at a time.
///
/// A pipe hands over bytes that stop wherever the kernel happened to stop, not on frame
/// boundaries, so the decoder is built around two guarantees the reader loop needs:
///
///   1. an incomplete frame reports ``MessagePackError/needsMoreBytes`` rather than guessing;
///   2. a failed decode leaves ``position`` at the start of that frame, so the caller can keep
///      the unread tail, append the next read, and try the same frame again.
public struct MessagePackDecoder {
    private let bytes: [UInt8]

    /// How far decoding has got. After a successful decode this is the first byte of the next
    /// frame; after a failure it is unchanged.
    public private(set) var position: Int

    public init(bytes: [UInt8], startingAt position: Int = 0) {
        self.bytes = bytes
        self.position = position
    }

    public mutating func decodeValue() throws -> MessagePackValue {
        let frameStart = position
        do {
            return try decodeNextValue()
        } catch {
            position = frameStart
            throw error
        }
    }

    private mutating func decodeNextValue() throws -> MessagePackValue {
        let formatByte = try readByte()

        switch formatByte {
        case MessagePackFormatByte.positiveFixedIntegerRange:
            return .unsignedInteger(UInt64(formatByte))
        case MessagePackFormatByte.negativeFixedIntegerRange:
            return .integer(Int64(Int8(bitPattern: formatByte)))
        case MessagePackFormatByte.fixedMapRange:
            return try decodeMap(count: Int(formatByte - MessagePackFormatByte.fixedMapPrefix))
        case MessagePackFormatByte.fixedArrayRange:
            return try decodeArray(count: Int(formatByte - MessagePackFormatByte.fixedArrayPrefix))
        case MessagePackFormatByte.fixedStringRange:
            return try decodeString(byteCount: Int(formatByte - MessagePackFormatByte.fixedStringPrefix))

        case MessagePackFormatByte.nilValue:
            return .nilValue
        case MessagePackFormatByte.booleanFalse:
            return .boolean(false)
        case MessagePackFormatByte.booleanTrue:
            return .boolean(true)

        case MessagePackFormatByte.binary8:
            return .binary(try readBytes(count: Int(try readByte())))
        case MessagePackFormatByte.binary16:
            return .binary(try readBytes(count: Int(try readBigEndian(UInt16.self))))
        case MessagePackFormatByte.binary32:
            return .binary(try readBytes(count: Int(try readBigEndian(UInt32.self))))

        case MessagePackFormatByte.extended8:
            return try decodeExtended(byteCount: Int(try readByte()))
        case MessagePackFormatByte.extended16:
            return try decodeExtended(byteCount: Int(try readBigEndian(UInt16.self)))
        case MessagePackFormatByte.extended32:
            return try decodeExtended(byteCount: Int(try readBigEndian(UInt32.self)))
        case MessagePackFormatByte.fixedExtended1:
            return try decodeExtended(byteCount: 1)
        case MessagePackFormatByte.fixedExtended2:
            return try decodeExtended(byteCount: 2)
        case MessagePackFormatByte.fixedExtended4:
            return try decodeExtended(byteCount: 4)
        case MessagePackFormatByte.fixedExtended8:
            return try decodeExtended(byteCount: 8)
        case MessagePackFormatByte.fixedExtended16:
            return try decodeExtended(byteCount: 16)

        case MessagePackFormatByte.float32:
            return .double(Double(Float(bitPattern: try readBigEndian(UInt32.self))))
        case MessagePackFormatByte.float64:
            return .double(Double(bitPattern: try readBigEndian(UInt64.self)))

        case MessagePackFormatByte.unsignedInteger8:
            return .unsignedInteger(UInt64(try readByte()))
        case MessagePackFormatByte.unsignedInteger16:
            return .unsignedInteger(UInt64(try readBigEndian(UInt16.self)))
        case MessagePackFormatByte.unsignedInteger32:
            return .unsignedInteger(UInt64(try readBigEndian(UInt32.self)))
        case MessagePackFormatByte.unsignedInteger64:
            return .unsignedInteger(try readBigEndian(UInt64.self))

        case MessagePackFormatByte.integer8:
            return .integer(Int64(Int8(bitPattern: try readByte())))
        case MessagePackFormatByte.integer16:
            return .integer(Int64(Int16(bitPattern: try readBigEndian(UInt16.self))))
        case MessagePackFormatByte.integer32:
            return .integer(Int64(Int32(bitPattern: try readBigEndian(UInt32.self))))
        case MessagePackFormatByte.integer64:
            return .integer(Int64(bitPattern: try readBigEndian(UInt64.self)))

        case MessagePackFormatByte.string8:
            return try decodeString(byteCount: Int(try readByte()))
        case MessagePackFormatByte.string16:
            return try decodeString(byteCount: Int(try readBigEndian(UInt16.self)))
        case MessagePackFormatByte.string32:
            return try decodeString(byteCount: Int(try readBigEndian(UInt32.self)))

        case MessagePackFormatByte.array16:
            return try decodeArray(count: Int(try readBigEndian(UInt16.self)))
        case MessagePackFormatByte.array32:
            return try decodeArray(count: Int(try readBigEndian(UInt32.self)))

        case MessagePackFormatByte.map16:
            return try decodeMap(count: Int(try readBigEndian(UInt16.self)))
        case MessagePackFormatByte.map32:
            return try decodeMap(count: Int(try readBigEndian(UInt32.self)))

        default:
            throw MessagePackError.unsupportedFormatByte(formatByte)
        }
    }

    private mutating func decodeString(byteCount: Int) throws -> MessagePackValue {
        .string(String(decoding: try readBytes(count: byteCount), as: UTF8.self))
    }

    private mutating func decodeExtended(byteCount: Int) throws -> MessagePackValue {
        // The type byte comes after the length and before the payload.
        let type = Int8(bitPattern: try readByte())
        return .extended(type: type, bytes: try readBytes(count: byteCount))
    }

    private mutating func decodeArray(count: Int) throws -> MessagePackValue {
        var items: [MessagePackValue] = []
        items.reserveCapacity(min(count, bytes.count - position))

        for _ in 0..<count {
            items.append(try decodeNextValue())
        }
        return .array(items)
    }

    private mutating func decodeMap(count: Int) throws -> MessagePackValue {
        var pairs: [MessagePackKeyValuePair] = []
        pairs.reserveCapacity(min(count, bytes.count - position))

        for _ in 0..<count {
            let key = try decodeNextValue()
            pairs.append(MessagePackKeyValuePair(key: key, value: try decodeNextValue()))
        }
        return .map(pairs)
    }

    private mutating func readByte() throws -> UInt8 {
        guard position < bytes.count else {
            throw MessagePackError.needsMoreBytes
        }
        defer { position += 1 }
        return bytes[position]
    }

    private mutating func readBytes(count: Int) throws -> [UInt8] {
        guard position + count <= bytes.count else {
            throw MessagePackError.needsMoreBytes
        }
        defer { position += count }
        return Array(bytes[position..<(position + count)])
    }

    /// MessagePack is big-endian for every multi-byte number.
    private mutating func readBigEndian<Number: FixedWidthInteger>(_ type: Number.Type) throws -> Number {
        let width = MemoryLayout<Number>.size
        guard position + width <= bytes.count else {
            throw MessagePackError.needsMoreBytes
        }

        var number: Number = 0
        for offset in 0..<width {
            number = (number << 8) | Number(bytes[position + offset])
        }
        position += width

        return number
    }
}
