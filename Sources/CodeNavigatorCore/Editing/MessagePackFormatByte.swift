/// The MessagePack format bytes, from the specification. Encoder and decoder read this one table.
///
/// The `fixed…` forms pack a small length or value into the format byte itself:
///
///     0x00…0x7f  positive fixint        0x80…0x8f  fixmap (count in low nibble)
///     0xe0…0xff  negative fixint        0x90…0x9f  fixarray
///                                       0xa0…0xbf  fixstr (length in low 5 bits)
enum MessagePackFormatByte {
    static let nilValue: UInt8 = 0xc0
    static let booleanFalse: UInt8 = 0xc2
    static let booleanTrue: UInt8 = 0xc3

    static let binary8: UInt8 = 0xc4
    static let binary16: UInt8 = 0xc5
    static let binary32: UInt8 = 0xc6

    static let extended8: UInt8 = 0xc7
    static let extended16: UInt8 = 0xc8
    static let extended32: UInt8 = 0xc9
    static let fixedExtended1: UInt8 = 0xd4
    static let fixedExtended2: UInt8 = 0xd5
    static let fixedExtended4: UInt8 = 0xd6
    static let fixedExtended8: UInt8 = 0xd7
    static let fixedExtended16: UInt8 = 0xd8

    static let float32: UInt8 = 0xca
    static let float64: UInt8 = 0xcb

    static let unsignedInteger8: UInt8 = 0xcc
    static let unsignedInteger16: UInt8 = 0xcd
    static let unsignedInteger32: UInt8 = 0xce
    static let unsignedInteger64: UInt8 = 0xcf
    static let integer8: UInt8 = 0xd0
    static let integer16: UInt8 = 0xd1
    static let integer32: UInt8 = 0xd2
    static let integer64: UInt8 = 0xd3

    static let string8: UInt8 = 0xd9
    static let string16: UInt8 = 0xda
    static let string32: UInt8 = 0xdb

    static let array16: UInt8 = 0xdc
    static let array32: UInt8 = 0xdd
    static let map16: UInt8 = 0xde
    static let map32: UInt8 = 0xdf

    static let positiveFixedIntegerRange: ClosedRange<UInt8> = 0x00...0x7f
    static let negativeFixedIntegerRange: ClosedRange<UInt8> = 0xe0...0xff
    static let fixedMapRange: ClosedRange<UInt8> = 0x80...0x8f
    static let fixedArrayRange: ClosedRange<UInt8> = 0x90...0x9f
    static let fixedStringRange: ClosedRange<UInt8> = 0xa0...0xbf

    static let fixedMapPrefix: UInt8 = 0x80
    static let fixedArrayPrefix: UInt8 = 0x90
    static let fixedStringPrefix: UInt8 = 0xa0

    /// The largest count or length each fixed form can carry.
    static let fixedMapMaximumCount = 15
    static let fixedArrayMaximumCount = 15
    static let fixedStringMaximumLength = 31
    static let positiveFixedIntegerMaximum: UInt64 = 127
    static let negativeFixedIntegerMinimum: Int64 = -32
}
