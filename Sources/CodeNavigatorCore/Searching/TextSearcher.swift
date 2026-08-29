import CodeNavigatorContract
import Foundation

/// Full-text search across the project's files (REQ-008).
///
/// Literal search runs on raw UTF-8 bytes: `String.range(of:)` compares grapheme clusters and
/// measured 4.6× slower on the same corpus (ADR-0004). Byte offsets are then converted to the
/// contract's UTF-16 offsets by `PreviewTextBuilder`, which is why that type takes bytes in.
///
/// An invalid regular expression is an **error**, never zero results (REQ-008 AC-2): a silent
/// empty list would tell the user their code contains no matches, which is a different claim.
///
/// Only the files the scanner listed are read, so exclusions cannot drift from what the tree
/// shows and the index holds (REQ-008 AC-3).
struct TextSearcher {

    /// Full-text hits are capped and the cap is reported, so the UI can say "showing the first N"
    /// instead of silently pretending the list is complete (REQ-008 AC-4).
    static let resultLimit = 500

    func search(
        query: String,
        mode: TextSearchMode,
        filePaths: [String],
        rootPath: URL
    ) throws -> TextSearchResult {
        guard !query.isEmpty else {
            return TextSearchResult(
                items: [], total: 0, truncated: false, limit: Self.resultLimit, filesSearched: 0
            )
        }

        let strategy = try makeStrategy(query: query, mode: mode)

        var items: [TextSearchItem] = []
        var observedCount = 0
        var truncated = false
        var filesSearched = 0

        for filePath in filePaths {
            filesSearched += 1
            FileLineScanner.scanLines(ofFileAt: rootPath.appendingPathComponent(filePath)) { lineNumber, line in
                guard let preview = makePreview(ofLine: line, using: strategy) else {
                    return .continueScanning
                }

                observedCount += 1

                // One item per line: `TextSearchItem.id` is "path:line", and the several hits a
                // line can hold are carried as several ranges inside that one item.
                guard items.count < Self.resultLimit else {
                    truncated = true
                    return .stopScanning
                }

                items.append(
                    TextSearchItem(
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

        return TextSearchResult(
            items: items.sorted(by: byPathThenLine),
            total: observedCount,
            truncated: truncated,
            limit: Self.resultLimit,
            filesSearched: filesSearched
        )
    }

    /// Returns nil when the line does not match, so the caller can skip it without deciding what
    /// an empty range list means.
    private func makePreview(
        ofLine line: ArraySlice<UInt8>,
        using strategy: TextSearchStrategy
    ) -> (previewText: String, matchRanges: [MatchRange])? {
        switch strategy {
        case .literal(let needle):
            // Match on bytes first; decoding the line is only worth it once it has a hit.
            let byteRanges = ByteSequenceSearch.occurrences(of: needle, in: line)
            guard !byteRanges.isEmpty else {
                return nil
            }
            return PreviewTextBuilder.makePreview(
                line: String(decoding: line, as: UTF8.self),
                utf8MatchRanges: byteRanges
            )

        case .regularExpression(let regularExpression):
            let lineText = String(decoding: line, as: UTF8.self)
            let utf16Ranges = utf16Ranges(matching: regularExpression, in: lineText)
            guard !utf16Ranges.isEmpty else {
                return nil
            }
            return PreviewTextBuilder.makePreview(line: lineText, utf16MatchRanges: utf16Ranges)
        }
    }

    /// `NSRegularExpression` reports matches in UTF-16 code units, which is already the
    /// contract's offset unit — no conversion, and no chance of one going wrong.
    private func utf16Ranges(
        matching regularExpression: NSRegularExpression,
        in lineText: String
    ) -> [Range<Int>] {
        let wholeLine = NSRange(lineText.startIndex..., in: lineText)

        return regularExpression.matches(in: lineText, options: [], range: wholeLine)
            .compactMap { match in
                // A zero-width match (`x*` against a line without `x`) highlights nothing.
                guard match.range.location != NSNotFound, match.range.length > 0 else {
                    return nil
                }
                return match.range.location..<(match.range.location + match.range.length)
            }
    }

    private func makeStrategy(query: String, mode: TextSearchMode) throws -> TextSearchStrategy {
        switch mode {
        case .literal:
            return .literal(needle: Array(query.utf8))

        case .regularExpression:
            do {
                return .regularExpression(try NSRegularExpression(pattern: query, options: []))
            } catch {
                throw NavigatorError.invalidRegularExpression(
                    pattern: query,
                    reason: error.localizedDescription
                )
            }
        }
    }

    private func byPathThenLine(_ left: TextSearchItem, _ right: TextSearchItem) -> Bool {
        left.path == right.path ? left.line < right.line : left.path < right.path
    }
}
