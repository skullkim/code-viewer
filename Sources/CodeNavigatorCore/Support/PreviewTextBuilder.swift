import CodeNavigatorContract

/// Turns a raw source line plus byte-offset match ranges into what the UI shows:
/// a trimmed, length-capped preview and highlight ranges that point into it.
///
/// Searching works in UTF-8 bytes (that is what the file is), while the contract and every
/// Swift/AppKit text API work in UTF-16 code units (ADR-0007). This is the one place that
/// conversion happens, so no caller has to think about it.
///
///     "  한글 needle 값"   utf8 [9,15)  →  "한글 needle 값"   utf16 [3,9)
///        └ trimmed away        └ bytes         └ preview          └ shifted + converted
public enum PreviewTextBuilder {

    /// Contract §3.1: previews are capped so one pathological minified line cannot flood the UI.
    private static let previewMaximumUtf16Length = 200

    /// Signatures sit in a single result row, so they are capped tighter than previews.
    private static let signatureMaximumUtf16Length = 120

    public static func makePreview(
        line: String,
        utf8MatchRanges: [Range<Int>]
    ) -> (previewText: String, matchRanges: [MatchRange]) {
        let previewText = truncated(trimmed(line), toUtf16Length: previewMaximumUtf16Length)
        let previewLength = previewText.utf16.count

        // Trimming the indentation moves every match left by exactly that much.
        let leadingWhitespaceLength = utf16LengthOfLeadingWhitespace(in: line)

        var matchRanges: [MatchRange] = []
        matchRanges.reserveCapacity(utf8MatchRanges.count)

        for utf8Range in utf8MatchRanges {
            let start = clamped(
                utf16Offset(in: line, forUtf8Offset: utf8Range.lowerBound) - leadingWhitespaceLength,
                toPreviewLength: previewLength
            )
            let end = clamped(
                utf16Offset(in: line, forUtf8Offset: utf8Range.upperBound) - leadingWhitespaceLength,
                toPreviewLength: previewLength
            )

            // A range that the trim or the cap collapsed is not a highlight any more.
            guard start < end else {
                continue
            }
            matchRanges.append(MatchRange(start: start, end: end))
        }

        return (previewText, matchRanges)
    }

    public static func makeSignature(line: String) -> String {
        truncated(trimmed(line), toUtf16Length: signatureMaximumUtf16Length)
    }

    private static func trimmed(_ line: String) -> Substring {
        var slice = Substring(line)
        while let firstCharacter = slice.first, firstCharacter.isWhitespace {
            slice = slice.dropFirst()
        }
        while let lastCharacter = slice.last, lastCharacter.isWhitespace {
            slice = slice.dropLast()
        }
        return slice
    }

    /// Cuts only between characters, so a surrogate pair (an emoji is two UTF-16 code units)
    /// is dropped whole instead of being split into an invalid half.
    private static func truncated(_ text: Substring, toUtf16Length maximumLength: Int) -> String {
        guard text.utf16.count > maximumLength else {
            return String(text)
        }

        var truncatedText = ""
        var length = 0
        for character in text {
            let characterLength = character.utf16.count
            if length + characterLength > maximumLength {
                break
            }
            truncatedText.append(character)
            length += characterLength
        }
        return truncatedText
    }

    private static func utf16LengthOfLeadingWhitespace(in line: String) -> Int {
        var length = 0
        for character in line {
            guard character.isWhitespace else {
                break
            }
            length += character.utf16.count
        }
        return length
    }

    /// Walks the line once, accumulating both encodings' lengths, and stops at the first scalar
    /// that already starts at or past the requested byte offset.
    private static func utf16Offset(in line: String, forUtf8Offset utf8Offset: Int) -> Int {
        var bytesSeen = 0
        var offset = 0

        for scalar in line.unicodeScalars {
            if bytesSeen >= utf8Offset {
                break
            }
            bytesSeen += utf8Length(of: scalar)
            offset += UTF16.width(scalar)
        }
        return offset
    }

    /// UTF-8 byte length of one scalar, by code point range. Spelled out rather than measured
    /// through `String(scalar).utf8.count` so the conversion allocates nothing per scalar.
    private static func utf8Length(of scalar: Unicode.Scalar) -> Int {
        switch scalar.value {
        case 0x0000...0x007F: return 1
        case 0x0080...0x07FF: return 2
        case 0x0800...0xFFFF: return 3
        default: return 4
        }
    }

    private static func clamped(_ offset: Int, toPreviewLength previewLength: Int) -> Int {
        min(max(offset, 0), previewLength)
    }
}
