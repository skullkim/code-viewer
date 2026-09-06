import CodeNavigatorContract
import Foundation

/// Finds where a symbol name is used across the project (REQ-006).
///
/// Matching is by name, and a name is not a symbol. Measured on a 463-file Java repository,
/// `getId` occurs on 670 lines across 15 unrelated receiver types — a reader standing on a
/// `Member` was handed every `Organization` and `Coupon` in the project. So when the caller says
/// where the cursor was, Java hits are narrowed to the receiver type in hand (`JavaReceiverType`).
///
/// **A hit we cannot judge stays in the list.** Dropping it would delete a real reference with no
/// way for the reader to notice; keeping it costs one line of noise. Those two mistakes are not
/// the same size. The same rule covers files the resolver does not handle at all.
///
/// What the search guarantees regardless is that a hit is a whole identifier — searching `Index`
/// must not surface `buildIndex` or `AlphaIndexer`, or the list stops being usable.
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
        symbolIndex: SymbolIndex,
        origin: ReferenceQueryOrigin? = nil
    ) async -> ReferenceSearchResult {
        guard !symbolName.isEmpty else {
            return ReferenceSearchResult(
                references: [],
                total: 0,
                truncated: false,
                limit: Self.resultLimit
            )
        }

        var matchedLines = collectMatchedLines(symbolName: symbolName, filePaths: filePaths, rootPath: rootPath)

        // 좁히기는 스캔이 끝난 뒤에 한다. 스캔 루프는 동기·무할당으로 두는 편이 빠르고,
        // 무엇보다 커서 타입을 못 알아내면 좁히기 자체를 안 하므로 스캔에 조건을 섞을 이유가 없다.
        var narrowing: ReferenceNarrowing?
        if let origin,
           let receiverType = cursorReceiverType(symbolName: symbolName, origin: origin, rootPath: rootPath) {
            let narrowed = narrow(
                matchedLines.lines,
                toReceiverType: receiverType,
                symbolName: symbolName,
                rootPath: rootPath
            )
            matchedLines.lines = narrowed.kept
            matchedLines.observedCount = narrowed.kept.count
            narrowing = ReferenceNarrowing(
                receiverType: receiverType,
                discarded: narrowed.discarded,
                unresolved: narrowed.unresolved
            )
        }

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
            limit: Self.resultLimit,
            narrowing: narrowing
        )
    }

    // MARK: - 수신자 타입으로 좁히기

    /// The type the cursor was standing on, or nil when it cannot be worked out — in which case
    /// nothing is narrowed and the list is exactly what it was before.
    private func cursorReceiverType(
        symbolName: String,
        origin: ReferenceQueryOrigin,
        rootPath: URL
    ) -> String? {
        guard isJava(origin.path),
              let source = try? String(contentsOf: rootPath.appendingPathComponent(origin.path), encoding: .utf8)
        else {
            return nil
        }
        return JavaReceiverType.Resolver(source: source).receiverType(
            line: origin.line,
            symbolName: symbolName
        )
    }

    private func narrow(
        _ lines: [MatchedLine],
        toReceiverType receiverType: String,
        symbolName: String,
        rootPath: URL
    ) -> (kept: [MatchedLine], discarded: Int, unresolved: Int) {
        var kept: [MatchedLine] = []
        var discarded = 0
        var unresolved = 0

        // 파일별로 묶어서 파일당 한 번만 파싱한다. 히트마다 파싱하면 같은 파일을 수십 번 다시
        // 읽는다 — 실측으로 670건에 1.59초였고, 파일당 1회로 바꾸니 0.24초였다.
        var index = 0
        while index < lines.count {
            let path = lines[index].path
            var end = index
            while end < lines.count, lines[end].path == path { end += 1 }
            let group = lines[index..<end]
            index = end

            guard isJava(path),
                  let source = try? String(contentsOf: rootPath.appendingPathComponent(path), encoding: .utf8)
            else {
                kept.append(contentsOf: group)
                unresolved += group.count
                continue
            }

            let resolver = JavaReceiverType.Resolver(source: source)
            for matched in group {
                guard let type = resolver.receiverType(line: matched.line, symbolName: symbolName) else {
                    kept.append(matched)
                    unresolved += 1
                    continue
                }
                if type == receiverType {
                    kept.append(matched)
                } else {
                    discarded += 1
                }
            }
        }
        return (kept, discarded, unresolved)
    }

    private func isJava(_ path: String) -> Bool {
        path.hasSuffix(".java")
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
