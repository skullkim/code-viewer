/// Builds the one-line signature shown next to a symbol.
///
/// The limit is counted in UTF-16 code units to match every other offset in the contract
/// (ADR-0007), and truncation never splits a surrogate pair.
enum SignatureBuilder {
    static let maximumLength = 120

    static func signature(forLine line: some StringProtocol) -> String {
        truncate(String(line).trimmingCharactersInWhitespace(), toUTF16Length: maximumLength)
    }

    /// Truncates to at most `limit` UTF-16 code units, stepping back off a trailing high
    /// surrogate so a split surrogate pair can never be produced.
    static func truncate(_ text: String, toUTF16Length limit: Int) -> String {
        let units = Array(text.utf16)
        guard units.count > limit else { return text }

        var end = limit
        if end > 0, Self.isHighSurrogate(units[end - 1]) {
            end -= 1
        }
        return String(decoding: units[0..<end], as: UTF16.self)
    }

    private static func isHighSurrogate(_ unit: UInt16) -> Bool {
        (0xD800...0xDBFF).contains(unit)
    }
}

extension StringProtocol {
    /// Trims leading and trailing whitespace without pulling in a character-set dependency.
    func trimmingCharactersInWhitespace() -> String {
        var view = Substring(self)
        while let first = view.first, first.isWhitespace {
            view = view.dropFirst()
        }
        while let last = view.last, last.isWhitespace {
            view = view.dropLast()
        }
        return String(view)
    }
}
