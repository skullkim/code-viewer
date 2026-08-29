import Foundation

/// Reads a file as UTF-8 **bytes** and hands its lines to a caller one at a time.
///
/// Searching works on bytes rather than on `String` for two reasons. `String.range(of:)` compares
/// grapheme clusters and measured 4.6× slower on the same corpus (ADR-0004), and byte offsets are
/// exactly what `PreviewTextBuilder` converts into the UTF-16 offsets the contract speaks in.
///
/// Lines are handed over as slices of one buffer, so scanning a file allocates one array, not one
/// string per line.
enum FileLineScanner {
    private static let newlineByte = UInt8(ascii: "\n")
    private static let carriageReturnByte = UInt8(ascii: "\r")
    private static let nullByte: UInt8 = 0

    /// How far into a file to look for a NUL byte before calling it binary. A NUL in the first
    /// few kilobytes is the same heuristic grep-like tools use, and it keeps images and jars from
    /// producing mojibake previews.
    private static let binaryProbeByteCount = 8_000

    static func scanLines(
        ofFileAt fileURL: URL,
        body: (_ lineNumber: Int, _ line: ArraySlice<UInt8>) -> LineScanDecision
    ) {
        // An unreadable file is skipped rather than fatal: one permission-denied file must not
        // abort a project-wide search.
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            return
        }

        let bytes = [UInt8](data)
        guard !isBinary(bytes) else {
            return
        }

        var lineNumber = 1
        var lineStart = 0
        var index = 0

        while index < bytes.count {
            guard bytes[index] == newlineByte else {
                index += 1
                continue
            }

            if body(lineNumber, line(in: bytes, from: lineStart, to: index)) == .stopScanning {
                return
            }

            lineNumber += 1
            index += 1
            lineStart = index
        }

        // A file not ending in a newline still has a last line.
        if lineStart < bytes.count {
            _ = body(lineNumber, line(in: bytes, from: lineStart, to: bytes.count))
        }
    }

    /// Drops the carriage return of a CRLF file so previews and offsets match what the user sees.
    private static func line(in bytes: [UInt8], from start: Int, to end: Int) -> ArraySlice<UInt8> {
        var lineEnd = end
        if lineEnd > start, bytes[lineEnd - 1] == carriageReturnByte {
            lineEnd -= 1
        }
        return bytes[start..<lineEnd]
    }

    private static func isBinary(_ bytes: [UInt8]) -> Bool {
        bytes.prefix(binaryProbeByteCount).contains(nullByte)
    }
}
