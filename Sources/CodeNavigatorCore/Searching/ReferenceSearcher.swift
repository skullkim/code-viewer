import CodeNavigatorContract
import Foundation

/// Finds where a symbol name is used across the project (REQ-006).
///
/// This is **name-based approximation**: there is no type resolution, so two unrelated classes
/// with the same name land in one list. What the search does guarantee is that a hit is a whole
/// identifier — searching `Index` must not surface `buildIndex` or `AlphaIndexer`, or the list
/// stops being usable.
///
/// Definition sites are included and flagged rather than filtered out (REQ-006 AC-2).
struct ReferenceSearcher {

    /// Results are capped so one common name (`get`, `id`) cannot stall the UI. The cap is
    /// reported back so the UI can say "showing the first N".
    static let resultLimit = 1000

    func search(
        symbolName: String,
        filePaths: [String],
        rootPath: URL,
        symbolIndex: SymbolIndex
    ) async -> ReferenceSearchResult {
        guard !symbolName.isEmpty else {
            return ReferenceSearchResult(
                references: [],
                total: 0,
                truncated: false,
                limit: Self.resultLimit
            )
        }

        let matchedLines = collectMatchedLines(symbolName: symbolName, filePaths: filePaths, rootPath: rootPath)

        // The index is consulted once per kept line, after scanning — not inside the scan loop,
        // which stays synchronous and allocation-free.
        var references: [Reference] = []
        references.reserveCapacity(matchedLines.lines.count)

        for matched in matchedLines.lines {
            let isDefinition = await symbolIndex.hasDefinition(
                named: symbolName,
                atPath: matched.path,
                line: matched.line
            )
            references.append(
                Reference(
                    path: matched.path,
                    line: matched.line,
                    previewText: matched.previewText,
                    matchRanges: matched.matchRanges,
                    isDefinition: isDefinition
                )
            )
        }

        return ReferenceSearchResult(
            references: references,
            total: matchedLines.observedCount,
            truncated: matchedLines.truncated,
            limit: Self.resultLimit
        )
    }

    private func collectMatchedLines(
        symbolName: String,
        filePaths: [String],
        rootPath: URL
    ) -> (lines: [MatchedLine], observedCount: Int, truncated: Bool) {
        let needle = Array(symbolName.utf8)

        var matchedLines: [MatchedLine] = []
        var observedCount = 0
        var truncated = false

        for filePath in filePaths {
            FileLineScanner.scanLines(ofFileAt: rootPath.appendingPathComponent(filePath)) { lineNumber, line in
                let tokenRanges = wholeTokenRanges(of: needle, in: line)
                guard !tokenRanges.isEmpty else {
                    return .continueScanning
                }

                observedCount += 1

                // One reference per line: `Reference.id` is "path:line", so two hits on one line
                // would collide in the list.
                guard matchedLines.count < Self.resultLimit else {
                    truncated = true
                    return .stopScanning
                }

                // The ranges the boundary check already produced are carried through rather than
                // thrown away, so the view highlights exactly what the search matched.
                let preview = PreviewTextBuilder.makePreview(
                    line: String(decoding: line, as: UTF8.self),
                    utf8MatchRanges: tokenRanges
                )
                matchedLines.append(
                    MatchedLine(
                        path: filePath,
                        line: lineNumber,
                        previewText: preview.previewText,
                        matchRanges: preview.matchRanges
                    )
                )
                return .continueScanning
            }

            if truncated {
                break
            }
        }

        return (matchedLines.sorted(by: byPathThenLine), observedCount, truncated)
    }

    /// Every position where the name appears as a whole identifier token, as byte offsets into
    /// the line. Empty means the line does not reference the symbol.
    ///
    /// Returning the positions rather than a yes/no keeps one rule for what a reference *is*:
    /// the same boundary test that decides whether to keep the line decides what gets highlighted.
    private func wholeTokenRanges(of needle: [UInt8], in line: ArraySlice<UInt8>) -> [Range<Int>] {
        let base = line.startIndex
        var ranges: [Range<Int>] = []

        for range in ByteSequenceSearch.occurrences(of: needle, in: line) {
            let byteBefore = base + range.lowerBound - 1
            let byteAfter = base + range.upperBound

            let continuesBefore = byteBefore >= base && isIdentifierByte(line[byteBefore])
            let continuesAfter = byteAfter < line.endIndex && isIdentifierByte(line[byteAfter])

            if !continuesBefore, !continuesAfter {
                ranges.append(range)
            }
        }

        return ranges
    }

    /// Bytes that can continue an identifier. Anything from 0x80 up is part of a multi-byte
    /// character, so `사용자Index` reads as one longer identifier rather than a hit on `Index`.
    private func isIdentifierByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"),
            UInt8(ascii: "A")...UInt8(ascii: "Z"),
            UInt8(ascii: "0")...UInt8(ascii: "9"),
            UInt8(ascii: "_"):
            return true
        default:
            return byte >= 0x80
        }
    }

    private func byPathThenLine(_ left: MatchedLine, _ right: MatchedLine) -> Bool {
        left.path == right.path ? left.line < right.line : left.path < right.path
    }
}
