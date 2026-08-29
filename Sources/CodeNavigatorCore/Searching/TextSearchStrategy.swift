import Foundation

/// How one query was compiled, decided once per search rather than per line.
///
/// The literal case carries UTF-8 bytes because literal matching runs on the raw file bytes;
/// the regular-expression case carries a compiled pattern, which is also where an invalid
/// pattern is rejected — before a single file is opened.
enum TextSearchStrategy {
    case literal(needle: [UInt8])
    case regularExpression(NSRegularExpression)
}
