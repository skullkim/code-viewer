import Foundation

enum JDWPReadError: Error, Sendable {
    /// 남은 바이트보다 많이 읽으려 했다.
    case outOfBounds(needed: Int, remaining: Int)
    case invalidUTF8
    case unsupportedIdentifierSize(Int)
}

/// JDWP 페이로드를 앞에서부터 읽는다.
///
/// 범위를 넘으면 **던진다.** 0 을 돌려주는 판본을 스파이크에서 써 봤는데, 그때는 크래시를
/// 막느라 그랬지만 제품에서는 반대다 — 0 은 유효한 ID 이자 유효한 길이라, 잘못 읽은 것이
/// 정상 응답과 구별되지 않는다. 파싱이 어긋난 순간에 멈추는 편이 낫다.
struct JDWPReader {
    private let bytes: [UInt8]
    private(set) var offset: Int

    init(bytes: [UInt8]) {
        self.bytes = bytes
        self.offset = 0
    }

    var remaining: Int { bytes.count - offset }

    mutating func readByte() throws -> UInt8 {
        try require(1)
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    mutating func readUInt32() throws -> UInt32 {
        try require(4)
        defer { offset += 4 }
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    mutating func readUInt64() throws -> UInt64 {
        try require(8)
        defer { offset += 8 }
        var value: UInt64 = 0
        for index in 0..<8 {
            value = value << 8 | UInt64(bytes[offset + index])
        }
        return value
    }

    /// ID 는 프로토콜상 **가변 폭**이다. `IDSizes` 를 먼저 읽고 그 값으로 읽는다 — 8 로 박으면
    /// 다른 JVM 에서 전부 어긋나고, 어긋난 채로 그럴듯한 값이 나온다.
    mutating func readIdentifier(size: Int) throws -> UInt64 {
        switch size {
        case 8: return try readUInt64()
        case 4: return UInt64(try readUInt32())
        case 2: return UInt64(try readUInt32() & 0xFFFF)
        default: throw JDWPReadError.unsupportedIdentifierSize(size)
        }
    }

    mutating func readString() throws -> String {
        let length = Int(try readUInt32())
        try require(length)
        defer { offset += length }
        guard let text = String(bytes: bytes[offset..<(offset + length)], encoding: .utf8) else {
            throw JDWPReadError.invalidUTF8
        }
        return text
    }

    mutating func skip(_ count: Int) throws {
        try require(count)
        offset += count
    }

    private func require(_ count: Int) throws {
        guard count >= 0, remaining >= count else {
            throw JDWPReadError.outOfBounds(needed: count, remaining: remaining)
        }
    }
}
