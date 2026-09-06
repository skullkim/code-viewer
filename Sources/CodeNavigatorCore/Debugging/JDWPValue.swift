import Foundation

/// A value the JVM handed back, still in JDWP's tagged form.
///
/// 태그를 보고 폭이 정해진다 — `I` 는 4바이트, `J` 는 8바이트, `L` 은 objectID 폭. 태그를
/// 무시하고 고정 폭으로 읽으면 그 다음 값부터 전부 밀린다. 지역 변수 목록은 값을 줄줄이
/// 이어 보내므로, 하나 밀리면 나머지가 전부 쓰레기가 된다.
enum JDWPValue: Sendable, Hashable {
    case boolean(Bool)
    case byte(Int8)
    case char(UInt16)
    case short(Int16)
    case int(Int32)
    case long(Int64)
    case float(Float)
    case double(Double)
    /// `null` 을 포함한다 — objectID 0 이 null 이다.
    case object(tag: Character, id: UInt64)
    case void

    /// 화면에 그대로 쓸 수 있는 표기.
    var displayText: String {
        switch self {
        case .boolean(let value): return value ? "true" : "false"
        case .byte(let value): return "\(value)"
        case .char(let value):
            let scalar = Unicode.Scalar(value).map { String(Character($0)) } ?? "?"
            return "'\(scalar)'"
        case .short(let value): return "\(value)"
        case .int(let value): return "\(value)"
        case .long(let value): return "\(value)"
        case .float(let value): return "\(value)"
        case .double(let value): return "\(value)"
        case .object(let tag, let id):
            guard id != 0 else { return "null" }
            return tag == "s" ? "String@\(id)" : "\(objectKindName(tag))@\(id)"
        case .void: return "void"
        }
    }

    private func objectKindName(_ tag: Character) -> String {
        switch tag {
        case "[": return "Array"
        case "t": return "Thread"
        case "g": return "ThreadGroup"
        case "l": return "ClassLoader"
        case "c": return "Class"
        default: return "Object"
        }
    }
}

extension JDWPReader {
    /// Reads one tagged value. The tag decides the width, so this cannot be split into
    /// "read tag" and "read N bytes" by the caller.
    mutating func readTaggedValue(objectIDSize: Int) throws -> JDWPValue {
        let tag = Character(UnicodeScalar(try readByte()))
        return try readValue(tag: tag, objectIDSize: objectIDSize)
    }

    mutating func readValue(tag: Character, objectIDSize: Int) throws -> JDWPValue {
        switch tag {
        case "Z": return .boolean(try readByte() != 0)
        case "B": return .byte(Int8(bitPattern: try readByte()))
        // `C` 와 `S` 는 2바이트다. 4바이트로 읽으면 그 다음 값부터 전부 밀리고, 밀린 값은
        // 예외가 아니라 그럴듯한 숫자로 나온다.
        case "C": return .char(try readUInt16())
        case "S": return .short(Int16(bitPattern: try readUInt16()))
        case "I": return .int(try readInt32())
        case "J": return .long(Int64(bitPattern: try readUInt64()))
        case "F": return .float(Float(bitPattern: try readUInt32()))
        case "D": return .double(Double(bitPattern: try readUInt64()))
        case "V": return .void
        default:
            // 나머지는 전부 objectID 폭이다: L(객체) s(문자열) [(배열) t(스레드) 등.
            return .object(tag: tag, id: try readIdentifier(size: objectIDSize))
        }
    }
}

extension JDWPReader {
    mutating func readUInt16() throws -> UInt16 {
        let high = UInt16(try readByte())
        let low = UInt16(try readByte())
        return high << 8 | low
    }
}
